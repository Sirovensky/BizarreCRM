# Security Audit Plan — Before Sharing Code or Server Access

*Created: 2026-04-05*

## Quick Checklist

Run this before every code share, deploy, or repo push:

### 1. Scan for hardcoded secrets
```bash
# From project root:
grep -rn "cze_\|sk-\|sk_live\|ghp_\|glpat-\|AKIA\|AIza" --include="*.ts" --include="*.tsx" --include="*.json" --include="*.md" --include="*.html" --include="*.sh" .
```

### 2. Scan for hardcoded passwords
```bash
grep -rn "admin123\|superadmin123\|password123\|changeme\|change-me" --include="*.ts" --include="*.tsx" --include="*.md" --include="*.html" .
```

### 3. Scan for personal info (emails, phones, addresses)
```bash
grep -rn "sirovensky\|pavel@\|303-261\|3032611911\|506 11th\|Longmont\|@gmail\.com" --include="*.ts" --include="*.tsx" --include="*.json" --include="*.md" --include="*.html" .
```

### 4. Scan for brand-specific references that should be generic
```bash
grep -rn "Bizarre Electronics\|bizarreelectronics\|repairdesk\.3cx" --include="*.ts" --include="*.tsx" --include="*.json" --include="*.md" --include="*.html" .
```

### 5. Check .env is NOT committed
```bash
git status .env
# Should say "nothing to commit" or not listed
```

### 6. Check database files are NOT committed
```bash
git status packages/server/data/
# Should show nothing tracked
```

### 7. Check uploads are NOT committed
```bash
git status packages/server/uploads/
# Should show nothing tracked (except .gitkeep)
```

### 8. Check certs are NOT committed
```bash
git status packages/server/certs/
# Should show nothing tracked
```

---

## Files That Must NEVER Be Shared

| File/Directory | Why |
|---|---|
| `.env` | JWT secrets, API keys |
| `packages/server/data/*.db` | Customer PII, financial data |
| `packages/server/data/tenants/*.db` | Per-tenant customer data |
| `packages/server/uploads/` | Customer device photos |
| `packages/server/certs/` | SSL private keys |
| `packages/server/data/master.db` | Tenant registry, billing |

## Files Safe to Share

| File/Directory | Notes |
|---|---|
| All `src/` code | No secrets in source |
| `.env.example` | Placeholder values only |
| `package.json`, `tsconfig.json` | Config only |
| `README.md` | Generic setup instructions |
| `.gitignore` | |
| `deploy/nginx.conf` | No secrets |

## Current Known Issues Found (2026-04-05)

### CRITICAL — Must Fix Before Sharing

1. **`.env` has real JWT secrets and RepairDesk API key**
   - Action: Delete `.env` before sharing, or ensure `.gitignore` excludes it
   - Long-term: Move secrets to per-tenant DB (see multi-tenant plan)

2. **`scripts/README.md` contains partial API key**
   - Action: Remove or redact

3. **Default passwords in documentation**
   - `admin123` in README.md, HOWTOGETBACK.md, seed.ts
   - `superadmin123` in index.ts
   - Action: These are intentional defaults for first-time setup (user MUST change on first login). Document that clearly.

### HIGH — Fix Soon

4. **Database backup with real customer data**
   - `packages/server/data/bizarre-crm-backup-20260405.db` (18MB, 958 customers)
   - Action: Delete before sharing, or move to external backup location

5. **Customer photos in uploads/**
   - Action: Clear before sharing

6. **SSL private key in certs/**
   - Action: Regenerate per-deployment, never share

### MEDIUM — Improve

7. **Dev fallback secrets in config.ts**
   - `dev-secret-change-me`, `dev-refresh-secret`, `super-admin-dev-secret`
   - These only apply when env vars are not set — acceptable for dev
   - Production mode already rejects missing secrets

8. **google-services.json has placeholder values**
   - Not real credentials, but should be in .gitignore for production

---

## Multi-Tenant Secret Strategy

Since we run one server for all tenants, secrets should be per-tenant in their database, NOT in .env:

| Secret | Where to Store | Status |
|---|---|---|
| JWT_SECRET | `.env` (shared, one per server) | Already there |
| JWT_REFRESH_SECRET | `.env` (shared) | Already there |
| SUPER_ADMIN_SECRET | `.env` (shared) | Already there |
| RepairDesk API Key | Per-tenant `store_config` table | Each shop enters their own |
| 3CX credentials | Per-tenant `store_config` table | Each shop enters their own |
| SMTP credentials | Per-tenant `store_config` table | Each shop enters their own |
| BlockChyp API keys | Per-tenant `store_config` table | Already stored per-tenant |
| Twilio/SMS keys | Per-tenant `store_config` table | Each shop enters their own |
| Store name/phone/email | Per-tenant `store_config` table | Set during first-time setup |

The `.env` should ONLY contain:
```env
# Server-level (shared across all tenants)
PORT=3020
NODE_ENV=production
JWT_SECRET=<random>
JWT_REFRESH_SECRET=<random>
SUPER_ADMIN_SECRET=<random>
MULTI_TENANT=true
BASE_DOMAIN=bizarrecrm.com

# Everything else is per-tenant in the database
```

---

## Automated Pre-Commit Hook (Recommended)

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
# Block commits containing potential secrets
if git diff --cached --name-only | xargs grep -lE "(sk-|cze_|AKIA|ghp_|password.*=.*['\"][^'\"]{8,})" 2>/dev/null; then
    echo "ERROR: Potential secret detected in staged files!"
    exit 1
fi
```

---

# EXHAUSTIVE ATTACK SURFACE AUDIT (2026-04-05)

## 1. AUTHENTICATION & AUTHORIZATION

| # | Check | Files | Status |
|---|-------|-------|--------|
| 1.1.1 | Can user login without password? | auth.routes.ts:232-240 | ✅ password_set=0 only issues challenge, never JWT |
| 1.1.2 | Can user skip 2FA? | auth.routes.ts:318-385 | ✅ issueTokens() ONLY called inside 2fa-verify handler |
| 1.1.3 | Challenge tokens reused? | auth.routes.ts:75-78 | ✅ consumeChallenge deletes after use |
| 1.1.4 | Challenge tokens brute-forceable? | auth.routes.ts:64 | ✅ UUIDv4 = 122 bits entropy. Infeasible. |
| 1.1.5 | Server restart mid-2FA? | auth.routes.ts:54 | ⚠️ In-memory only. User must restart login. Acceptable. |
| 1.1.6 | Backup codes reusable? | auth.routes.ts:414-426 | ✅ Spliced from array, DB updated |
| 1.1.7 | Deactivated user login? | auth.routes.ts:222 | ✅ `is_active = 1` in login query |
| 1.1.8 | Password length DoS? | auth.routes.ts:244 | ⚠️ bcrypt truncates at 72 bytes. No server-side max. Should add 128 char limit. |
| 1.2.1 | JWT payload contents | auth.routes.ts:162 | ✅ userId, sessionId, role, tenantSlug — no PII |
| 1.2.2 | JWT secret entropy check | config.ts | ⚠️ Dev fallback exists. Production multi-tenant exits if not set. |
| 1.2.3 | JWT algorithm confusion | auth.ts:34 | ✅ jwt.verify defaults to HS256, rejects none/RS256 |
| 1.2.4 | Separate refresh secret | config.ts | ✅ JWT_REFRESH_SECRET is separate |
| 1.2.5 | Refresh as access token? | auth.ts:36-39 | ✅ Rejects if `payload.type === 'refresh'` |
| 1.2.6 | JWT expired mid-request | auth.ts:78 | ✅ jwt.verify throws, caught, returns 401 |
| 1.2.7 | Sessions after password change? | auth.routes.ts | ⚠️ NOT invalidated. Should delete sessions on password change. |
| 1.2.8 | Sessions after deactivation? | Various | ✅ Session cleanup on user deactivation implemented |
| 1.3.1 | Non-admin on admin endpoints? | settings.routes.ts:30-33 | ✅ adminOnly middleware checks role |
| 1.3.2 | User changes own role? | employees.routes.ts | ⚠️ NEEDS VERIFICATION — check if role is stripped from update body |
| 1.3.3 | Tech bulk-deletes tickets? | tickets.routes.ts | ✅ Bulk delete requires admin role |
| 1.3.4 | Tech modifies other users? | employees.routes.ts | ⚠️ NEEDS VERIFICATION |
| 1.4.1 | PIN switch bypasses 2FA? | auth.routes.ts:500+ | ✅ Issues new JWT but requires existing auth session first |
| 1.4.2 | PIN hashed? | seed.ts, auth.routes.ts | ✅ bcrypt cost 12 |
| 1.4.3 | PIN requires session? | auth.routes.ts:500 | ✅ authMiddleware applied |
| 1.4.4 | PIN rate limited? | auth.routes.ts:117-137 | ✅ 5/15min per IP |

## 2. MULTI-TENANT ISOLATION

| # | Check | Status |
|---|-------|--------|
| 2.1.1 | All routes use req.db | ✅ Verified all 36 files |
| 2.1.2 | All services accept db param | ✅ Verified 7 service files |
| 2.1.3 | req.db can't be master DB | ✅ tenantResolver only sets tenant DBs |
| 2.1.4 | req.db can't be other tenant | ✅ Slug from Host header, validated against master DB |
| 2.1.5 | Path traversal in DB path | ✅ Regex + path.resolve containment check |
| 2.2.1-5 | Token isolation | ✅ All verified (see MT audit above) |
| 2.3.1 | In-memory Maps tenant-keyed | ✅ FIXED — SMS rate limiter, challenge tokens |
| 2.3.2 | SMS provider per-tenant | ✅ FIXED — per-tenant cache with TTL |
| 2.3.3 | Broadcasts scoped | ✅ FIXED — all 29 calls pass tenantSlug |
| 2.3.4 | WS client keys composite | ✅ tenantSlug:userId |
| 2.3.5 | Background task isolation | ✅ forEachDb with temp connections |
| 2.4.1-4 | File system isolation | ✅ FIXED — logo, MMS, recordings now tenant-scoped |
| 2.5.1-5 | Super admin separation | ✅ All verified (see MT audit above) |

## 3-16. REMAINING SECTIONS

To be audited — see checklist items above. Each will be verified against actual code, documented with file:line references, and any issues will be added to AUDIT_REPORT.md.

### AUDIT EXECUTION RESULTS (2026-04-05)

| # | Check | Result | Action |
|---|-------|--------|--------|
| 1.1.8 | Max password length | ⚠️ OPEN | Add 128 char server-side limit |
| 1.2.7 | Sessions on password change | ✅ FIXED | Added `DELETE FROM sessions WHERE user_id = ?` after password update |
| 1.3.2 | User role self-change | ✅ NOT AN ISSUE | Endpoint is admin-only. Admins should be able to change roles. |
| 1.3.4 | Tech modify other users | ✅ NOT AN ISSUE | Endpoint is admin-only. Techs can't access it. |
| 3.2.2 | dangerouslySetInnerHTML | ✅ SAFE | All usages sanitized with DOMPurify strict allowlist |
| 5.3.1 | Error handler leakage | ✅ SAFE | Stack traces only in console (dev), response is always generic |
| 12.4 | FTS search DoS | ⚠️ OPEN | No max search string length. Add 200 char limit. |
| 13.7 | Source maps in production | ✅ FIXED | Changed to `sourcemap: process.env.NODE_ENV !== 'production'` |
| 13.8 | .env accessible via HTTP | ✅ SAFE | dotfiles: 'deny' + path traversal checks prevent access |
| 3.4.1 | Command injection | ✅ SAFE | No execSync/exec with user input anywhere |
| 14.7 | Negative stock | ✅ SAFE | `if (newStock < 0) throw AppError` check present |
| 14.8 | Refund exceeds payment | ⚠️ OPEN | Refund amount not validated against invoice total |

### REMAINING OPEN ITEMS

| # | Severity | Issue | Action |
|---|----------|-------|--------|
| 1.1.8 | LOW | No max password length (bcrypt 72-byte limit) | Add 128 char server-side limit |
| 12.4 | LOW | FTS search string unlimited | Add 200 char max |
| 14.8 | MEDIUM | Refund can exceed invoice total | Add amount validation |
| S6 | MEDIUM | CSP unsafe-inline | Move admin script to separate file |
| W1 | HIGH | Wrong localStorage key for MMS upload | Fix 'token' → 'accessToken' |
