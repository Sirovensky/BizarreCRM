# Runbook: Sync Queue Stuck

**Severity:** P0 — Customer-impacting
**Expected MTTR:** 15 min
**Last updated:** 2026-04-20

---

## Symptoms

- Offline sync banner shows `pendingCount > 0` for more than 30 minutes without decreasing.
- Network connectivity is confirmed (Safari loads pages normally).
- New writes may still succeed locally but are not reaching the server.
- Reports or other devices do not reflect recent changes.

---

## Diagnosis

### Step 1 — Open the Dead Letter Queue viewer

**Settings → Admin → Sync Status → Dead Letter Queue**

This viewer was shipped in Phase 0 (§20). It shows every operation that failed more than the configured retry limit.

- If the dead letter queue is **empty** and `pendingCount` is still positive: the drain loop may be paused or the network is intermittently failing. Jump to Step 3.
- If the dead letter queue has **entries**: identify the failing operation type (e.g., `invoice.create`, `ticket.update`). Proceed to Step 2.

### Step 2 — Identify the failing operation

For each dead-lettered operation:

1. Tap the entry to expand details.
2. Note the **error code** and **last server response** (HTTP status + message body).
3. Common causes:

| Error | Likely cause | Action |
|---|---|---|
| 401 Unauthorized | Auth token expired or revoked | Follow [auth-down.md](auth-down.md); re-auth clears token, retries drain |
| 409 Conflict | Concurrent edit from another device | Review the conflicting record; resolve manually; retry op |
| 422 Unprocessable | Server validation failure | The local payload is malformed; inspect and discard or edit |
| 5xx Server Error | Server-side outage | Contact BizarreCRM ops; pause auto-drain until resolved |
| Timeout | Network too slow or proxy issue | Switch to Wi-Fi; retry |

### Step 3 — Check drain loop health

**Settings → Admin → Sync Status → Drain Log**

- Confirm the drain loop last ran recently (within the past 2 minutes).
- If "Last drain attempt" is > 10 min ago: the drain loop may have crashed. Force-quit and relaunch the app to restart it.
- If drain is running but all ops are failing: consider pausing auto-drain (see **Mitigation**).

---

## Mitigation

### Option A — Retry dead-lettered operations

In the Dead Letter Queue viewer:

1. Tap "Retry All" to re-queue all dead-lettered ops for the next drain cycle.
2. Monitor `pendingCount` for 2 minutes. If it drops, the issue is resolved.
3. If retries fail again with the same error: investigate that specific error (see Step 2 table above).

### Option B — Pause auto-drain + contact ops

If the failure is systemic (all ops failing with 5xx or timeouts):

1. **Settings → Admin → Sync Status → Pause Auto-Drain** (toggle).
2. This prevents new failures from accumulating in dead letter queue.
3. Local writes continue to queue locally; no data is lost.
4. Contact BizarreCRM ops (`https://bizarrecrm.com/support`) with the error details.
5. Resume auto-drain once ops confirms the server issue is resolved.

---

## Rollback — Clear a specific operation

**Admin action required.** Use this only when an operation is permanently unresolvable (e.g., references a deleted record).

1. Open Dead Letter Queue viewer.
2. Tap the specific operation.
3. Tap "Discard Operation" (requires tenant admin role).
4. The operation is removed. The local record may be in an inconsistent state — manually verify it.

**Warning:** Discarding an op is irreversible. The write will not reach the server.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Tenant admin | Immediately; drain pause + DLQ clear requires admin role |
| 2 | BizarreCRM support | If systemic server-side failure |

---

## Post-incident

- Document which ops were retried vs discarded.
- Verify affected records on both device and server web UI for consistency.
- If data loss occurred, trigger server backup restore per [crisis-playbook.md](crisis-playbook.md).
