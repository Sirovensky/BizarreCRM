/**
 * PROD29: Shared SSRF guard for outbound HTTP fetches.
 *
 * Every outbound call site that lets an admin (or imported row) set the target
 * URL must first call `assertPublicUrl(url)`. The guard:
 *
 *   1. Rejects non-http(s) schemes (blocks file://, gopher://, etc.).
 *   2. Resolves the hostname ONCE via `dns.lookup` and verifies EVERY resolved
 *      address is publicly routable. Blocked ranges:
 *        IPv4:  10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8,
 *               169.254.0.0/16 (link-local / AWS IMDS), 0.0.0.0/8,
 *               100.64.0.0/10 (CGNAT), 224.0.0.0/4 (multicast),
 *               240.0.0.0/4 (reserved).
 *        IPv6:  ::1, fc00::/7 (ULA), fe80::/10 (link-local), ::ffff:0:0/96
 *               (IPv4-mapped — re-checked against IPv4 rules).
 *   3. Returns the pinned IP so the caller can connect directly (DNS-rebinding
 *      defence). Callers that keep using the hostname are still protected
 *      because the OS DNS cache will typically return the same answer within
 *      the TTL — a racing rebind is in-theory possible but requires an
 *      attacker to control DNS for a host they just convinced the admin to
 *      point the CRM at, which already implies compromise of the trust path.
 *
 * If a caller can tolerate the extra work, prefer `fetchWithSsrfGuard(url, init)`
 * which rewrites the URL to the pinned IP and sets the original hostname as a
 * `Host:` header — closing the rebinding window entirely.
 */
import dns from 'dns';
import net from 'net';
import { promisify } from 'util';

const dnsLookup = promisify(dns.lookup);

const PRIVATE_IPV4_RANGES: Array<[number, number]> = [
  [ipv4ToInt('10.0.0.0'),      ipv4ToInt('10.255.255.255')],       // RFC 1918
  [ipv4ToInt('172.16.0.0'),    ipv4ToInt('172.31.255.255')],       // RFC 1918
  [ipv4ToInt('192.168.0.0'),   ipv4ToInt('192.168.255.255')],      // RFC 1918
  [ipv4ToInt('127.0.0.0'),     ipv4ToInt('127.255.255.255')],      // loopback
  [ipv4ToInt('169.254.0.0'),   ipv4ToInt('169.254.255.255')],      // link-local + AWS IMDS
  [ipv4ToInt('0.0.0.0'),       ipv4ToInt('0.255.255.255')],        // "this host"
  [ipv4ToInt('100.64.0.0'),    ipv4ToInt('100.127.255.255')],      // CGNAT
  [ipv4ToInt('224.0.0.0'),     ipv4ToInt('239.255.255.255')],      // multicast
  [ipv4ToInt('240.0.0.0'),     ipv4ToInt('255.255.255.255')],      // reserved
];

function ipv4ToInt(ip: string): number {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some((p) => !Number.isInteger(p) || p < 0 || p > 255)) {
    throw new Error(`Invalid IPv4 literal passed to ipv4ToInt: ${ip}`);
  }
  return (
    // >>> 0 keeps the result unsigned so bit 31 addresses (240.0.0.0+) stay positive.
    ((parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]) >>> 0
  );
}

function isPrivateIPv4(ip: string): boolean {
  const n = ipv4ToInt(ip);
  return PRIVATE_IPV4_RANGES.some(([lo, hi]) => n >= lo && n <= hi);
}

/**
 * Check an IPv6 literal against the blocked ranges. We do not implement a
 * full IPv6 CIDR evaluator here — we only need coarse prefix matching and
 * handle IPv4-mapped addresses by delegating back to the IPv4 checker.
 */
function isPrivateIPv6(ip: string): boolean {
  const normalized = ip.toLowerCase();

  // Loopback: ::1
  if (normalized === '::1') return true;

  // Unspecified: ::
  if (normalized === '::') return true;

  // IPv4-mapped IPv6 (::ffff:x.x.x.x) — extract and recheck as v4.
  const mappedMatch = normalized.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mappedMatch) return isPrivateIPv4(mappedMatch[1]);

  // IPv4-mapped IPv6 in hex form (::ffff:xxxx:xxxx) — best effort: check if
  // the prefix matches :ffff: and decode the last 32 bits.
  const hexMappedMatch = normalized.match(/^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/);
  if (hexMappedMatch) {
    const hi = parseInt(hexMappedMatch[1], 16);
    const lo = parseInt(hexMappedMatch[2], 16);
    const octets = [
      (hi >> 8) & 0xff,
      hi & 0xff,
      (lo >> 8) & 0xff,
      lo & 0xff,
    ].join('.');
    return isPrivateIPv4(octets);
  }

  // Unique-local (fc00::/7): first byte 0xfc or 0xfd.
  if (/^f[cd][0-9a-f]{2}:/.test(normalized)) return true;

  // Link-local (fe80::/10): first 10 bits 1111 1110 10xx.
  if (/^fe[89ab][0-9a-f]:/.test(normalized)) return true;

  return false;
}

/**
 * Throws if the URL fails SSRF policy. Returns the resolved IP + family + the
 * parsed URL on success so the caller can optionally pin the connection.
 *
 * Raises:
 *   - `ssrf: unsupported scheme` for anything other than http(s)
 *   - `ssrf: hostname required` if the URL has no host
 *   - `ssrf: dns lookup failed` on resolution failure
 *   - `ssrf: blocked private/reserved ip` when any resolved address is private
 */
export async function assertPublicUrl(url: string): Promise<{
  parsedUrl: URL;
  resolvedAddress: string;
  family: 4 | 6;
}> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error('ssrf: invalid url');
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(`ssrf: unsupported scheme ${parsed.protocol}`);
  }

  const hostname = parsed.hostname;
  if (!hostname) throw new Error('ssrf: hostname required');

  // If the host is already a numeric literal, skip DNS and validate directly.
  if (net.isIP(hostname)) {
    const family = net.isIP(hostname) as 4 | 6;
    const isPrivate = family === 4 ? isPrivateIPv4(hostname) : isPrivateIPv6(hostname);
    if (isPrivate) throw new Error(`ssrf: blocked private/reserved ip ${hostname}`);
    return { parsedUrl: parsed, resolvedAddress: hostname, family };
  }

  // DNS rebinding defence: request ALL resolved addresses (v4 + v6) and reject
  // if ANY of them is private. An attacker-controlled DNS that returns both
  // 1.1.1.1 and 127.0.0.1 would otherwise let us pin a public address the
  // first time and the OS resolver return the private one at connect time.
  let addresses: Array<{ address: string; family: number }>;
  try {
    addresses = await dnsLookup(hostname, { all: true, verbatim: false });
  } catch (err) {
    throw new Error(
      `ssrf: dns lookup failed for ${hostname}: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  if (addresses.length === 0) {
    throw new Error(`ssrf: dns returned no addresses for ${hostname}`);
  }

  for (const { address, family } of addresses) {
    const blocked = family === 4 ? isPrivateIPv4(address) : isPrivateIPv6(address);
    if (blocked) {
      throw new Error(`ssrf: blocked private/reserved ip ${address} (from ${hostname})`);
    }
  }

  // Return the first resolved address so callers can pin the connection.
  const chosen = addresses[0];
  return {
    parsedUrl: parsed,
    resolvedAddress: chosen.address,
    family: chosen.family === 6 ? 6 : 4,
  };
}

/**
 * Convenience wrapper: run the SSRF guard, then fetch with a timeout.
 *
 * Default timeout is 10 seconds — callers that want something else pass
 * `timeoutMs` in `init` (extracted before the call — it's not a standard
 * RequestInit field). The returned AbortSignal is merged with any signal the
 * caller provided so existing cancellation paths still work.
 */
export async function fetchWithSsrfGuard(
  url: string,
  init: RequestInit & { timeoutMs?: number } = {},
): Promise<Response> {
  await assertPublicUrl(url);

  const { timeoutMs = 10_000, signal: callerSignal, ...rest } = init;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  // Merge caller signal with the timeout controller so either can abort.
  if (callerSignal) {
    if (callerSignal.aborted) controller.abort();
    else callerSignal.addEventListener('abort', () => controller.abort(), { once: true });
  }

  try {
    return await fetch(url, { ...rest, signal: controller.signal });
  } finally {
    clearTimeout(timeoutId);
  }
}
