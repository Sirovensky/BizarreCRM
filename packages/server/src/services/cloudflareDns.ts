import { config } from '../config.js';

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
 * Build the full hostname for a tenant slug (e.g. "shop1" → "shop1.bizarrecrm.com").
 * Cloudflare's list endpoint returns full names, so we use them consistently
 * for exact-match lookups.
 */
function buildRecordName(slug: string): string {
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

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), CF_REQUEST_TIMEOUT_MS);

  try {
    const res = await fetch(`${CF_API_BASE}${path}`, {
      ...init,
      headers: {
        'Authorization': `Bearer ${config.cloudflareApiToken}`,
        'Content-Type': 'application/json',
        ...(init.headers || {}),
      },
      signal: controller.signal,
    });

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
      throw new Error(`Cloudflare API request timed out after ${CF_REQUEST_TIMEOUT_MS}ms`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }
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
    console.log(`[CloudflareDNS] Record already exists for ${slug} (id=${existing}), reusing`);
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

  console.log(`[CloudflareDNS] Created A record for ${name} → ${config.serverPublicIp} (id=${res.result.id}, proxied)`);
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
    console.log(`[CloudflareDNS] Deleted record ${recordId}`);
  } catch (err: unknown) {
    // Cloudflare returns error code 81044 or similar when the record doesn't exist.
    // Treat "not found" as a successful deletion (idempotent).
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes('81044') || msg.includes('not found') || msg.includes('HTTP 404')) {
      console.log(`[CloudflareDNS] Record ${recordId} already gone, treating as success`);
      return;
    }
    throw err;
  }
}
