# BizarreCRM iOS — Crisis Playbook

**Severity:** All P0/P1 tenant-level incidents
**Owner:** BizarreCRM Ops + iOS Engineering Lead
**Last updated:** 2026-04-20

---

## What this playbook covers

A tenant-level crisis is any incident that blocks a substantial portion of a tenant's staff from conducting business, or that puts customer data at risk. Examples:

- App crashing for all devices at a tenant
- Server-side outage causing all clients to go offline
- Authentication service down for a tenant
- Data breach or suspected unauthorized access
- Corrupt database requiring restore from backup

This playbook covers four areas: **communication**, **rollback**, **disaster recovery**, and **post-mortem**.

---

## 1. Communication Plan

### 1.1 Internal notification (first 5 minutes)

When a P0/P1 is declared:

1. **Incident commander** (on-call engineer or manager): declare the incident in the team channel with severity, scope, and initial symptoms.
2. **Tenant admin contact**: call or text the primary contact for the affected tenant immediately. Do not wait for a fix — communicate first.
3. **Staff notification**: tenant admin notifies their staff via the BizarreCRM in-app broadcast (if accessible) or their preferred out-of-band channel (SMS, Slack, etc.).

### 1.2 Status updates

- P0: update every 5 minutes until resolved.
- P1: update every 15 minutes until resolved.
- Use plain language. Avoid jargon. State: what is broken, what workaround exists, estimated resolution time.

### 1.3 Customer-facing messaging

For incidents visible to end-customers (checkout down, payment processing failed):

- Staff should verbally communicate: "We are experiencing a brief technical issue. We can still process your [cash / email invoice] today."
- Do not share internal error codes or server URLs with customers.

### 1.4 Resolution notification

When resolved: notify the tenant admin with:
- Time of resolution
- Root cause (brief, non-technical)
- Any customer data affected
- Next steps (post-mortem scheduled, etc.)

---

## 2. Rollback Procedure

### 2.1 Feature-flag emergency toggle

The fastest rollback for most incidents is disabling the problematic feature flag.

1. **Web admin panel** (`https://[your-server]/admin`): navigate to **Settings → Feature Flags**.
2. Identify the flag for the suspect feature (flags are named by feature, e.g., `pos.offline_queue.v2`, `dashboard.glass_chrome`).
3. Toggle the flag off. The change is effective on the next app foreground event for all clients.
4. On iOS: the flag is fetched on each launch and on foreground via the `FeatureFlag` system (§1 / `Core/FeatureFlag.swift`).

For an emergency on a device that cannot connect to the server to fetch updated flags: use the Safe Mode procedure in [crash-loop.md](crash-loop.md).

On-device flag override (for testing, requires tenant admin role): **Settings → Admin → Feature Flags → [flag] → Override**.

### 2.2 App version rollback via TestFlight

If a specific app build is causing the incident and a feature flag cannot isolate it:

**Prerequisites:** fastlane is configured and the previous build is available in App Store Connect.

1. Open a terminal with the iOS project root in scope.
2. Run the rollback lane:
   ```
   bundle exec fastlane ios rollback_testflight build:<previous_build_number>
   ```
3. This promotes the previous build to the active TestFlight group.
4. Instruct affected staff to update via TestFlight (they will receive a push notification from TestFlight automatically).

If the rollback build is not in TestFlight, engineering must submit it via:
```
bundle exec fastlane ios beta
```
(This uploads the current commit's build; adjust the git ref first.)

### 2.3 App Store rollback

App Store rollback is not instant (requires Apple review). For urgent App Store incidents:

1. Use the server-side **forced-update banner** (`§33.8`): set `min_supported_version` on the server to the last known-good version. All older builds will see an upgrade prompt; the broken build is blocked.
2. Submit the fixed build to App Store with expedited review request (use sparingly — see §33.6).

---

## 3. Disaster Recovery

### 3.1 Database restore from backup

BizarreCRM server maintains automated backups (§1 Backup/Restore). In the event of data corruption or accidental deletion:

1. **Contact BizarreCRM ops** immediately with:
   - Tenant identifier
   - Approximate time of corruption or last known-good state
   - Nature of the data issue
2. Ops identifies the appropriate backup snapshot (daily snapshots retained for 30 days; hourly for last 7 days).
3. Restore is performed server-side. The iOS app will pull the restored state on next sync.
4. **Important:** any iOS device writes that occurred after the backup snapshot point will conflict with the restored server state. The sync queue will surface these as conflicts. Have tenant admin review and resolve them in the Dead Letter Queue viewer (**Settings → Admin → Sync Status → Dead Letter Queue**).

### 3.2 iOS local cache recovery

If a device's local GRDB cache is corrupt (symptoms: app launches but shows empty data despite being online):

1. **Settings → Developer → Reset Local Cache** (requires confirmation).
2. This deletes the local GRDB database and re-syncs all data from the server.
3. Any locally-queued writes that had not drained are lost — the sync queue is also cleared. Note this risk before proceeding.

If Settings is inaccessible: uninstall and reinstall the app (see [crash-loop.md](crash-loop.md) Option C).

### 3.3 Data sovereignty reassurance

BizarreCRM is a single-tenant architecture: each tenant's data lives in an isolated database on the tenant's chosen server instance. There is no multi-tenant data co-mingling.

Customer data:
- All data is encrypted at rest (SQLCipher on device; server encryption per host configuration).
- In transit: TLS 1.2+ required; optional SPKI pinning available (§1 CLAUDE.md).
- The iOS app never sends data to third-party SDKs (§32 Sovereignty guardrails; SDK ban lint enforced in CI).
- The only network peer is `APIClient.baseURL` — the tenant's own server.

In the event of a suspected breach:
1. Follow the Security Response Protocol in `docs/security/`.
2. Rotate all auth tokens: **Server admin → Auth → Invalidate All Sessions**.
3. Notify affected customers per applicable data protection laws.

---

## 4. Post-Mortem Template

File a post-mortem for all P0 incidents and P1 incidents lasting > 30 min.

```
## Incident Post-Mortem

**Date:** YYYY-MM-DD
**Severity:** P0 / P1
**Incident commander:** [name]
**Duration:** HH:MM (detection → resolution)

### Summary

One paragraph describing what happened and who was affected.

### Timeline

| Time | Event |
|---|---|
| HH:MM | Incident first detected |
| HH:MM | Incident commander notified |
| HH:MM | Tenant admin notified |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | Incident resolved |
| HH:MM | Post-mortem filed |

### Root Cause

Concise technical explanation of what failed and why.

### Impact

- Number of tenants / staff affected:
- Duration of impact:
- Transactions affected (if applicable):
- Customer data exposure (yes / no / suspected):

### Action Items

| Action | Owner | Due date |
|---|---|---|
| Fix root cause | | |
| Add regression test | | |
| Update runbook | | |
| Review related systems | | |

### What went well

- ...

### What could be improved

- ...
```

---

## Quick reference

| Action | Where |
|---|---|
| Feature flag toggle | Web admin → Settings → Feature Flags |
| Drain pause | Settings → Admin → Sync Status → Pause Auto-Drain |
| Dead letter queue | Settings → Admin → Sync Status → Dead Letter Queue |
| Safe Mode | Long-press icon → Safe Mode (or Volume Down on launch) |
| Force widget refresh | Settings → Developer → Force Widget Refresh |
| Reset local cache | Settings → Developer → Reset Local Cache |
| Clear auth tokens | Settings → Developer → Clear Auth Tokens |
| Rollback TestFlight | `bundle exec fastlane ios rollback_testflight build:N` |
| Request DB restore | BizarreCRM ops — `https://bizarrecrm.com/support` |
