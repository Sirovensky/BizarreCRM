# T14 — Email Header Injection (CRLF) + Attachment Filename Injection

**Scope reviewed:**
- `packages/server/src/services/email.ts` — full
- `packages/server/src/routes/auth.routes.ts` — password reset email path
- `packages/server/src/routes/settings.routes.ts` — SMTP config endpoints
- `packages/server/src/routes/notifications.routes.ts` — receipt email
- `packages/server/src/routes/campaigns.routes.ts` — campaign dispatch
- `packages/server/src/services/notifications.ts` — ticket status notification
- `packages/server/src/services/dunningScheduler.ts` — dunning emails
- `packages/server/src/services/scheduledReports.ts` — daily report
- `packages/server/src/services/reportEmailer.ts` — weekly summary
- `packages/server/src/services/dataExportScheduleCron.ts` — export schedule
- `packages/server/src/services/automations.ts` — automation engine
- `packages/server/src/services/tenantTermination.ts` — termination email
- `packages/server/src/middleware/stepUpTotp.ts` — PII export email

**nodemailer version:** `^8.0.4` — no known critical CVEs; RFC 2822 address parsing sanitizes CRLF in To/From header fields before wire encoding. Raw CRLF injection via nodemailer's address-parser is not achievable on this version.

---

### MEDIUM `smtp_from` stored without email-format validation via `PUT /store`

**Where:** `packages/server/src/routes/settings.routes.ts:570–598` and `packages/server/src/services/email.ts:84–86`

**What:**
`PUT /settings/store` accepts `smtp_from` in its allowlist (line 578) but does **not** call `validateConfigValue()` — the function that enforces `EMAIL_RE` on `smtp_from`. The companion endpoint `PUT /settings/config` (line 482) correctly validates `smtp_from` through `EMAIL_SETTINGS` → `EMAIL_RE`. As a result an admin can store any arbitrary string (including display-name format such as `"ACME Shop" <relay@acme.com>`) in `smtp_from`. In `email.ts` `getSmtpConfig()`, when `from_email` fails `EMAIL_FROM_RE`, the code falls through to `smtpFrom` **without any format check** (line 84–86) and passes it directly as the nodemailer `from` field. nodemailer's addressparser prevents wire-level CRLF injection, but the stored value may spoof the display-name portion of the From header arbitrarily.

**Code:**
```typescript
// settings.routes.ts:578 — PUT /store (no validateConfigValue call)
const allowed = ['store_name','address','phone','email','timezone','currency',
  'tax_rate','receipt_header','receipt_footer','logo_url','sms_provider',
  'tcx_host','tcx_extension','tcx_password',
  'smtp_host','smtp_port','smtp_user','smtp_from','business_hours','store_logo'];
for (const [key, value] of Object.entries(req.body)) {
  if (!allowed.includes(key)) continue;
  const strVal = value;                             // no EMAIL_RE check
  const storedVal = ENCRYPTED_CONFIG_KEYS.has(key) ? encryptConfigValue(strVal) : strVal;
  await adb.run('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)', key, storedVal);
}

// email.ts:84-86 — smtp_from fallback, no validation
} else if (smtpFrom) {
  from = smtpFrom;   // used as-is without EMAIL_FROM_RE test
  fromSource = 'smtp_from';
}
```

**Exploit:**
A tenant admin issues `PUT /settings/store` with `smtp_from: "Legitimate Bank <billing@bank.example.com>"`. Every outbound email from that tenant then carries `From: "Legitimate Bank <billing@bank.example.com>"` regardless of the SMTP relay's actual sender, enabling display-name spoofing on all automated emails (receipts, dunning, password resets). Nodemailer prevents raw CRLF from reaching the wire, so multi-line header injection is not achieved; only display-name spoofing.

**Fix:**
Apply `validateConfigValue('smtp_from', value)` inside the `PUT /store` handler's loop (same as `PUT /config`) before persisting the value. Alternatively, call `EMAIL_FROM_RE.test(smtpFrom)` in `getSmtpConfig()` before using the fallback and log + skip if invalid.

---

### LOW HTML injection into PII-export notification email via `User-Agent` header

**Where:** `packages/server/src/middleware/stepUpTotp.ts:175–178`

**What:**
`firePiiExportEmail()` interpolates `userAgent` (from `req.headers['user-agent']`) directly into an HTML email body without calling `escapeHtml`. The downstream `sanitizeEmailHtml()` in `email.ts` strips `<script>` blocks and `on*=` event handlers but **does not strip arbitrary structural HTML tags** such as `<img>`. An authenticated user who performs a TOTP-gated PII export with a crafted `User-Agent` header will receive their own security-alert email containing the injected HTML.

**Code:**
```typescript
// stepUpTotp.ts:172-181
const body = `
<p>A PII export was completed on your BizarreCRM account.</p>
<ul>
  <li><strong>Endpoint:</strong> ${endpoint}</li>
  <li><strong>IP address:</strong> ${ip}</li>
  <li><strong>User-Agent:</strong> ${userAgent}</li>   // ← raw, no escapeHtml
  <li><strong>Timestamp (UTC):</strong> ${timestamp}</li>
</ul>
...`.trim();
```

**Exploit:**
An authenticated user sets `User-Agent: </li><img src="//attacker.com/track.gif"><li>` and triggers a PII export. The security-alert email they receive contains a tracking pixel that fires when they open the email, confirming the email address is active. In practice the victim is the attacker themselves (the email goes to `dbUser.email` — the requesting user's own address), so cross-user impact is none. Email forwarding, archiving systems, or audit displays that render the body raw could be affected.

**Fix:**
Replace `${userAgent}` with `${escapeHtml(userAgent)}` (and `${escapeHtml(ip)}` for consistency). `escapeHtml` is already imported from `utils/escape.js` in the same file.

---

### LOW Raw `username` interpolated into password-reset email HTML body

**Where:** `packages/server/src/routes/auth.routes.ts:1759`

**What:**
The password-reset email is built with template literal `<p>Hi ${user.username},</p>…` without calling `escapeHtml`. `user.username` is whatever is stored in the `users` table, which can be set to any string by an admin via `POST /settings/users` (admin-only, no HTML-escaping enforced at storage). `sanitizeEmailHtml()` in `sendEmail()` strips `<script>` and `on*` handlers but passes `<img src=//external>` and other structural tags through unchanged.

**Code:**
```typescript
// auth.routes.ts:1759
html: `<p>Hi ${user.username},</p>
<p>Click the link below to reset your password. This link expires in 1 hour.</p>
<p><a href="${resetUrl}">${resetUrl}</a></p>
<p>If you didn't request this, you can safely ignore this email.</p>`,
```

**Exploit:**
An admin creates a user account with `username: '<img src=//attacker.com/px.gif>'`. When that user's password is reset, their reset-email contains a tracking pixel. Impact is limited: the admin can already change the user's email address and thus control what the user receives; the username injection provides no privilege escalation. Severity is LOW due to the admin-only precondition.

**Fix:**
Wrap `user.username` with `escapeHtml(user.username)`. The import is already present in `auth.routes.ts` via `utils/escape.js`.

---

### LOW `schedule.name` interpolated raw into export-delivery email HTML

**Where:** `packages/server/src/services/dataExportScheduleCron.ts:231–234`

**What:**
The delivery-email body for a completed data-export schedule injects `schedule.name` directly into HTML (`<strong>${schedule.name}</strong>`) and also into the email subject (`Data export ready — ${schedule.name}`). The subject is protected by `sanitizeSubject()` in `sendEmail()`, but the HTML body only passes through `sanitizeEmailHtml()` which does not escape arbitrary HTML tags. Any admin who can create an export schedule can craft a `name` that embeds structural HTML (e.g. `<img>` tags) in the delivery email sent to whatever `delivery_email` they configure.

**Code:**
```typescript
// dataExportScheduleCron.ts:229-240
await sendEmail(db, {
  to: schedule.delivery_email,
  subject: `Data export ready — ${schedule.name}`,      // sanitized by sanitizeSubject()
  html: [
    `<p>Your scheduled data export "<strong>${schedule.name}</strong>" has completed.</p>`,
    `<ul>`,
    `<li>Export type: ${exportType}</li>`,               // enum-validated — safe
    `<li>Rows exported: ${rowCount.toLocaleString()}</li>`,
    `<li>File: ${fileName}</li>`,
    `</ul>`,
  ].join(''),
});
```

**Exploit:**
An admin creates an export schedule with `name: "</strong><img src=//attacker.com/t.gif>"` and sets `delivery_email` to a colleague's inbox. When the schedule fires, the colleague receives a report email with an embedded tracking pixel. This requires admin access and the colleague must be someone the admin can legitimately send automated email to, limiting real-world impact.

**Fix:**
Replace `${schedule.name}` in the HTML body with `${escapeHtml(schedule.name)}`. `escapeHtml` is available from `utils/escape.js` — add the import to `dataExportScheduleCron.ts`.

---

## SCOPE CLEARED — items investigated and found safe

- **Subject-line CRLF injection (all callers):** `sendEmail()` applies `sanitizeSubject()` which calls `s.replace(/[\r\n]+/g, ' ')` before nodemailer sees the value. All callers — dunning, campaigns, notifications, scheduledReports, auth — pass through this guard.
- **nodemailer To/From CRLF injection:** nodemailer `^8.0.4` parses all address fields through its RFC 2822 addressparser before writing to the SMTP socket. Raw CR/LF bytes in `to` or `from` are either stripped or cause the send to throw (caught by the try/catch in `sendEmail()`). No raw wire-level injection is achievable.
- **nodemailer CVE exposure:** `^8.0.4` carries no known critical CVEs as of the audit date.
- **Custom `headers:` object passed to `sendMail()`:** The single `sendMail()` call site (`email.ts:224–230`) passes only `from`, `to`, `subject`, `html`, `text` — no `headers` key, no replyTo, no attachments, no custom extension headers.
- **`from_email` via `PUT /config`:** Correctly validated against `EMAIL_FROM_RE` through `validateConfigValue()` → `EMAIL_SETTINGS` set before persistence.
- **Attachment filename injection:** No `attachments` property is passed in any `sendMail()` call. The `SendEmailOptions` interface does not include attachments. No attachment filename injection surface exists.
- **Return-Path / SMTP DSN abuse:** nodemailer uses the SMTP auth credentials as the MAIL FROM envelope; there is no code path that sets a user-controlled `envelope.from` or `Return-Path` header.
- **Dunning and automation template subject injection:** All dunning subjects flow through `renderTemplate()` (no escape) into `sendEmail()` where `sanitizeSubject()` strips CRLF. The HTML body uses `renderTemplate(..., 'html')` which applies `escapeHtml` to all variable substitutions.
- **Notification template injection (notifications.ts):** `escapeHtml` applied to all customer-controlled variables before email body construction (lines 527–544).
- **tenantTermination email:** Uses `escapeHtml(opts.adminUsername)` explicitly (line 533).
- **Campaigns template subject/body:** Subject uses `renderTemplate` (raw) but is sanitized by `sanitizeSubject()` at send; HTML body uses `renderTemplateHtml` which applies `escapeHtml` to all substituted values.
- **`delivery_email` CRLF in `to` field:** The `to` field is not CRLF-sanitized by our code, but nodemailer's addressparser handles this. The `.includes('@')` check is weak but insufficient to enable header injection given nodemailer's protections.
