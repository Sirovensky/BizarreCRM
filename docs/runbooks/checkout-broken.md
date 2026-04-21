# Runbook: Checkout Broken

**Severity:** P0 — Customer-impacting
**Expected MTTR:** 3 min with offline fallback
**Last updated:** 2026-04-20

---

## Symptoms

- Staff taps "Charge" or "Finalize Sale" in POS; nothing happens or an error appears.
- Cart items are visible but the payment flow will not proceed.
- Customer is present and waiting.
- Possible UI: spinning indicator that never resolves, or inline error banner.

---

## Triage (follow in order, stop when issue found)

### Step 1 — Is BlockChyp terminal paired?

Open **Settings → Hardware → Payment Terminal**.

- If status shows "Unpaired" or "Disconnected": follow [terminal-disconnected.md](terminal-disconnected.md).
- If status shows "Paired" and last heartbeat is recent (< 30 s): proceed to Step 2.

### Step 2 — Is the receipt printer online?

Open **Settings → Hardware → Printer**.

- If printer status is "Offline": the checkout flow may be waiting on a printer handshake. Follow [printer-offline.md](printer-offline.md) to restore or disable the printer requirement.
- If printer is online or print-on-completion is disabled: proceed to Step 3.

### Step 3 — Is the sync queue draining?

Open **Settings → Admin → Sync Status** (or the offline banner if visible).

- Check `pendingCount`. If it is > 50 and rising, the queue may be saturated and blocking new writes.
- If stuck: follow [sync-queue-stuck.md](sync-queue-stuck.md) first, then retry checkout.
- If queue is healthy (pendingCount stable or draining): proceed to Step 4.

### Step 4 — Is network connectivity healthy?

On the device:

1. Open Safari and navigate to `https://bizarrecrm.com` — confirm the page loads.
2. If no connectivity: the device is offline. Offline queue should handle the sale automatically — see **Mitigation** below.
3. If connectivity exists but checkout still fails: proceed to Step 5.

### Step 5 — Is the cart persisted?

- Force-quit the app and relaunch.
- Navigate to POS. The cart should be restored from the GRDB local draft (§63 Draft Recovery).
- If the cart is empty: items were not yet saved. Re-add items manually from the ticket or inventory list.
- If the cart restores: retry checkout.

---

## Mitigation — Offline queue auto-capture

BizarreCRM POS supports full offline checkout (Phase 5 / §20 offline queue).

1. Proceed through checkout normally. The app will detect offline state and queue the sale.
2. The offline indicator banner ("Sale queued — will sync when online") confirms the operation was captured.
3. Hand the customer their receipt (printed if printer is online; email/SMS if not).
4. The queued sale will drain to the server automatically when connectivity is restored.
5. If automatic drain does not occur within 30 minutes of reconnection: follow [sync-queue-stuck.md](sync-queue-stuck.md).

**Important:** Offline captures are idempotent via `Idempotency-Key`. Retrying an offline sale will not double-charge.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Shop manager | Immediately; they have hardware reset access |
| 2 | Tenant admin | If shop manager cannot resolve within 5 min |
| 3 | BizarreCRM support | `https://bizarrecrm.com/support` or in-app "Contact Support" |

---

## Post-incident

- Note time of failure and resolution in the store's incident log.
- If a queued sale was captured offline, confirm it appears in invoices after drain.
- If checkout was broken for > 10 min, file a P0 post-mortem using the template in [crisis-playbook.md](crisis-playbook.md).
