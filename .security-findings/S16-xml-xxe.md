# S16 — XML / XXE / Deserialization

## Scope cleared — with one MEDIUM access-control finding

---

### [MEDIUM] /settings-ext/history audit log accessible to any authenticated user (no admin gate)

**Where:** `packages/server/src/routes/settingsExport.routes.ts:401–446`

**What:**
`GET /api/v1/settings-ext/history` is mounted under `authMiddleware` (index.ts:1641) but has **no `adminOnly` check** inside the handler, unlike every other mutating endpoint in the same file. It returns audit log rows including `event`, `user_id`, `meta`, and `created_at` for all `settings_*`, `user_created`, `user_updated`, and `user_deleted` events. Non-admin staff (technicians, employees) can query the full settings-change and user-lifecycle audit trail.

**Code:**
```typescript
router.get(
  '/history',
  // ← no adminOnly here; /export.json, /import, /bulk, /templates/apply all have it
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const limit = parsePageSize(req.query.limit, 25);
    // ...
    const rows = await adb.all<{ id: number; event: string; user_id: number|null; meta: string|null; created_at: string }>(
      `SELECT al.id, al.event, al.user_id, al.meta, al.created_at
       FROM audit_logs al
       WHERE al.event LIKE 'settings_%'
          OR al.event IN ('store_updated','user_created','user_updated','user_deleted')
       ORDER BY al.created_at DESC LIMIT ?`,
      limit
    );
```

**Exploit:**
Any tenant employee with a valid JWT can call `GET /api/v1/settings-ext/history` and read the settings audit log — including timestamped records of when admins changed passwords, updated SMTP credentials, imported settings, or created/deleted other users (with `user_id` references). This leaks configuration-change history and user-management activity to non-admin staff.

**Fix:**
Add `adminOnly` middleware to this route, consistent with the rest of the file: `router.get('/history', adminOnly, asyncHandler(...))`.

---

### [INFO] SVG accepted as estimate signature data URL — no server-side sanitization

**Where:** `packages/server/src/routes/estimateSign.routes.ts:58–60, 534–538`

**What:**
`POST /public/api/v1/estimate-sign/:token` accepts `data:image/svg+xml;base64,...` in `signature_data_url`. The server stores the raw base64 string in `estimate_signatures.signature_data_url` without decoding or sanitizing the SVG content (no XML parsing, no entity stripping, no DOMPurify). The stored blob is never served back as `image/svg+xml` — it is returned as JSON data and currently only embedded in a JSON response body. Risk depends on whether any future PDF/HTML receipt renderer decodes and inlines the SVG; the current code path does not.

**Code:**
```typescript
const ACCEPTED_DATA_URL_PREFIXES = [
  'data:image/png;base64,',
  'data:image/svg+xml;base64,',  // SVG accepted, content not sanitized
];
// Only size check, no content inspection:
const approxBytes = Math.ceil(base64Part.length * 3 / 4);
if (approxBytes > MAX_SIGNATURE_BYTES) { ... }
// Raw string stored to DB:
params: [estimateId, signerName, signerEmail, ip, signatureDataUrl, nowSql, userAgent],
```

**Exploit:**
An unauthenticated customer with a valid sign link can persist an SVG containing `<script>`, `<foreignObject>`, or external entity references (`<!ENTITY xxe SYSTEM "file:///etc/passwd">`) into the database. If a future receipt/print route decodes and inlines the SVG into HTML or passes it to a headless browser for PDF generation, it becomes stored XSS or potentially a local file read. Today the data URL is returned as a JSON field, not rendered server-side.

**Fix:**
Either reject SVG entirely (restrict to PNG/JPEG which are safe as opaque blobs), or decode the base64 and sanitize the SVG with a server-side library (e.g., `DOMPurify` in jsdom context or `svg-sanitize`) before storage. Never pipe an unsanitized SVG data URL into an HTML `<img src=…>` embedded in a document that will be rendered.

---

## Full scope cleared — what was checked

- **`packages/server/src/utils/xml.ts`** — Only exports `escapeXml()`. No XML parsing of any kind; no DTD, no entity expansion. Safe output-escaping only.
- **`packages/server/src/routes/settingsExport.routes.ts`** — Handles JSON import/export exclusively. No XML parser invoked. Import allow-list enforced. Encrypted keys handled correctly.
- **No XML parser libraries installed** — `packages/server/package.json` contains no `xml2js`, `fast-xml-parser`, `sax`, `xmldom`, `libxmljs`, or any other XML parser. No YAML libraries (`js-yaml`, `yaml`). No serialization libraries (`msgpack`, `bson`, `php-serialize`).
- **TwiML/BXML/TeXML generation (voice.routes.ts, twilio.ts, plivo.ts, bandwidth.ts)** — All user-controlled values (`to`, `from`, `forwardNumber`) are escaped via `escapeXml()` before string interpolation. No DTD or ENTITY declarations in generated XML. No inbound XML parsing of provider webhooks — providers send JSON or form-encoded data which is parsed by `express.json()` / `express.urlencoded()`.
- **cheerio (catalogScraper.ts)** — Used in HTML mode (default), not XML mode. Fetches external supplier HTML from hardcoded allowlisted domains (`mobilesentrix.com`, `phonelcdparts.com`). Response body capped at 10 MiB before parse. SSRF guard (`assertPublicUrl`) on every fetch.
- **RepairDesk / RepairShopr / MyRepairApp imports** — All three services consume JSON REST APIs via `fetch()` + `.json()`. No XML parsing. No SVG/OPML/RSS in the import pipeline.
- **SVG uploads** — Logo upload (`/settings/logo`) rejects SVG at the `multer` `fileFilter` (only JPEG/PNG/WebP/GIF allowed) and `LOGO_ALLOWED_MIMES`. `fileValidation.ts` has no SVG magic-byte entry. Only `estimateSign.routes.ts` accepts SVG as a base64 data URL (see INFO finding above).
- **Deserialization** — No `eval()`, `new Function()`, `yaml.load()`, `node-serialize`, or unsafe deserialization patterns found. All `JSON.parse()` calls operate on DB-stored strings or validated input, with surrounding `try/catch`.
- **`/history` endpoint** — Missing `adminOnly` (see MEDIUM finding above). The `GET /templates` endpoint is intentionally public read-only static data (no shop state exposed) and is considered safe per code comment.
