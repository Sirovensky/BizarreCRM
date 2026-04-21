# Runbook: Widget Stale

**Severity:** P2 — Cosmetic / low-frequency
**Expected MTTR:** 2 min
**Last updated:** 2026-04-20

---

## Symptoms

- Home Screen, Lock Screen, or StandBy widget shows data that is clearly out of date (e.g., wrong ticket count, old revenue figure).
- The main app shows correct data but the widget has not updated.
- Widget may show "Updated X hours ago" with an unusually old timestamp.

---

## Cause

iOS controls widget refresh scheduling via WidgetKit timelines. The system throttles refreshes to preserve battery. Under low power mode, background activity restrictions, or heavy system load, widgets may not refresh on the expected schedule.

BizarreCRM widgets read from the shared **App Group GRDB database** (`group.com.bizarrecrm`). If the main app has not written a fresh snapshot to the App Group cache, the widget will show stale data regardless of the WidgetKit timeline.

---

## Resolution

### Step 1 — Force the main app to write a fresh snapshot

1. Open BizarreCRM.
2. Navigate to the screen that drives the widget (e.g., Dashboard for the overview widget, Tickets list for the ticket count widget).
3. Pull to refresh (drag down from the top of the list).
4. Wait for the spinner to complete. This writes the latest data to the App Group cache.

### Step 2 — Force the widget timeline to refresh

After updating the App Group cache:

1. Long-press the widget on the Home Screen.
2. Tap "Edit Widget" (or "Reload Widget" if available).
3. Exit the widget edit mode. iOS should schedule an immediate reload.

Alternatively, from inside BizarreCRM:

1. **Settings → Developer → Force Widget Refresh** (available in Debug and Staging builds).
2. This calls `WidgetCenter.shared.reloadAllTimelines()` immediately.

### Step 3 — Verify

- Return to the Home Screen.
- Confirm the widget now shows current data (matching what the main app displays).

---

## If the widget remains stale after a forced refresh

This may indicate the App Group database is not being written correctly. Check:

1. **Settings → Admin → Sync Status** — confirm the last successful sync was recent.
2. If sync is stuck, follow [sync-queue-stuck.md](sync-queue-stuck.md) first, then retry widget refresh.
3. If the device is in Low Power Mode: iOS aggressively throttles widget refresh. Disable Low Power Mode (**Settings → Battery → Low Power Mode**) to allow normal refresh.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Staff self-service | Steps 1-3 above |
| 2 | BizarreCRM support | `https://bizarrecrm.com/support` — if widget never refreshes after sync is confirmed healthy |

---

## Notes for engineering

Widget data flow: main app sync → GRDB write → App Group container GRDB (`group.com.bizarrecrm`) → WidgetKit timeline entry read.

If the App Group write is not happening, check `Packages/Dashboard/Sources/Dashboard/WidgetSnapshotWriter.swift` and confirm it is called after every successful sync drain in `Packages/Sync/`.
