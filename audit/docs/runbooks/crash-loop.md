# Runbook: Crash Loop

**Severity:** P0 — Customer-impacting
**Expected MTTR:** 5 min
**Last updated:** 2026-04-20

---

## Symptoms

- App crashes immediately or within 3 seconds of launching.
- Relaunching triggers the same crash every time.
- Staff cannot access any app functionality.
- Device shows crash reporter prompt ("BizarreCRM quit unexpectedly").

---

## Triage

### Step 1 — Gather crash context (if possible)

If the device has a second person available to assist:

1. On iOS 16+, navigate to **Settings → Privacy & Security → Analytics & Improvements → Analytics Data**.
2. Find the most recent `BizarreCRM-*.ips` file and note the top frame of the stack trace.
3. Alternatively, connect the device to a Mac with Xcode and open the Devices window to download crash logs.
4. Note any recent changes: was the app just updated? Was a feature flag changed?

If crash log retrieval is not practical (store environment), skip to Step 2.

### Step 2 — Check MetricKit payloads (engineering use)

On a development build or via a connected Mac:

```
MXMetricManager.shared.pastPayloads
```

This surfaces recent hang and crash diagnostics without Xcode. Engineering should check this when investigating root cause.

### Step 3 — Identify the trigger

Common crash-loop causes and their signals:

| Signal | Likely cause | Fix |
|---|---|---|
| Crash immediately on launch, new app version | Bad migration in GRDB schema | Safe Mode (Step 4) → report to engineering |
| Crash after feature flag was changed | Newly-enabled feature has a launch-time bug | Disable suspect flag (Step 4) |
| Crash after login, not before | Auth token in unexpected format | Clear auth tokens (Settings → Developer → Clear Auth Tokens if accessible) |
| Crash only on specific device model | Hardware-specific bug (e.g., camera init on simulator) | Report to engineering with device model |
| Crash in TestFlight only | Build-specific regression | Revert to previous TestFlight build |

---

## Mitigation

### Option A — Safe Mode (all feature flags off)

BizarreCRM supports a Safe Mode that disables all non-core feature flags at launch. This bypasses features that may be causing the crash.

**To activate Safe Mode:**

1. On the device's Home Screen, long-press the BizarreCRM icon.
2. If a "Safe Mode" shortcut appears (App Intent §24): tap it.
3. Alternatively: hold Volume Down while tapping the app icon during the first 2 seconds of launch — this triggers the Safe Mode flag override.

In Safe Mode:
- Core auth, ticket list, customer list, and POS are available.
- All Phase 6+ integrations (widgets, push, Siri) are disabled.
- Hardware peripherals are disabled.

Report the crashing feature to BizarreCRM support with the Safe Mode workaround in place.

### Option B — Feature flag override

If a specific feature flag was recently enabled by an admin:

1. On a working device (or web admin panel): **Settings → Admin → Feature Flags**.
2. Identify the flag changed most recently (sorted by "Last modified").
3. Toggle it off.
4. The crashing device will pick up the flag change on next network sync — if the app can reach the network at all. If it cannot, proceed to Option C.

### Option C — Uninstall and reinstall

**Data is preserved** on the server from the last successful sync.

1. Long-press the BizarreCRM icon → Remove App → Delete App.
2. Reinstall from the App Store or TestFlight.
3. Log in with the correct server URL and credentials.
4. The app pulls the latest server state into the local cache.
5. Any locally-queued writes that had not drained are lost — note these for manual re-entry.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Tenant admin | Disable feature flags; coordinate reinstall |
| 2 | BizarreCRM engineering | Share crash logs + reproduction steps; needed for root cause |
| 3 | BizarreCRM support | `https://bizarrecrm.com/support` |

---

## Post-incident

- Collect the `.ips` crash report and attach it to the support ticket.
- Confirm whether a bad feature flag or schema migration was the root cause.
- Engineering: add regression test covering the crash scenario.
- If > 15 min of store downtime: file a P0 post-mortem per [crisis-playbook.md](crisis-playbook.md).
