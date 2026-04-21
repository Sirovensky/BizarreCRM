# Runbook: Camera Unresponsive

**Severity:** P1 — Staff-impacting (workaround exists)
**Expected MTTR:** 3 min
**Last updated:** 2026-04-20

---

## Symptoms

- Tapping any camera action (barcode scan, document scan, photo capture, receipt OCR) opens a blank or frozen camera preview.
- Camera viewfinder shows a black screen or spins indefinitely.
- App does not respond to shutter or cancel buttons while the camera is open.

---

## Triage and resolution

### Step 1 — Dismiss and retry

1. Tap the "X" or "Cancel" button to dismiss the camera view.
2. Wait 5 seconds.
3. Attempt the camera action again.
4. If the camera opens correctly: no further action needed.

### Step 2 — Check camera permission

1. **iOS Settings → BizarreCRM → Camera** — confirm the toggle is enabled.
2. If disabled: enable it, return to BizarreCRM, and retry.
3. BizarreCRM requires camera access for barcode scanning (§17.2), document scanning (§5), receipt OCR (§39), and photo annotation.

### Step 3 — Restart the camera session

If the camera view opens but the preview is frozen:

1. Force-quit BizarreCRM: swipe up from the bottom of the screen (or double-press Home on older devices) and swipe away the BizarreCRM card.
2. Relaunch BizarreCRM.
3. Retry the camera action.

This clears any stale `AVCaptureSession` state that was not properly torn down.

### Step 4 — Verify no other app has camera in use

iOS allows only one app at a time to use the camera. If another app (FaceTime, another scanner) has the camera:

1. Check the green camera-in-use indicator in the status bar.
2. Force-quit any other app using the camera.
3. Retry BizarreCRM camera.

---

## Fallback options

### Fallback A — Photo library

For any camera capture that accepts an existing image (receipt scan, ticket photo, product photo):

1. When the camera action opens, tap "Choose from Library" (or the photo icon in the camera UI).
2. Select a photo taken previously or taken outside the app with the native camera.

### Fallback B — Type manually

For barcode scanning:

1. Tap "Enter Barcode Manually" in the barcode scanner.
2. Type the SKU or barcode number using the keyboard.

For receipt OCR:

1. Skip OCR pre-fill.
2. Enter expense details manually.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Shop manager | Device-level camera restart, permission check |
| 2 | BizarreCRM support | `https://bizarrecrm.com/support` — if camera session restart does not resolve |

---

## Notes for engineering

Camera session lifecycle is managed in `Packages/Camera/Sources/Camera/`. If a crash or hang occurs in the camera session, check:

- `AVCaptureSession.isRunning` state at the point of failure.
- Whether `stopRunning()` is called on session teardown in every dismiss path.
- Whether the camera preview layer is being re-added on re-present without removing the old one.
