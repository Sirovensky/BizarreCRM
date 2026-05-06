# T13 — Decompression Bombs (zip, gzip, image, PDF, JSON, XML)

**Auditor:** T13 slot  
**Scope:** `packages/server/src/` — all decompression/expansion bomb vectors  
**Files read end-to-end:** `services/receiptOcr.ts`, `services/walletPass.ts`, `services/myRepairAppImport.ts`, `services/repairDeskImport.ts`, `services/repairShoprImport.ts`, `services/backup.ts`, `services/tenantExport.ts`, `services/catalogScraper.ts`, `middleware/fileUploadValidator.ts`, `utils/fileValidation.ts`, `utils/xml.ts`, `index.ts`, `routes/inventoryEnrich.routes.ts`, `routes/inventory.routes.ts`, `routes/sms.routes.ts`, `routes/settings.routes.ts`, `routes/bench.routes.ts`, `routes/expenses.routes.ts`, `routes/expenseReceipts.routes.ts`, `routes/estimateSign.routes.ts`, `routes/ticketSignatures.routes.ts`, `routes/import.routes.ts`  
**body-parser internals inspected:** `lib/read.js` (contentstream), `lib/types/json.js`; `raw-body/index.js` (streaming limit check)  
**node-canvas limits confirmed:** max height 32,767 pixels (empirically tested on installed version)

---

### [MEDIUM] PDF label-print canvas allocation bomb — main-thread OOM, any authenticated user

**Where:** `packages/server/src/routes/inventoryEnrich.routes.ts:1205` (no role gate, just `authMiddleware`)  
`packages/server/src/index.ts:1625` (`app.use('/api/v1/inventory-enrich', authMiddleware, inventoryEnrichRoutes)`)

**What:**  
`POST /api/v1/inventory-enrich/labels/print` with `format:"pdf"` creates a single tall PDF canvas whose height is `96 × (item_count × copies_per_item)`. `item_count` is bounded to 500 (via `validateArrayBounds`) and `copies_per_item` is capped at 10, yielding a theoretical canvas of 288 × 480,000 px. node-canvas enforces a 32,767-pixel ceiling so requests with more than ~34 items at 10 copies per item (≥ 342 total labels) throw `"Canvas height cannot exceed 32767"` synchronously on the main event loop. Below that ceiling a request with 341 labels allocates a 36 MB main canvas plus up to 18.9 MB of per-label barcode canvases (268 × 52 px each), totalling ~55 MB of synchronous main-thread allocation per request. The endpoint has **no rate limit** and **no role gate** (only `authMiddleware`), so any authenticated technician can call it at the global 300 req/min cap.

**Code:**
```typescript
// inventoryEnrich.routes.ts:1280–1320
const PX_W = 288;
const PX_H = 96;
const totalH = PX_H * totalLabels;           // 96 × (items.length × copies) ← unbounded

const canvas = createCanvas(PX_W, totalH, 'pdf');   // ← throws or allocates up to 36 MB
// ... per-label loop:
const barcodeCanvas = createCanvas(PX_W - 20, 52);  // ← 341 × 55 KB = 18.9 MB
```

**Exploit:**  
An authenticated technician (lowest-privilege role) sends `POST /api/v1/inventory-enrich/labels/print` with `{"item_ids":[1,2,...,35],"copies_per_item":10,"format":"pdf"}`. With 35 items × 10 copies = 350 labels the canvas constructor throws on the main thread, returning HTTP 500 to all concurrent requests. Alternatively, with 34 items × 10 copies = 340 labels, ~55 MB of canvas memory is allocated synchronously per request; at 300 req/min the GC contention causes measurable latency spikes for all tenants sharing the process.

**Fix:**  
Add a `totalLabels` ceiling before `createCanvas` (e.g. `if (totalLabels > 100) throw new AppError('Too many labels per request', 400)` — or match the printer page limit). Move canvas rendering to a piscina worker thread so a large or crashing allocation cannot stall the main event loop. Add a per-user rate limit (e.g. 10 req/min) on this endpoint.

---

## SCOPE CLEARED — remaining vectors investigated

1. **Zip bomb (import services):** `package.json` for the server lists zero zip-extraction libraries (`adm-zip`, `jszip`, `yauzl`, `unzipper`, `node-tar` are all absent). `repairDeskImport.ts`, `repairShoprImport.ts`, and `myRepairAppImport.ts` pull data from remote APIs via HTTP — no file upload, no archive extraction. `backup.ts` writes AES-256-GCM `.enc` files and decrypts them with `crypto.createDecipheriv`; it never calls an archive extraction API. `tenantExport.ts` builds a raw PKZIP buffer with a custom `buildZip()` writer — no extraction path exists.

2. **Gzip bomb via `Content-Encoding: gzip`:** `body-parser/lib/read.js` pipes gzip bodies through `zlib.createGunzip()` and passes `length = undefined` (not the compressed Content-Length) to `raw-body`. `raw-body` skips the pre-check (length is null) but enforces the `limit` counter **during streaming** (`if (limit !== null && received > limit)`). A 1 KB compressed body that decompresses beyond the 1 MB / 10 MB parser limit is rejected on the first chunk that crosses the threshold. The decompressed bytes already buffered at that point are bounded by the configured limit. The rate limiter (300 req/min) precedes body parsing (`index.ts:1181`), providing a second line of defence.

3. **JSON bomb (deep nesting):** Node.js v22.22.2 `JSON.parse` handles 200,000-deep nesting (1.2 MB JSON) without stack overflow or OOM — tested empirically (parses in ~5 ms). The global `express.json({ limit: '1mb' })` and the 10 MB carve-out for `/catalog/bulk-import` (admin-only) bound input size before parse. The catalog bulk-import flat-array payload (5 000 items × 500 bytes = 2.5 MB) parses in ~5 ms with no event-loop impact.

4. **Image bomb (sharp):** The only sharp call is `sms.routes.ts:141` which correctly sets `{ limitInputPixels: 24_000_000, failOn: 'error' }`, capping decoded pixels at 24 MP. All other image upload routes (logo, inventory photos, bench QC, shrinkage photos, expense receipts) store files on disk without decoding pixel data — no canvas or sharp processing path. Receipt OCR uses `tesseract.js` which is not installed (`package.json` omits it); the cron stub marks OCR jobs failed without calling any image decoder.

5. **PDF bomb:** No PDF parsing library (`pdf-parse`, `pdf-lib`, `pdfjs-dist`) is installed. All `/reports/*.pdf` endpoints generate PDFs via canvas output (`canvas.toBuffer('application/pdf')`). The portal "receipt.pdf" and "warranty.pdf" routes return HTML (comment in code: "pdfkit/puppeteer are not installed"). `fileValidation.ts` has a PDF magic-byte entry (for future use) but no upload route in the current codebase accepts `application/pdf` as an allowed MIME.

6. **XML bomb (entity expansion):** The server generates TwiML/BXML/PlivoXML via `utils/xml.ts:escapeXml()` (pure string substitution, no parser). No incoming XML is parsed: there is no `xml2js`, `fast-xml-parser`, `xmldom`, `sax`, or `DOMParser` call anywhere in `packages/server/src/`. The voice webhook handlers receive JSON or URL-encoded bodies, not XML.

7. **SVG bomb:** `estimateSign.routes.ts` accepts `data:image/svg+xml;base64,...` up to 200 KB and stores it verbatim as a base64 string in the DB — it is never decoded or parsed server-side. No XML entity expansion is possible.

8. **Brotli bomb:** `body-parser/lib/read.js:contentstream()` handles only `deflate`, `gzip`, and `identity` in its switch statement. A request with `Content-Encoding: br` falls to the default branch and returns 415 Unsupported Content Encoding, rejecting it before any decompression attempt.

9. **HEIC/HEIF upload:** `expenseReceipts.routes.ts` lists `image/heic` in `ALLOWED_RECEIPT_MIMES` and the multer filter, but `fileValidation.ts:SIGNATURES` contains no HEIC magic-byte entry. `fileUploadValidator` therefore rejects HEIC files with 400 "Unrecognized file signature". This is safe (though it creates a mismatch between multer's filter and the downstream validator).

10. **Backup decryption size:** `backup.ts:decryptFile()` reads the full encrypted file into a `Buffer` with no pre-size cap, but the backup directory is admin-configured and locally written by the server's own `runBackup()` (bounded by the tenant's actual DB size). No external upload path reaches this function; restore only operates on files that already exist in the local `backupDir`.

---
