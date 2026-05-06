# T10 — DNS Rebinding, URL Parser Confusion, Request-Library SSRF Nuances

**Scope:** `utils/ssrfGuard.ts`, `geocode.routes.ts`, `services/cloudflareDns.ts`, `services/githubUpdater.ts`, `services/catalogScraper.ts`, `services/catalogSync.ts`, `services/walletPass.ts`, `services/repairShoprImport.ts`, `services/repairDeskImport.ts`, `services/myRepairAppImport.ts`, `services/email.ts`, `services/webhooks.ts`, `services/notifications.ts`  
**Investigator:** Agent T10  
**Date:** 2026-05-06

---

## IP-Pinning Verification

`assertPublicUrl` resolves DNS and validates all returned addresses, then returns `{ resolvedAddress, family }`. `fetchWithSsrfGuard` (the IP-pinning wrapper) installs an undici `Agent` with a `connect.lookup` callback that short-circuits to the pre-validated address, preventing re-resolution at connect time. **However, `fetchWithSsrfGuard` is never called anywhere in the codebase.** Every real fetch site calls `assertPublicUrl` then immediately invokes the global `fetch()`, which re-resolves DNS via the OS resolver. This exposes every SSRF-guarded call site to the DNS rebinding TOCTOU described below.

---

### [MEDIUM] webhooks.ts: SSRF guard run before each fetch attempt but connection not IP-pinned — DNS rebinding window

**Where:** `packages/server/src/services/webhooks.ts:284–305`

**What:**
`attemptDelivery` calls `assertWebhookUrl(url)` (lines 283–299) to validate DNS-resolved addresses, then immediately issues `fetch(url, ...)` (line 305) without binding the connection to the pre-validated IP. The OS resolver is re-invoked at TCP connect time. An admin who controls a domain's DNS can use a TTL=0 authoritative server to return a public IP for the guard's `dns.lookup` call and flip the answer to a private/reserved IP (e.g. `169.254.169.254`) by the time the undici connection handler resolves the same hostname milliseconds later. Unlike `catalogScraper.ts`, the webhook target URL is admin-configurable (`store_config.webhook_url`) and `redirect: 'error'` is set, but IP pinning is absent.

**Code:**
```typescript
// webhooks.ts:283-305
try {
  await assertWebhookUrl(url);   // DNS check → validates IPs once
} catch (err: unknown) {
  // ... SSRF block logged ...
  return { ok: false, ... };
}
// gap: OS re-resolves DNS here; if TTL=0 DNS flipped to private IP, guard is bypassed
const res = await fetch(url, {
  method: 'POST',
  redirect: 'error',   // redirects blocked, but DNS rebinding still possible
  ...
});
```

**Exploit:**
Admin configures `webhook_url = http://evil.example.com/` where `evil.example.com` is served by an attacker-controlled TTL=0 DNS server. First assertion: DNS returns `1.2.3.4` (public) → guard passes. Between guard return and fetch connect (< 1 ms), DNS is flipped to `169.254.169.254` → the TCP connection reaches AWS IMDS. The server POSTs the signed event payload (including tenant data) to the IMDS endpoint and may receive cloud credentials in the response. Re-run on every retry attempt since the guard fires once per attempt.

**Fix:**
Replace `assertWebhookUrl(url)` + `fetch(url, ...)` with `fetchWithSsrfGuard(url, { method: 'POST', redirect: 'error', body, headers, timeoutMs: ATTEMPT_TIMEOUT_MS })` from `ssrfGuard.ts:190`. This pins the undici connection to the pre-validated IP address, closing the TOCTOU window entirely.

---

### [LOW] fetchWithSsrfGuard defined but never called — IP pinning dead code

**Where:** `packages/server/src/utils/ssrfGuard.ts:190–229`

**What:**
`fetchWithSsrfGuard` implements correct DNS-rebinding defence by installing a per-request undici `Agent` whose `connect.lookup` callback returns the pre-validated IP, ensuring the OS resolver is never consulted at connect time. This is exactly the fix needed for `catalogScraper.ts` and `webhooks.ts`. However, `fetchWithSsrfGuard` is exported but has zero callers in the entire codebase — both existing SSRF-guarded fetch sites call `assertPublicUrl` directly and then use the global `fetch()`. The defensive wrapper provides no protection in its current state.

**Code:**
```typescript
// ssrfGuard.ts:190 — exported, never imported anywhere else
export async function fetchWithSsrfGuard(
  url: string,
  init: RequestInit & { timeoutMs?: number } = {},
): Promise<Response> {
  const { resolvedAddress, family } = await assertPublicUrl(url);
  // ... installs pinnedAgent with lookup callback ...
}
// Zero grep results for fetchWithSsrfGuard outside this file
```

**Exploit:**
Indirect — the dead code means all current SSRF-guarded fetch sites lack IP pinning. See webhooks.ts MEDIUM and catalogScraper.ts LOW (S15) for concrete exploitation paths.

**Fix:**
Replace `assertPublicUrl` + `fetch` call-pairs in `catalogScraper.ts:414–417` and `webhooks.ts:284–305` with `fetchWithSsrfGuard`. Remove the two-step pattern from the codebase to prevent future sites from copying the unsafe pattern.

---

### [LOW] isPrivateIPv6 does not block deprecated IPv6 site-local range fec0::/10

**Where:** `packages/server/src/utils/ssrfGuard.ts:96–101`, mirrored at `services/webhooks.ts:98–103`

**What:**
`isPrivateIPv6` blocks `fc00::/7` (ULA, prefix `f[cd]`) and `fe80::/10` (link-local, prefix `fe[89ab]`). It does not block `fec0::/10` (deprecated site-local, RFC 3879 §4), whose second byte ranges from `0xc0` to `0xff` — the first hex nibble of the second byte is `c` through `f`, which is not matched by `[89ab]` and not caught by `^f[cd]` (which only covers `fc` and `fd`, not `fe`). If a DNS server returns an address in `fec0::/10`, `isPrivateIPv6` returns `false` and the address is treated as public. Site-local addresses were deprecated in 2004 but some enterprise networks still route them.

**Code:**
```typescript
// ssrfGuard.ts:95-101
if (/^f[cd][0-9a-f]{2}:/.test(normalized)) return true;   // fc00::/7 ULA
if (/^fe[89ab][0-9a-f]:/.test(normalized)) return true;    // fe80::/10 link-local
// fec0::/10 (fe[c-f][0-9a-f]):  not matched by either pattern → returns false
return false;
```

**Exploit:**
Requires an environment where `fec0::/10` addresses are routed to internal services and a DNS server returns such an address. Not exploitable in most deployments (site-local is deprecated/unrouted). An attacker-controlled DNS returning `fec0::1` as the resolved address for a webhook target would bypass the guard on vulnerable networks.

**Fix:**
Add `/^fe[c-f][0-9a-f]{2}:/.test(normalized)` or the broader check `/^fe[89a-f][0-9a-f]{2}:/.test(normalized)` to `isPrivateIPv6` to cover the full `fe80::/10` through `feff::/16` range. Update both `ssrfGuard.ts` and the duplicated logic in `webhooks.ts`.

---

### [INFO] Hex/octal/decimal IPv4 literals safely normalized by WHATWG URL parser

**Where:** `packages/server/src/utils/ssrfGuard.ts:119–139`

**What:**
`assertPublicUrl` uses `new URL(url)` before extracting `parsed.hostname`. Node 22's WHATWG URL implementation normalizes non-standard IPv4 notation in URLs to dotted-decimal form before parsing: `http://0x7f000001/` → hostname `127.0.0.1`; `http://2130706433/` (decimal) → `127.0.0.1`; `http://017700000001/` (octal) → `127.0.0.1`; `http://127.1/` (short form) → `127.0.0.1`. All of these are then caught by `net.isIP(hostname) === 4` followed by `isPrivateIPv4('127.0.0.1') === true`. Alternate non-standard IP forms are **not a bypass** on this Node version.

**Code:**
```typescript
// Node 22 URL parser: verified via node -e
// new URL('http://0x7f000001/').hostname  →  '127.0.0.1'
// new URL('http://2130706433/').hostname  →  '127.0.0.1'
// new URL('http://017700000001/').hostname  →  '127.0.0.1'
// All caught by isPrivateIPv4 check in assertPublicUrl
```

**Exploit:**
None — the URL parser normalization closes this attack vector on Node 22. Would need re-verification on a Node version that doesn't normalize (Node < 18 had inconsistencies). Hardening recommendation: add an explicit blocklist test for these forms if the codebase is expected to run on Node < 18.

---

### [INFO] Wildcard DNS services (nip.io, sslip.io) mitigated by DNS resolution check

**Where:** `packages/server/src/utils/ssrfGuard.ts:141–172`, `services/webhooks.ts:179–203`

**What:**
Wildcard DNS services like `127.0.0.1.nip.io` and `127.0.0.1.sslip.io` resolve to `127.0.0.1`. An attacker could configure `webhook_url = http://127.0.0.1.nip.io/` hoping the hostname pattern check misses the numeric IP-in-name. Both `assertPublicUrl` and `assertWebhookUrl` call `dns.lookup(hostname, { all: true })` and check every returned IP against the private ranges. Since `127.0.0.1.nip.io` resolves to `127.0.0.1`, `isPrivateIPv4('127.0.0.1') === true` and the URL is blocked. The DNS-resolution approach catches this class of bypass by design.

**Code:**
```typescript
// assertPublicUrl: resolves all IPs, checks each one
for (const { address, family } of addresses) {
  const blocked = family === 4 ? isPrivateIPv4(address) : isPrivateIPv6(address);
  if (blocked) throw new Error(`ssrf: blocked private/reserved ip ${address} (from ${hostname})`);
}
```

**Exploit:**
None — DNS-resolution-based guard correctly blocks wildcard DNS bypass.

---

### [INFO] IDN homograph attack mitigated by DNS resolution — resolved IP is checked not hostname label

**Where:** `packages/server/src/utils/ssrfGuard.ts:141–172`

**What:**
An IDN homograph attack uses a Punycode domain whose Unicode rendering looks identical to a legitimate domain (e.g. `xn--internal-look-alike.com` visually matches `internal.example.com`). The WHATWG URL parser preserves Punycode labels as-is in `hostname`. The guard's `dns.lookup` call resolves the Punycode hostname via the OS IDNA resolver; if the domain resolves to a private IP, `isPrivateIPv4` / `isPrivateIPv6` catches it. IDN homographs that actually resolve to private IPs are blocked. Domains designed to look like internal names but resolving to public IPs are harmless to the guard.

---

### [INFO] IPv6 literal URLs blocked via ENOTFOUND, not via isPrivateIPv6 policy check

**Where:** `packages/server/src/utils/ssrfGuard.ts:130–139`

**What:**
`new URL('http://[::1]/').hostname` returns `'[::1]'` (with brackets, per WHATWG spec). `net.isIP('[::1]') === 0`, so the guard skips the IP-literal fast path and falls through to `dns.lookup('[::1]', { all: true })`, which returns `ENOTFOUND`. The URL is correctly rejected but with the error message `ssrf: dns lookup failed` rather than `ssrf: blocked private/reserved ip`. The `isPrivateIPv6` function is never reached for bracketed IPv6 literals in practice. This is a correctness gap (wrong error code) but not a security bypass since the connection is still rejected.

**Fix (cosmetic):** Strip brackets from the hostname before the `net.isIP` check: `const rawHost = hostname.startsWith('[') && hostname.endsWith(']') ? hostname.slice(1, -1) : hostname;` then pass `rawHost` to `net.isIP`. Apply the same fix in `webhooks.ts`.

---

