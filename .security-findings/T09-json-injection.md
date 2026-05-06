# T09 — JSON Path Injection & FTS5 MATCH Audit

**Slot:** T09  
**Scope:** `json_extract`, `json_each`, `json_tree`, `json_set`, `json_remove`, `json_object`, `json_array`, `json_type`, `FTS5 MATCH`, `fts_` — across all server routes and services.

---

## Summary of Findings

| # | Severity | Short Title |
|---|----------|-------------|
| 1 | LOW | `repairPricing /services` LIKE missing `ESCAPE` clause |
| 2 | LOW | `invoices /stats` LIKE escapes input but omits `ESCAPE` clause |
| 3 | LOW | `inventoryVariants bundles` LIKE escapes input but omits `ESCAPE` clause |
| 4 | LOW | `reports /tax-report.pdf` jurisdiction LIKE: no `escapeLike`, no `ESCAPE` |

---

### [LOW] repairPricing /services LIKE missing ESCAPE clause

**Where:** `packages/server/src/routes/repairPricing.routes.ts:511-514`

**What:**
`GET /api/v1/repair-pricing/services?q=…` routes the `q` query param into a LIKE pattern via `%${q.trim().toLowerCase()}%` without passing through `escapeLike()` and without appending `ESCAPE '\\'` to the SQL clause. SQLite's LIKE treats `%` and `_` as wildcards when no escape character is declared. A locally-defined `escapeLike()` function exists in the same file at line 82 but is not called here.

**Code:**
```typescript
// repairPricing.routes.ts:502-517
router.get('/services', asyncHandler(async (_req, res) => {
  const adb = _req.asyncDb;
  const { category, q } = _req.query as { category?: string; q?: string };
  let sql = 'SELECT * FROM repair_services WHERE 1=1';
  const params: any[] = [];
  if (q && typeof q === 'string' && q.trim().length > 0) {
    sql += " AND (LOWER(name) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?)";
    const like = `%${q.trim().toLowerCase()}%`;  // ← no escapeLike()
    params.push(like, like);                      // ← no ESCAPE '\' in SQL
  }
  sql += ' ORDER BY category ASC, sort_order ASC';
  const services = await adb.all(sql, ...params);
```

**Exploit:**
Any authenticated user (role: technician) sends `GET /api/v1/repair-pricing/services?q=%25` and the LIKE becomes `%% LIKE` which matches every row — the whole `repair_services` table is returned regardless of the category filter, turning the endpoint into a full-table dump. With `q=_` the caller can scan individual character positions across all service names (single-char wildcard enumeration). The route carries no role gate (`GET /services` is open to all authenticated users; only POST/PUT/DELETE require `adminOrManager`).

**Fix:**
Replace the pattern with `escapeLike(q.trim().toLowerCase())` (the function is already defined in the same file at line 82) and add `ESCAPE '\\'` to both LIKE predicates:
```sql
AND (LOWER(name) LIKE ? ESCAPE '\' OR LOWER(COALESCE(category,'')) LIKE ? ESCAPE '\')
```

---

### [LOW] invoices /stats LIKE escapes input but omits ESCAPE clause

**Where:** `packages/server/src/routes/invoices.routes.ts:369-375`

**What:**
`GET /api/v1/invoices/stats?keyword=…` (the KPI stats sub-endpoint) calls `escapeLike(keyword)` to produce backslash-escaped patterns but then omits `ESCAPE '\\'` from the four LIKE predicates. SQLite does not honor escape sequences unless told which character is the escape character — without the `ESCAPE` clause the inserted backslashes are treated as literal characters, not escape indicators. The main list endpoint (`GET /invoices`) at line 254 does this correctly with `ESCAPE '\\'`; the stats endpoint at line 372 does not.

**Code:**
```typescript
// invoices.routes.ts:369-376
if (keyword) {
  const esc = escapeLike(keyword);               // escapes % _ \ → \% \_ \\
  conditions.push(
    "(inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR " +
    "(c.first_name || ' ' || c.last_name) LIKE ?)"  // ← ESCAPE '\' missing from all four
  );
  const pat = `%${esc}%`;
  params.push(pat, pat, pat, pat);
}
```

**Exploit:**
An authenticated user with `invoices.view` permission sends `GET /api/v1/invoices/stats?keyword=_&status=paid` — the `_` wildcard matches any single character, so all paid invoice stats are aggregated. Supplying `keyword=%` returns totals across all (non-void) invoices regardless of any other filter, leaking revenue aggregates more broadly than intended. The blast radius is limited to aggregate KPI numbers (not individual records) and requires authentication.

**Fix:**
Add `ESCAPE '\\'` to every LIKE predicate in the stats handler, mirroring the pattern already used in the list handler at line 254.

---

### [LOW] inventoryVariants bundles LIKE escapes input but omits ESCAPE clause

**Where:** `packages/server/src/routes/inventoryVariants.routes.ts:295-298`

**What:**
`GET /api/v1/inventory-variants/bundles?keyword=…` manually escapes the keyword with `keyword.replace(/[%_\\]/g, '\\$&')` but the two LIKE predicates in the dynamically-built `where` string carry no `ESCAPE '\\'` clause. Without the escape-char declaration SQLite ignores the backslashes and `%`/`_` still act as wildcards.

**Code:**
```typescript
// inventoryVariants.routes.ts:295-299
if (keyword) {
  where += ' AND (b.name LIKE ? OR b.sku LIKE ?)';  // ← no ESCAPE '\'
  const k = `%${keyword.replace(/[%_\\]/g, '\\$&')}%`;
  params.push(k, k);
}
```

**Exploit:**
Any authenticated user sends `GET /api/v1/inventory-variants/bundles?keyword=%` — the LIKE `%%` matches every active bundle row and bypasses intended search narrowing, returning the full bundles catalogue. `_` can be used as a single-character wildcard to enumerate bundles by partial name/SKU pattern.

**Fix:**
Add `ESCAPE '\\'` to both LIKE predicates:
```typescript
where += " AND (b.name LIKE ? ESCAPE '\\' OR b.sku LIKE ? ESCAPE '\\')";
```

---

### [LOW] reports /tax-report.pdf jurisdiction LIKE: no escapeLike, no ESCAPE

**Where:** `packages/server/src/routes/reports.routes.ts:2732,2743`

**What:**
`GET /api/v1/reports/tax-report.pdf?jurisdiction=…` builds a LIKE pattern `%${jurisdictionRaw}%` directly from `req.query.jurisdiction` without calling `escapeLike()` and without an `ESCAPE` clause. The endpoint is gated to admin/manager via `requireAdminOrManager()` so the attack surface is limited to privileged users, but those users can still cause unintended wide matches (e.g. `jurisdiction=%` matches all tax classes) or index-hostile patterns.

**Code:**
```typescript
// reports.routes.ts:2712, 2732, 2743
const jurisdictionRaw = String(req.query.jurisdiction || 'default').trim();
// ...
const jurisdictionPattern = `%${jurisdictionRaw}%`;  // ← no escapeLike()
// SQL:
'AND LOWER(COALESCE(tc.name, \'\')) LIKE LOWER(?)'   // ← no ESCAPE clause
```

**Exploit:**
An admin sends `GET /tax-report.pdf?jurisdiction=%` — the LIKE pattern `%%` matches every tax class row, so the filter is silently bypassed and the report includes all tax classes rather than a specific jurisdiction. A value like `_` matches any single-character class name, allowing confirmation of whether any one-character tax class names exist (low-impact info-leak). No SQL injection is possible because this is a parameterized query.

**Fix:**
Apply `escapeLike()` and add `ESCAPE '\\'`:
```typescript
const jurisdictionPattern = `%${escapeLike(jurisdictionRaw)}%`;
// SQL:
"AND LOWER(COALESCE(tc.name, '')) LIKE LOWER(?) ESCAPE '\\'"
```
Import `escapeLike` from `../utils/query.js` (already imported elsewhere in the file's dependency chain).

---

## Scope Cleared — Confirmed-Safe Checks

The following items were investigated and found to be secure:

1. **`json_extract` path in `auth.routes.ts:1166-1167, 2141-2142`** — `matchIdx` is the result of `Array.prototype.findIndex()` on a server-side array, always a non-negative integer. The path `'$[${matchIdx}]'` cannot be controlled by user input; the user-supplied backup `code` is only ever used as the bcrypt comparison operand (bound as `?`), never interpolated into the JSON path.

2. **FTS5 MATCH in `customers.routes.ts` and `search.routes.ts`** — Both files implement `ftsMatchExpr()` which (a) bounds input to 200 chars, (b) strips all characters except `[a-zA-Z0-9\s\-@.]` (no FTS5 operators survive: no `"`, `^`, `*`, `(`, `)`, `:`), and (c) wraps each token in double quotes (`"token"*`). Characters that pass through (`-`, `@`, `.`) are only special in FTS5 when they appear _outside_ quoted phrases; inside a quoted string they are literal. The match expression is then bound as a single `?` parameter, preventing any SQL-level injection.

3. **`json_object` / `json_array` in `import.routes.ts`** — All values in these calls are either string literals or bound `?` parameters (error message strings). No user-supplied values are interpolated into the JSON function arguments.

4. **`json_group_array` / `json_object` in `catalog.routes.ts:722`** — These aggregate a JOIN result from trusted database columns, not from request parameters.

5. **`json_set` / `json_remove` — no occurrences found** — Codebase does not use `json_set` or `json_remove` in any route except the `JSON_REMOVE` in `auth.routes.ts` which is safe (integer index, as described above).

6. **`json_each` / `json_tree` — no occurrences found** — Not used anywhere in the codebase; no JSON-each-based query DoS surface exists.

7. **LIKE in `tracking.routes.ts:269-273`** — Pattern is `%${last4}` where `last4 = digits.slice(-4)` and `digits = phone.replace(/\D/g, '')`. Stripping all non-digits guarantees `last4` can only contain `[0-9]` — no LIKE wildcards possible.

8. **LIKE in `tv.routes.ts:208-209`** — Patterns are built from the hardcoded `IN_PROGRESS_KEYWORDS` and `READY_PICKUP_KEYWORDS` constants, not from any request parameter.

9. **LIKE in `reports.routes.ts:150-159`** — Hardcoded string literals (`'%hold%'`, `'%waiting%'`, etc.) — no user input.

10. **LIKE in `settings.routes.ts:1359,1371`** — `itemName` originates from a DB read (`inventory_items.name`), not from the HTTP request; these lines are inside a POST `/reconcile-cogs` admin handler that iterates over existing inventory records, not user-supplied names.
