# T25 — Dependency CVEs / Outdated Libs / Supply-Chain Risk

**Auditor:** T25 slot  
**Scope:** `package.json`, `packages/server/package.json`, `packages/web/package.json`, `packages/shared/package.json`, `packages/management/package.json`, and `package-lock.json` (all 1 023 resolved packages)  
**Method:** Full lockfile parse; version × CVE cross-reference; source diff of high-risk packages; deprecated-package enumeration; install-script enumeration; integrity-hash spot-checks; bcrypt usage audit across all `.ts` production files.

---

## Cleared / Not Vulnerable

The following packages were audited against known CVEs and are at patched versions:

| Package | Installed | CVEs checked | Status |
|---------|-----------|--------------|--------|
| express | 4.22.1 | CVE-2024-29041 (< 4.19.2), CVE-2024-43796 (< 4.20.0) | ✓ FIXED |
| serve-static | 1.16.3 | CVE-2024-43799 (< 1.16.0) | ✓ FIXED |
| body-parser | 1.20.4 | CVE-2024-45590 (< 1.20.3) | ✓ FIXED |
| cookie | 0.7.2 | CVE-2024-47764 (< 0.7.0) | ✓ FIXED |
| ws | 8.20.0 | CVE-2024-37890 (< 8.17.1) | ✓ FIXED |
| axios | 1.15.0 | CVE-2024-39338 SSRF (< 1.7.4) | ✓ FIXED |
| follow-redirects | 1.16.0 | CVE-2024-28849, CVE-2023-26159 (< 1.15.6) | ✓ FIXED |
| jsonwebtoken | 9.0.3 | CVE-2022-23529/CVE-2022-23541 (< 9.0.0) | ✓ FIXED |
| multer | 2.1.1 | CVE-2022-24434 (1.x only) | ✓ v2 unaffected |
| qs | 6.14.2 | CVE-2022-24999 (< 6.7.3) | ✓ FIXED |
| path-to-regexp | 0.1.13 | CVE-2024-45296 (< 0.1.10), CVE-2024-52798 (≤ 0.1.11) | ✓ FIXED (0.1.12 patched; 0.1.13 confirmed via source diff) |
| semver | 6.3.1 / 7.7.4 / 5.7.2 | CVE-2022-25883 (< 5.7.2, < 6.3.1, < 7.5.2) | ✓ FIXED |
| lodash | 4.18.1 | GHSA-xxjr-mmjv-4gpg, GHSA-f23m-r3pf-42rh prototype pollution | ✓ PATCH RELEASE — diff confirms only security fixes; published by original author jdalton |
| got | 11.8.6 | CVE-2022-33987 (< 11.8.5) | ✓ FIXED |
| ini | 1.3.8 | CVE-2020-7788 (< 1.3.6) | ✓ FIXED |
| undici | 7.24.7 | CVE-2024-30261 (< 6.11.1), CVE-2024-24758 (< 6.6.1) | ✓ FIXED |
| dompurify | 3.4.0 | — | ✓ Current |
| tar | 7.5.13 | CVE-2024-28863 (6.x < 6.2.1 path traversal) | ✓ v7 unaffected |
| helmet | 8.1.0 | — | ✓ Current |
| bcryptjs | 3.0.3 | — | ✓ No known CVEs (see performance finding below) |
| better-sqlite3 | 12.9.0 | — | ✓ Current |

No packages sourced from GitHub or non-npm registries. All `integrity` hashes present. No packages missing SRI.

---

### [MEDIUM] 37 synchronous `bcrypt.hashSync` / `compareSync` calls block the Node.js event loop

**Where:**
- `packages/server/src/routes/auth.routes.ts:652,653,756,914,1063,1165,1514,1670,1991,2184,2225,2304,2420` (13 calls)
- `packages/server/src/routes/settings.routes.ts:1486,1487,1543,1577,1578,1719,1781,1782,3145` (9 calls)
- `packages/server/src/routes/import.routes.ts:510,847,1173,1350` (4 calls — via `await import('bcryptjs')` then `.default.compareSync`)
- `packages/server/src/routes/employees.routes.ts:331,429` (2 calls)
- `packages/server/src/routes/customers.routes.ts:2123` (1 call)
- `packages/server/src/routes/admin.routes.ts:101` (1 call)
- `packages/server/src/routes/posEnrich.routes.ts:706` (1 call)
- `packages/server/src/routes/management.routes.ts:178` (1 call)
- `packages/server/src/index.ts:611` (1 call)
- (4 already-reported in S04 included above; the other 33 are distinct call-sites)

**What:**
`bcryptjs` is a pure-JavaScript implementation with **no native bindings**. Every `hashSync(password, 12)` or `compareSync(password, hash)` with cost-factor 12 spins the CPU in JavaScript for approximately 150–400 ms on modern Node.js, **holding the event loop** for that entire duration. Node.js is single-threaded: while a `hashSync` call is executing, no other HTTP request, WebSocket message, cron callback, or DB query can proceed. There are 37 distinct synchronous bcrypt call-sites across 9 production route files and the server entry point. The `auth.routes.ts:1063` call is particularly severe: it calls `bcrypt.hashSync(c, 12)` ten times in a tight `map()` (one per backup recovery code) — roughly **1.5–4 seconds of event loop freeze** per 2FA-enrollment request.

**Code:**
```typescript
// auth.routes.ts:1060–1066 — 10× hashSync in a tight loop
const plainCodes = Array.from({ length: 10 }, () =>
  Array.from(crypto.getRandomValues(new Uint8Array(5)))
    .map(b => b.toString(36).padStart(2, '0')).join('').slice(0, 8)
);
const hashedCodes = plainCodes.map(c => bcrypt.hashSync(c, 12)); // ← BLOCKS ~1.5–4 s
// settings.routes.ts:1486–1487 — two hashSync calls in sequence on employee create
const placeholderPasswordHash = bcrypt.hashSync(crypto.randomBytes(32).toString('hex'), 12);
const pinHash = pin ? bcrypt.hashSync(pin, 12) : null;
```

**Exploit:**
An authenticated attacker (any user who can trigger employee creation, password changes, or 2FA enrollment) sends repeated requests to these endpoints. Each request freezes the event loop for 150–800 ms (or 1.5–4 s for the backup-codes path). At 10 concurrent requests, all other tenants' HTTP requests queue up indefinitely. Unauthenticated endpoints that call `compareSync` (e.g. the admin login at `admin.routes.ts:101`) can be used without authentication for the same effect if rate-limiting is insufficient per-IP.

**Fix:**
Replace all `hashSync`/`compareSync` calls with the async `bcrypt.hash(pw, 12)` / `bcrypt.compare(pw, hash)` — both are available in `bcryptjs` and offload to a worker thread internally. Alternatively, replace `bcryptjs` with the native `bcrypt` npm package (requires compile) or `argon2` for future-proof KDF; both offer true async operation. The 10× `hashSync` in the backup-codes path should become `await Promise.all(plainCodes.map(c => bcrypt.hash(c, 12)))`.

---

### [LOW] `uuidv4` (deprecated) pulled in by `@blockchyp/blockchyp-ts`, carries old `uuid` 8.3.2

**Where:** `package-lock.json` — `node_modules/uuidv4: 6.2.13`, `node_modules/uuidv4/node_modules/uuid: 8.3.2`

**What:**
`@blockchyp/blockchyp-ts@2.30.1` depends on `uuidv4@6.2.13`, which is explicitly **deprecated** ("Package no longer supported") and bundles its own copy of `uuid@8.3.2` (2021 release). `uuid@8.3.2` has no known CVEs, but the `uuidv4` wrapper itself has an [GHSA] noting it exposes UUID v1 and v4 from an older API surface. More importantly, the deprecated package receives no security patches.

**Code:**
```json
// node_modules/@blockchyp/blockchyp-ts package.json (resolved in lockfile)
"dependencies": {
  "uuidv4": "^6.2.13"   // deprecated — no longer supported
}
```

**Exploit:**
No direct exploit today. Risk is that future vulnerabilities in the `uuid@8.x` series shipped inside `uuidv4` will not be patched because `uuidv4` is abandoned.

**Fix:**
File an issue / PR with `@blockchyp/blockchyp-ts` to replace `uuidv4` with `uuid@^11`. In the meantime, add an `overrides` entry in the root `package.json` to force `uuidv4/node_modules/uuid` to `^11.0.0` if the API is compatible.

---

### [LOW] `base32@0.0.7` — deeply unmaintained package in payment-processing path

**Where:** `package-lock.json` — `node_modules/base32: 0.0.7`; required by `@blockchyp/blockchyp-ts`

**What:**
`base32@0.0.7` was published in 2012 and has never been updated. The package has 0 issues, 0 PRs, and no activity on its repository. It is used inside `blockchyp-ts` for HMAC-based authentication of payment API calls. A correctness bug or subtle encoding flaw in this package could silently corrupt HMAC signatures or authentication tokens sent to the BlockChyp payment gateway.

**Code:**
```json
// @blockchyp/blockchyp-ts dependency chain
"base32": "^0.0.7"   // published 2012, 0 updates in 13 years
```

**Exploit:**
Exploitation requires discovering a flaw in `base32@0.0.7`'s encoding logic and constructing a HMAC bypass. Unlikely in isolation but raises supply-chain risk given the package's age and lack of any audit.

**Fix:**
Open an issue with `@blockchyp/blockchyp-ts` to replace `base32@0.0.7` with `base32-decode`/`base32-encode` (actively maintained) or `@scure/base` from the same `@noble` family already present in the dependency tree.

---

### [INFO] `bcryptjs` pure-JS vs native `bcrypt` — production KDF library choice

**Where:** `packages/server/package.json:22`

**What:**
The server uses `bcryptjs@3.0.3`, a pure-JavaScript reimplementation of bcrypt with no native bindings. While functionally correct and free of known CVEs, `bcryptjs` is 3–8× slower than the native `bcrypt` npm package (which uses libbcrypt compiled via node-gyp). For a CRM handling concurrent logins across multiple tenants on a single Node.js process, this means each authentication operation holds the CPU longer than necessary even when using the async API, reducing throughput per core.

**Fix:**
Replace `bcryptjs` with `bcrypt` (native) or `argon2` (Argon2id, memory-hard, OWASP-recommended). `bcrypt` drops in as a compatible API replacement; `argon2` requires updating hash verification logic but provides stronger resistance to GPU cracking.

---

### [INFO] Deprecated `moment.js@2.30.1` in payment-processing dependency chain

**Where:** `node_modules/moment: 2.30.1` — required by `@blockchyp/blockchyp-ts`

**What:**
`moment.js` is officially in maintenance mode ("legacy project") since 2020. No new features or security patches are planned. It has a history of ReDoS vulnerabilities in date-parsing paths (CVE-2017-18214, CVE-2022-24785). The installed `2.30.1` is the latest release and has no unpatched CVEs at time of audit, but the package will not receive future security fixes.

**Fix:**
This is a transitive dependency of `blockchyp-ts`; open a PR/issue with the upstream library to migrate to `date-fns` (already used by the `management` package) or native `Temporal`/`Intl` APIs.

---

### [INFO] `lodash@4.18.1` — legitimate security patch release, no supply-chain concern

**Where:** `node_modules/lodash: 4.18.1`

**What:**
`lodash@4.18.1` was published 2026-04-01 by the original author `jdalton` after a ~5-year gap since `4.17.21`. The version appeared suspicious (5-year gap, April Fool's day publish date). A full source diff against `4.17.21` confirms the release contains exclusively legitimate security fixes: prototype-pollution guards added to `baseUnset` path traversal (GHSA-xxjr-mmjv-4gpg, GHSA-f23m-r3pf-42rh), a new `INVALID_TEMPL_IMPORTS_ERROR_TEXT` constant, forbidden-identifier validation in `_.template`, and security warnings in the `_.template` JSDoc. No malicious or unexpected code was found. The npm signature is valid (keyid `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`).

**Fix:**
No action required. The installed version is patched and correct. Note that `lodash` is only a transitive dependency (required by `recharts`, `electron-winstaller`, `@malept/flatpak-bundler`) — it is not a direct server dependency.

---

### [INFO] Packages with native install scripts (supply-chain surface)

**Where:** `package-lock.json` — `hasInstallScript: true` entries

**What:**
The following packages execute native build scripts during `npm install`: `better-sqlite3`, `canvas`, `electron`, `electron-winstaller`, `esbuild`, `fsevents`, `sharp`. These are all well-known packages with legitimate native compilation needs, but they represent the highest-risk attack surface for supply-chain compromise — a malicious release of any of them would execute arbitrary code during `npm ci`. All are at current stable versions.

**Fix:**
Pin these packages to exact versions (remove `^` caret) in `package.json` to prevent automatic minor/patch upgrades pulling in a compromised release. Add `npm audit` and Dependabot/Renovate to CI.

---

## Scope Cleared

The following items were specifically checked and found safe:

- **express CVEs**: 4.22.1 is beyond all 2024 fix thresholds (CVE-2024-29041 required ≥ 4.19.2; CVE-2024-43796 required ≥ 4.20.0).
- **jsonwebtoken alg confusion**: 9.0.3 ships with algorithm-pinning support and the codebase uses `{ algorithms: [...] }` in verify calls (confirmed in S06 slot).
- **multer DoS**: The installed version is 2.x, a full major rewrite; the CVE-2022-24434 affected the 1.x `diskStorage` path only.
- **ws server-sent ping flood**: 8.20.0 is well beyond the 8.17.1 fix threshold for CVE-2024-37890.
- **undici SSRF/header-injection**: 7.24.7 is current and beyond all 2024 CVE fix thresholds.
- **path-to-regexp ReDoS**: 0.1.13 is a patch on top of 0.1.12 (which fixed CVE-2024-45296 and CVE-2024-52798); source diff confirms the change is purely a `backtrack = ''` reset addition.
- **semver ReDoS**: All three semver versions in the tree (5.7.2, 6.3.1, 7.7.4) meet or exceed the CVE-2022-25883 fix thresholds.
- **Non-registry sources**: All 1 023 packages resolve to `registry.npmjs.org`. No GitHub-sourced or private-registry packages outside the four `@bizarre-crm/*` workspace siblings.
- **Integrity hashes**: Every package has a `sha512` integrity field. No missing hashes.
