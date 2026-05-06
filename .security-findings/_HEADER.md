

---

# SECURITY AUDIT — BACKEND (server side) — 2026-05-05

Multi-agent deep audit of `packages/server/src/` performed in worktree `claude/security-audit-306cff` off `main@ccb275ba` ("fix(auth): /setup-status reads BOTH wizard_completed keys").

**Methodology:** 36 specialized agents, each focused on one security aspect. Each agent ran ≥25–45 min and ≥60+ tool calls under the protocol at `.security-findings/.PROTOCOL.md`. 12 of the slots (S01–S12) had a shallow Pass 1 followed by a Pass 2 deep dive — both passes are preserved in their files.

**Slots covered:**

| Slot | Aspect |
|------|--------|
| S01 | Auth core — login/sessions/JWT/refresh/remember-me |
| S02 | Password reset, email verification, email change |
| S03 | 2FA / TOTP / step-up / recovery codes / device-trust |
| S04 | POS PIN / manager-override / sensitive POS ops |
| S05 | Master / super-admin auth + admin HTML/JS |
| S06 | JWT secrets — signing, verification, alg pinning, audience |
| S07 | CSRF — double-submit, SameSite, exempted webhooks |
| S08 | Multi-tenant isolation (tenant resolver, pool, master DB) |
| S09 | RBAC / role gates / privilege escalation |
| S10 | Tenant provisioning / repair / termination lifecycle |
| S11 | Tenant + data export, scheduled exports, backups |
| S12 | SQL injection sweep across all DB call sites |
| S13 | XSS in admin HTML, email/SMS templates, public pages |
| S14 | Path traversal in uploads / imports / backups |
| S15 | SSRF in geocode / DNS / scrapers / wallet pass / image fetch |
| S16 | XML / XXE / unsafe deserialization |
| S17 | RCE via eval / new Function / child_process / vm |
| S18 | Prototype pollution / mass assignment / body-parser quirks |
| S19 | Money endpoints — IDOR, amount tampering, race conditions |
| S20 | BlockChyp payment-terminal integration |
| S21 | Stripe + payment webhook handlers |
| S22 | Loyalty / store credit / counters / commissions arithmetic |
| S23 | PII exposure on customer / search / activity / portal |
| S24 | Logging secrets / error message leakage / request logger PII |
| S25 | Data retention / hard-delete / GDPR right-to-erasure |
| S26 | Zip-slip / tar-slip / CSV formula injection |
| S27 | Signed upload / download URLs |
| S28 | Rate-limit completeness across sensitive flows |
| S29 | CORS / Helmet / security headers / trust proxy / body limits |
| S30 | WebSocket auth / authorization / broadcast scoping |
| S31 | Cron / background jobs / scheduled services |
| S32 | Configuration encryption (secrets at rest) |
| S33 | Provider creds in DB and exposure on read endpoints |
| S34 | hCaptcha / reCAPTCHA integration |
| S35 | Public / unauth surface (booking / portal / voice / pay-link) |
| S36 | HOLISTIC — middleware order, request lifecycle, cross-module |

**Severity scale:** CRITICAL > HIGH > MEDIUM > LOW > INFO.

**How to use this appendix:**
- Each finding has `Where:` (file:line), `What:`, `Code:`, `Exploit:`, `Fix:`.
- Treat any CRITICAL or HIGH as drop-everything. MEDIUMs are next-sprint priority. LOWs and INFOs are hardening backlog.
- Backup of this appendix lives at `SECURITY_AUDIT_2026-05-05.md` in the repo root in case TODO.md is overwritten.
- Per-slot raw files live at `.claude/worktrees/security-audit-306cff/.security-findings/SXX-*.md`.
- Master branch impacted: `claude/security-audit-306cff` (read-only worktree, no source edits).

---

