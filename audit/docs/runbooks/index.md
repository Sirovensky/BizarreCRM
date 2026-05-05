# BizarreCRM iOS — Incident Runbook Index

**Last updated:** 2026-04-20
**Owner:** BizarreCRM Ops / iOS Engineering

---

## How to use this index

1. Identify symptoms from the table below.
2. Open the linked runbook.
3. Follow triage steps in order — do not skip.
4. If MTTR is exceeded, escalate to the next tier immediately.

---

## P0 — Customer-impacting (act immediately)

| Runbook | Summary | Expected MTTR |
|---|---|---|
| [checkout-broken.md](checkout-broken.md) | POS cart won't finalize; customer present and waiting. Offline queue auto-captures; drain later. | 3 min |
| [sync-queue-stuck.md](sync-queue-stuck.md) | `pendingCount > 0` for > 30 min; writes not reaching server. | 15 min |
| [auth-down.md](auth-down.md) | Login fails or 401 on every request; staff locked out. Offline read-only mode available. | 10 min |
| [crash-loop.md](crash-loop.md) | App crashes on launch; store operations blocked. Safe Mode via feature flags. | 5 min |

---

## P1 — Staff-impacting (workaround exists)

| Runbook | Summary | Expected MTTR |
|---|---|---|
| [printer-offline.md](printer-offline.md) | Receipt printer unreachable. Fall back to AirPrint or email PDF. | 5 min |
| [terminal-disconnected.md](terminal-disconnected.md) | BlockChyp terminal not pairing. Fall back to manual card entry or cash. | 5 min |
| [camera-unresponsive.md](camera-unresponsive.md) | Camera session hangs; barcode/doc-scan blocked. Fall back to photo library. | 3 min |

---

## P2 — Cosmetic or low-frequency

| Runbook | Summary | Expected MTTR |
|---|---|---|
| [widget-stale.md](widget-stale.md) | Home/Lock screen widget shows outdated data. Force timeline refresh. | 2 min |
| [push-delayed.md](push-delayed.md) | Push notifications arriving late or not at all. APNs status check + manual badge refresh. | 10 min |
| [settings-page-broken.md](settings-page-broken.md) | A settings screen is blank or crashes. Clear local settings overrides via Dev Console. | 5 min |

---

## Supporting documents

| Document | Purpose |
|---|---|
| [crisis-playbook.md](crisis-playbook.md) | Tenant-level crisis management: communication, rollback, DR, post-mortem. |
| [first-responder-cheatsheet.md](first-responder-cheatsheet.md) | 1-page printable summary of key commands and escalation contacts. |
