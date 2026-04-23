import { config } from '../config.js';
import { createBreaker } from '../utils/circuitBreaker.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('cloudflareDns');

// SEC-H77: Circuit breaker for Cloudflare DNS API calls.
const cloudflareBreaker = createBreaker('cloudflare');

/**
 * Cloudflare DNS auto-provisioning.
 *
 * Thin wrapper around the Cloudflare DNS API v4 used by tenant provisioning
 * to create/delete a proxied A record per shop subdomain.
 *
 * Free-plan Universal SSL automatically covers every proxied first-level
 * subdomain, so no cert management is required on the origin — Cloudflare's
 * edge terminates TLS with a trusted cert for every {slug}.{baseDomain}.
 *
 * API reference: https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-list-dns-records
 */

const CF_API_BASE = 'https://api.cloudflare.com/client/v4';
const CF_REQUEST_TIMEOUT_MS = 10_000;
// @audit-fixed: explicit max-retry cap and base delay so 429 rate-limit responses
// no longer immediately fail tenant provisioning. Cloudflare returns 429 when the
// per-zone DNS-record write quota is exceeded (or burst from many tenants signing
// up at once). Without retry/backoff the provisioning helper just threw, leaving
// tenants in a half-created state.
const CF_MAX_RETRIES = 3;
const CF_RETRY_BASE_MS = 1000;

interface CloudflareEnvelope<T> {
  success: boolean;
  errors: Array<{ code: number; message: string }>;
  messages: Array<{ code: number; message: string }>;
  result: T;
  result_info?: { count: number; page: number; per_page: number; total_count: number };
}

interface DnsRecord {
  id: string;
  type: string;
  name: string;
  content: string;
  proxied: boolean;
  ttl: number;
  comment?: string | null;
}

/**
 * Build the full hostname for a tenant slug (e.g. "shop1" → "shop1.example.com").
 * Cloudflare's list endpoint returns full names, so we use them consistently
 * for exact-match lookups.
 *
 * @audit-fixed: validate the slug shape before interpolating into either the
 * URL or the JSON payload. Slugs should always pass through tenant-provisioning
 * validation first, but defense-in-depth: reject anything that contains a dot,
 * slash, or non-DNS-safe character so a corrupted DB row cannot poison the API
 * call.
 */
function buildRecordName(slug: string): string {
  if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(slug)) {
    throw new Error(`Invalid tenant slug for DNS record: "${slug}" — must be DNS-label safe`);
  }
  return `${slug}.${config.baseDomain}`;
}

/**
 * Make an authenticated request to the Cloudflare API with timeout and
 * standard envelope parsing. Throws a descriptive error on non-200 or
 * `success: false` responses.
 */
async function cfRequest<T>(path: string, init: RequestInit = {}): Promise<CloudflareEnvelope<T>> {
  if (!config.cloudflareApiToken || !config.cloudflareZoneId) {
    throw new Error('Cloudflare API not configured (missing CLOUDFLARE_API_TOKEN or CLOUDFLARE_ZONE_ID)');
  }

  // @audit-fixed: retry with capped exponential backoff on HTTP 429 / 5xx so a transient
  // rate limit doesn't kill tenant provisioning. We retry at most CF_MAX_RETRIES times
  // and respect Cloudflare's `Retry-After` header when present.
  let lastErr: Error | null = null;
  for (let attempt = 0; attempt <= CF_MAX_RETRIES; attempt++) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), CF_REQUEST_TIMEOUT_MS);

    try {
      const res = await cloudflareBreaker.run(() =>
        fetch(`${CF_API_BASE}${path}`, {
          ...init,
          headers: {
            'Authorization': `Bearer ${config.cloudflareApiToken}`,
            'Content-Type': 'application/json',
            ...(init.headers || {}),
          },
          signal: controller.signal,
        }),
      );

      // Retryable: 429 Too Many Requests, 502/503/504 transient. Honor Retry-After.
      // SEC-L17: add ±25% jitter to the exponential backoff so that a burst of
      // signup provisioning events (each doing its own CF call) doesn't
      // thundering-herd on the same retry window after a shared 429 — with a
      // pure deterministic backoff every retry attempt bunches at exactly
      // base*2^attempt and we just re-trigger the rate limit.
      if (res.status === 429 || res.status === 502 || res.status === 503 || res.status === 504) {
        if (attempt < CF_MAX_RETRIES) {
          const retryAfterSec = parseInt(res.headers.get('retry-after') || '0', 10);
          const deterministic = retryAfterSec > 0
            ? retryAfterSec * 1000
            : CF_RETRY_BASE_MS * Math.pow(2, attempt);
          const jitter = deterministic * (0.75 + Math.random() * 0.5);
          const backoff = Math.round(jitter);
          console.warn(`[CloudflareDNS] HTTP ${res.status} on attempt ${attempt + 1}/${CF_MAX_RETRIES + 1}, retrying in ${backoff}ms (base ${deterministic}ms, jitter applied)`);
          clearTimeout(timeoutId);
          await new Promise((resolve) => setTimeout(resolve, backoff));
          continue;
        }
      }

      // Cloudflare returns JSON for all responses, including errors. Parse it
      // unconditionally so the caller gets a descriptive message on any failure.
      const body = await res.json() as CloudflareEnvelope<T>;

      if (!res.ok || !body.success) {
        const errMsg = body.errors?.[0]?.message || `HTTP ${res.status}`;
        const errCode = body.errors?.[0]?.code;
        throw new Error(`Cloudflare API error (${errCode ?? res.status}): ${errMsg}`);
      }

      return body;
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        lastErr = new Error(`Cloudflare API request timed out after ${CF_REQUEST_TIMEOUT_MS}ms`);
      } else {
        lastErr = err instanceof Error ? err : new Error(String(err));
      }
      // Non-retryable error: throw immediately
      if (lastErr.message.includes('Cloudflare API error') || attempt >= CF_MAX_RETRIES) {
        throw lastErr;
      }
    } finally {
      clearTimeout(timeoutId);
    }
  }
  throw lastErr || new Error('Cloudflare request failed after all retries');
}

/**
 * Find an existing A record by tenant slug. Used for idempotency — if a record
 * already exists (from a manual creation or a previous run), we reuse its ID
 * instead of failing with "record already exists".
 *
 * @returns the record ID if found, or null if no record exists for this slug
 */
export async function findTenantDnsRecord(slug: string): Promise<string | null> {
  const name = buildRecordName(slug);
  const qs = new URLSearchParams({ type: 'A', name, per_page: '1' });
  const res = await cfRequest<DnsRecord[]>(
    `/zones/${config.cloudflareZoneId}/dns_records?${qs.toString()}`,
    { method: 'GET' },
  );
  const record = res.result?.[0];
  return record?.id || null;
}

/**
 * Create a proxied A record for a tenant slug pointing at the server's public IP.
 *
 * Idempotent: if a record with the same name already exists, returns the
 * existing record's ID instead of attempting to create a duplicate (which
 * Cloudflare would reject with error 81057).
 *
 * @param slug — tenant slug (e.g. "bizarreelectronics")
 * @returns the Cloudflare record ID (stored in tenants.cloudflare_record_id for later deletion)
 */
export async function createTenantDnsRecord(slug: string): Promise<string> {
  // Idempotency check: if the record already exists, return its ID
  const existing = await findTenantDnsRecord(slug);
  if (existing) {
    logger.info('cloudflare_dns_record_reused', { slug, id: existing });
    return existing;
  }

  const name = buildRecordName(slug);
  const res = await cfRequest<DnsRecord>(
    `/zones/${config.cloudflareZoneId}/dns_records`,
    {
      method: 'POST',
      body: JSON.stringify({
        type: 'A',
        name,
        content: config.serverPublicIp,
        ttl: 1, // 1 = auto
        proxied: true,
        comment: `BizarreCRM tenant: ${slug}`,
      }),
    },
  );

  logger.info('cloudflare_dns_record_created', { name, ip: config.serverPublicIp, id: res.result.id });
  return res.result.id;
}

/**
 * Delete a tenant's DNS record by record ID.
 *
 * Treats 404 as success: if the record is already gone (manual deletion, or
 * cleanup from a prior failed run), there's nothing to do.
 *
 * @param recordId — the Cloudflare record ID from tenants.cloudflare_record_id
 */
export async function deleteTenantDnsRecord(recordId: string): Promise<void> {
  try {
    await cfRequest<{ id: string }>(
      `/zones/${config.cloudflareZoneId}/dns_records/${encodeURIComponent(recordId)}`,
      { method: 'DELETE' },
    );
    logger.info('cloudflare_dns_record_deleted', { recordId });
  } catch (err: unknown) {
    // Cloudflare returns error code 81044 or similar when the record doesn't exist.
    // Treat "not found" as a successful deletion (idempotent).
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('81044') || msg.includes('not found') || msg.includes('HTTP 404')) {
      logger.info('cloudflare_dns_record_already_gone', { recordId });
      return;
    }
    throw err;
  }
}
