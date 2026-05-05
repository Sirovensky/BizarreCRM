# Runbook: Push Notifications Delayed

**Severity:** P2 — Cosmetic / low-frequency
**Expected MTTR:** 10 min
**Last updated:** 2026-04-20

---

## Symptoms

- Push notifications are arriving minutes or hours after the triggering event.
- Some push notifications never arrive even though the in-app notification list shows them.
- Badge count on the app icon is wrong (shows old unread count).

---

## Triage

### Step 1 — Check APNs service status

1. Open `https://www.apple.com/support/systemstatus/` on any browser.
2. Look for **Apple Push Notification service** in the list.
3. If APNs shows an outage or degraded state: this is outside BizarreCRM's control. Monitor the status page and communicate expected delay to staff.
4. If APNs is operational: proceed to Step 2.

### Step 2 — Verify device push settings

1. **iOS Settings → Notifications → BizarreCRM** — confirm "Allow Notifications" is on.
2. Confirm **Time Sensitive Notifications** is on (BizarreCRM uses `.timeSensitive` for appointment reminders and urgent alerts).
3. Confirm the device is not in Focus mode that blocks BizarreCRM notifications (**iOS Settings → Focus → your active Focus → Apps → check BizarreCRM is allowed**).
4. Confirm the device is not in Low Power Mode (background network activity is restricted).

### Step 3 — Check silent push quota

APNs imposes a limit on silent push notifications (background updates). If BizarreCRM is sending high volumes of silent pushes (e.g., every sync cycle), the system may throttle them.

Signs: silent pushes slow down while user-facing pushes are delivered normally.

Resolution: the server team should audit `/telemetry/apns` delivery rates and reduce silent push frequency if over quota. Tenant admin can also adjust notification frequency in **Settings → Notifications → Sync Push Frequency**.

### Step 4 — Manual badge count refresh

If the badge count is wrong:

1. Open BizarreCRM and navigate to the Notifications list.
2. Scroll through all notifications (this marks them read and triggers a badge recount).
3. Alternatively: **Settings → Developer → Reset Badge Count** (Debug/Staging builds).

---

## Resolution for persistent delay

If pushes are consistently late (> 5 min) and APNs is healthy:

1. Confirm the APNs certificate or auth key on the server has not expired. Server team checks **Settings → APNs → Certificate Expiry** in the BizarreCRM server admin panel.
2. Rotate the APNs auth key if expired: Fastlane `produce_push_certificate` action, then upload new key to server config. The Fastlane lane for this is `ios/fastlane/Fastfile` lane `rotate_apns`.
3. After rotation, test with a manual push from **Settings → Admin → Send Test Push** in the web admin panel.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Tenant admin | Verify notification permissions; adjust frequency |
| 2 | BizarreCRM server team | APNs cert/key rotation; delivery rate audit |
| 3 | Apple Developer Support | If APNs account-level issues |
