# Runbook: Settings Page Broken

**Severity:** P2 — Cosmetic / low-frequency
**Expected MTTR:** 5 min
**Last updated:** 2026-04-20

---

## Symptoms

- A specific settings page opens blank, shows only a spinner, or crashes immediately.
- The settings search returns results but tapping them leads to a broken page.
- A settings form cannot be saved ("Save failed" error or validation loop).

---

## Triage

### Step 1 — Identify the broken page

Note the exact path to the broken page (e.g., **Settings → Hardware → Printer** or **Settings → Roles**). This helps determine whether it is a data-loading issue or a local settings override.

### Step 2 — Force-quit and retry

1. Force-quit BizarreCRM.
2. Relaunch and navigate to the broken settings page.
3. If the page now loads: the issue was transient (stale view state). No further action needed.
4. If it remains broken: proceed to Step 3.

### Step 3 — Clear local settings overrides via Dev Console

Local settings overrides are stored in the device's UserDefaults and can become inconsistent with the server-side schema after an app update.

1. **Settings → Developer → Dev Console** (available in all builds; may require passcode on production builds).
2. Tap "Clear Local Settings Overrides".
3. Confirm the prompt. This resets all locally-cached settings preferences to server defaults.
4. Navigate back to the broken settings page.

**Note:** This does not affect tenancy data (tickets, customers, invoices). Only UI preference overrides are cleared.

### Step 4 — Check server-side settings availability

Some settings pages require a specific server feature to be enabled (e.g., Roles requires the roles API, Multi-location requires the locations endpoint).

1. On the web admin panel (`https://[your-server]/admin`), confirm the relevant feature is enabled for the tenant.
2. If the feature is not enabled, the iOS page may fail gracefully with an empty state — this is expected behavior, not a bug.

### Step 5 — Check role permissions

Some settings pages are only accessible to specific roles (e.g., tenant admins only).

1. Confirm the logged-in user has the required role in **Settings → My Account → Role**.
2. If the role is insufficient: the page will show a "Permission required" state.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Staff self-service | Force-quit, clear overrides (Steps 1-3) |
| 2 | Tenant admin | Role permissions; server feature enablement |
| 3 | BizarreCRM support | `https://bizarrecrm.com/support` — if Dev Console clear does not resolve |

---

## Notes for engineering

Settings sub-pages are independent files under `Packages/Settings/Sources/Settings/`. If a specific page is consistently broken after the clear:

1. Check whether the page's ViewModel is fetching from a server endpoint that may not exist yet (§74 gap).
2. Verify the page uses the `§63` error recovery patterns (shows error state rather than crashing).
3. Confirm the page handles nil data from GRDB gracefully (empty state, not crash).
