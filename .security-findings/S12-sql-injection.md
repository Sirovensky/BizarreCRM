# S12 — SQL Injection Sweep (better-sqlite3)

**Auditor:** Claude (Slot 12)
**Date:** 2026-05-05
**Scope:** `packages/server/src/` — all `db.prepare`, `db.exec`, template-literal SQL

---

## Summary

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 3 |
| LOW | 1 |
| INFO | 3 |

---

## MEDIUM — Missing `ESCAPE` clause on escapeLike-protected LIKE patterns

### M1 — `invoices.routes.ts` invoice-report endpoint (line 372)

**File:** `packages/server/src/routes/invoices.routes.ts:370-375`

```ts
const esc = escapeLike(keyword);
conditions.push(
  "(inv.order_id LIKE ? OR c.first_name LIKE ? OR c.last_name LIKE ? OR (c.first_name || ' ' || c.last_name) LIKE ?)"
);
const pat = `%${esc}%`;
```

**Issue:** `escapeLike()` escapes `%`, `_`, and `\` using backslash as the escape character, but the SQL fragment has no `ESCAPE '\'` clause. SQLite has no default escape character, so the backslashes inserted by `escapeLike()` are treated as literal characters inside the pattern instead of escape tokens. A user who supplies `%` or `_` can still expand the match beyond their intended scope (index bypass / broad enumeration). This is the invoice *reports/KPI* route (separate from the main invoice list at line 254 which correctly includes `ESCAPE`).

**Note:** No classic injection — values are bound via `?` parameters. Risk is LIKE-wildcard enumeration/DoS, not data modification.

**Remediation:** Add `ESCAPE '\'` to every LIKE clause in this fragment, consistent with line 254.

---

### M2 — `repairPricing.routes.ts` repair-services search (line 512)

**File:** `packages/server/src/routes/repairPricing.routes.ts:511-515`

```ts
sql += " AND (LOWER(name) LIKE ? OR LOWER(COALESCE(category,'')) LIKE ?)";
const like = `%${q.trim().toLowerCase()}%`;
params.push(like, like);
```

**Issue:** `q` comes directly from `req.query.q` (string-typed). No `escapeLike()` call and no `ESCAPE` clause. A user can send `%` or `_` characters to match all rows or trigger a full table scan. The repair-services table is internal (admin-only route), reducing exploitability, but the pattern is incorrect.

**Remediation:**
```ts
import { escapeLike } from '../utils/query.js';
const like = `%${escapeLike(q.trim().toLowerCase())}%`;
sql += " AND (LOWER(name) LIKE ? ESCAPE '\\' OR LOWER(COALESCE(category,'')) LIKE ? ESCAPE '\\')";
```

---

### M3 — `inventoryVariants.routes.ts` bundle search (line 296-297)

**File:** `packages/server/src/routes/inventoryVariants.routes.ts:296-298`

```ts
where += ' AND (b.name LIKE ? OR b.sku LIKE ?)';
const k = `%${keyword.replace(/[%_\\]/g, '\\$&')}%`;
```

**Issue:** Manual regex escape is functionally equivalent to `escapeLike()`, but there is no `ESCAPE '\'` clause in the LIKE fragment. Without the SQL-level escape declaration, the backslashes are literal noise and `%`/`_` from the user still act as wildcards.

**Remediation:** Replace inline regex with `escapeLike()` and add `ESCAPE '\'` to both LIKE clauses.

---

## LOW — `tracking.routes.ts` phone last-4 LIKE without `ESCAPE` (line 273)

**File:** `packages/server/src/routes/tracking.routes.ts:269-273`

```ts
const digits = phone.replace(/\D/g, '');
const last4 = digits.slice(-4);
...
`, `%${last4}`, `%${last4}`, `%${last4}`);
```

**Issue:** `last4` is derived by stripping non-digits with `replace(/\D/g, '')`, so it can only contain `0-9`. Neither `%` nor `_` can survive. There is no injection risk and no wildcard risk from `last4` itself. However the LIKE patterns have no `ESCAPE` clause, which is a consistency/future-safety gap (if the stripping logic ever widens). Rated LOW because current input is strictly digit-only.

**Remediation:** Either document the invariant with a comment or add `ESCAPE '\'` as defence-in-depth; no urgency.

---

## INFO — Patterns that look risky but are safe

### I1 — Dynamic `SET` clause in `super-admin.routes.ts` (line 904-907)

```ts
const allowedFields: Record<string, any> = {};
if (req.body.plan !== undefined) allowedFields['plan'] = req.body.plan;
// ... other explicit assignments only
const keys = Object.keys(allowedFields);
const setClause = keys.map(k => `${k} = ?`).join(', ');
masterDb.prepare(`UPDATE tenants SET ${setClause} ...`).run(...params);
```

`keys` is derived from `allowedFields` whose properties are set by explicit `if` branches using string literals, not `req.body` keys directly. There is no user-controlled string flowing into a column name. **Safe.**

### I2 — `ORDER BY` interpolation in multiple routes

All examined `ORDER BY ${...}` sites use one of:
- An explicit `Record<string, string>` map keyed by the user value (estimates, invoices, inventory).
- An `allowedSorts.includes()` guard that falls back to a safe default (customers, tickets, inventory).
- A boolean ternary (`hotOnly` in repairPricing — parsed via `parseBoolish()`, emits fixed SQL strings).

No user-controlled string reaches the SQL column position unguarded. **Safe.**

### I3 — Dynamic `DELETE FROM ${table}` in `repairDeskImport.ts` (line 2380-2386)

```ts
const batchDelete = (table: string, column: string, ids: number[]) => {
  assertValidTableName(table);
  if (!/^[a-z_]+$/.test(column)) throw new Error(`Invalid column name: ${column}`);
  ...
  db.prepare(`DELETE FROM ${table} WHERE ${column} IN (${placeholders})`).run(...batch);
};
```

Both `table` and `column` are validated before interpolation: `assertValidTableName` checks against a hardcoded `ALLOWED_WIPE_TABLES` set; column is checked with a strict regex. All call sites in the file pass literal string arguments. **Safe.**

---

## Positive findings (defence-in-depth already in place)

- `utils/query.ts` exports `escapeLike`, `likeContains`, `likeStartsWith`, `likeEndsWith`, and `assertSafeIdentifier` with an optional allowlist — a solid library that just needs consistent adoption.
- `db-worker.mjs` validates task shape (op allowlist, sql type check) before passing to `db.prepare()`.
- All `IN (${placeholders})` sites build placeholders as `ids.map(() => '?').join(',')` — no user values are interpolated, only bound parameters.
- `LIKE` usage in `search.routes.ts`, `customers.routes.ts`, `inventory.routes.ts`, `voice.routes.ts`, `expenses.routes.ts` all correctly call `escapeLike()` and include `ESCAPE '\'`. 
- `tv.routes.ts` LIKE patterns use hardcoded constant arrays, not request data.

---

## PASS 2 — DEEP DIVE

**Date:** 2026-05-05
**Auditor:** Claude (Slot 12 — Pass 2)

**Approach:** exhaustive grep over all 2,146 DB call sites; swept all routes/, services/, utils/, db/ files end-to-end. Checked: dynamic `ORDER BY`, `LIKE` with/without `ESCAPE`, `IN (${placeholders})` construction, dynamic `SET` clause builders, FTS5 `MATCH` sanitisation, `json_extract` / `JSON_REMOVE` index interpolation, `PRAGMA table_info(${table})`, `db.exec()` sites, retention-sweeper interpolations, import/export table-name interpolations, segment rule engine.

---

### Updated severity table (cumulative)

| SEV | Count |
|-----|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 3 |
| LOW | 1 |
| INFO | 4 |

---

### [INFO] `PRAGMA table_info(${table})` without identifier binding in `columnExists`

**Where:** `packages/server/src/services/retentionSweeper.ts:334`

**What:**
`columnExists()` uses `db.prepare(\`PRAGMA table_info(${table})\`)` with string interpolation instead of a parameterised form. SQLite's PRAGMA syntax does not accept `?` bindings for table names (a known SQLite limitation), so this is the standard workaround. However, the function does not validate `table` itself; it relies entirely on the single call-site at line 476 having already run `assertSqlIdent(rule.table, 'table')` earlier in `applyPiiRule`. The `RULES` and `PII_RULES` arrays are static constants, so no user-supplied string ever reaches this function at runtime.

**Code:**
```typescript
function columnExists(db: Database, table: string, column: string): boolean {
  try {
    const rows = db.prepare(`PRAGMA table_info(${table})`).all()
      as Array<{ name?: string }>;
    return rows.some((r) => r.name === column);
  } catch {
    return false;
  }
}
// Called only from applyPiiRule (line 476), after assertSqlIdent already ran.
```

**Exploit:**
No current exploit path — all callers pass literals from a static constant array and `assertSqlIdent` has already validated the name. Risk is latent: if a future caller passes a user-controlled `table` argument without pre-validating, PRAGMA injection could read arbitrary table schemas or cause errors.

**Fix:**
Add an `assertSqlIdent(table, 'table')` guard at the top of `columnExists` as defence-in-depth, independent of what callers do. Consistent with the pattern already used in `applyPiiRule`.

---

## Pass 2 — Extended Safe Patterns Verified

- **All `ORDER BY ${...}` sites** (inventory, invoices, estimates, tickets, leads, customers): every interpolated column/direction comes from an explicit allowlist (`allowedSorts.includes()` / `Record<string, string>` map / binary ternary). No user string reaches the SQL position unguarded.
- **All dynamic `SET` clause builders** (tickets, smsAutoResponders, roles, locations, crm, onboarding, campaigns, bookingConfig, sms, catalog, team, pos, dunning, recurringInvoices, voice, dataExportSchedules, customers, inventory variants/bundles, reports, purchase orders): in every case, column names are pushed as hardcoded string literals inside `if (req.body.X !== undefined)` guards — not from `Object.keys(req.body)`.
- **FTS5 `MATCH ?`**: user input flows through `ftsMatchExpr()` which strips to alphanumeric + safe chars and double-quotes each token before binding via `?`. No injection.
- **`json_extract(backup_codes, '$[${matchIdx}]')`**: `matchIdx` derives from `Array.findIndex()` return value (always a non-negative integer). Not user-controlled.
- **`IN (${placeholders})`** (fieldService, syncConflicts, customers, leads, sampleData, rma, dunning, repairPricing): all use `.map(() => '?').join(',')` — structural only; values are always bound parameters.
- **`DELETE FROM ${table}`** (repairDeskImport nuclear wipe, selectiveWipe, retentionSweeper): all tables come from hardcoded arrays and pass `assertValidTableName()` / `assertSqlIdent()` before interpolation.
- **`SELECT * FROM "${table}"`** (dataExportGenerator, tenantExport): tables come from `sqlite_master` (not user input) and pass `/^[a-zA-Z_][a-zA-Z0-9_]*$/` regex guard.
- **`PRAGMA table_info(${table})`** (retentionSweeper): PRAGMA syntax cannot accept `?` bindings; `table` comes from a static constant and `assertSqlIdent` already ran at the call-site. Latent risk if new callers are added.
- **`STRFTIME('${dateFormat}', ...)` in reports.routes.ts**: `dateFormat` is always `'%Y-%m'` or `'%Y-%m-%d'` — result of a ternary on a trusted boolean, not a user string.
- **`retentionSweeper` rule `whereExtra`**: hardcoded constant string in `RULES` array, no user input.
- **`LIMIT ${limit ?? 5_000}`** in campaigns.routes.ts: `limit` is either `null` or a server-computed integer, never from req.
- **`LIMIT ${PENDING_BATCH_LIMIT}`, `LIMIT ${MAX_EXPORT}`**: named constants, not request data.
- **`catalogScraper.ts:374` inverted LIKE**: `LOWER(?) LIKE '%' || LOWER(name) || '%'` — the `?` is the search term (left operand), the pattern comes from the DB column. Wildcards in the user input cannot expand because the input is the non-pattern side.
