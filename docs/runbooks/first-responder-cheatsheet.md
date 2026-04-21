# BizarreCRM iOS — First Responder Cheatsheet

> Print this page and keep it at the POS station or manager's desk.
> For detailed steps see the full runbooks at `docs/runbooks/`.

---

## Escalation Contacts

| Tier | Who | How |
|---|---|---|
| 1 | Shop manager | On-site |
| 2 | Tenant admin | Internal contact list |
| 3 | BizarreCRM support | https://bizarrecrm.com/support |

---

## P0 Incidents — Act immediately

### Checkout broken (customer waiting)

1. Is terminal paired? → **Settings → Hardware → Payment Terminal**
2. Is printer online? → **Settings → Hardware → Printer**
3. Is network working? → Open Safari, load bizarrecrm.com
4. If offline: checkout queues automatically — give receipt, drain later
5. MTTR: **3 min**

### Sync queue stuck (pendingCount > 0 for 30+ min)

1. Open **Settings → Admin → Sync Status → Dead Letter Queue**
2. Check error on failing op (401 = re-auth; 5xx = server issue)
3. Tap "Retry All" — watch pendingCount drop
4. If systemic: **Pause Auto-Drain** → call ops
5. MTTR: **15 min**

### Auth down (401 on everything / can't log in)

1. Can Safari reach your server URL? If not: server outage → call ops
2. Check TLS cert (padlock in Safari)
3. Check tenant slug in login URL field
4. Last resort: **Settings → Developer → Clear Auth Tokens** → re-login
5. Offline: read-only mode is available (view tickets/customers, no edits)
6. MTTR: **10 min**

### App crash on launch

1. Try relaunching 2x
2. Long-press icon → **Safe Mode** (or hold Volume Down on launch)
3. In Safe Mode, disable the suspect feature flag: **Settings → Admin → Feature Flags**
4. If nothing works: uninstall + reinstall (data is on server)
5. MTTR: **5 min**

---

## P1 Incidents — Workaround available

### Printer offline

1. **Settings → Hardware → Printer → Test Print**
2. If fails: power-cycle printer, re-pair
3. Fallback: tap **Print → AirPrint** or **Send Receipt → Email/SMS**
4. Disable "Require Print Before Finalise" if needed
5. MTTR: **5 min**

### Terminal disconnected

1. **Settings → Hardware → Payment Terminal → Reconnect**
2. If fails: Remove + re-pair (get IP from terminal screen)
3. Fallback: **Manual Card Entry** or **Cash** or **Payment Link**
4. MTTR: **5 min**

### Camera frozen

1. Dismiss camera, wait 5 s, retry
2. Check **iOS Settings → BizarreCRM → Camera** (must be ON)
3. Force-quit app, relaunch, retry
4. Fallback: **Choose from Library** or type barcode manually
5. MTTR: **3 min**

---

## P2 Incidents — Self-service

### Widget shows stale data

1. Open BizarreCRM → navigate to widget's data screen → pull to refresh
2. Long-press widget → Edit Widget (forces reload)
3. MTTR: **2 min**

### Push notifications late

1. Check APNs status: apple.com/support/systemstatus
2. Check **iOS Settings → Notifications → BizarreCRM** (must be ON)
3. Check Focus mode is not blocking BizarreCRM
4. Manual refresh: open BizarreCRM Notifications list
5. MTTR: **10 min**

### Settings page blank/broken

1. Force-quit + relaunch + retry
2. **Settings → Developer → Dev Console → Clear Local Settings Overrides**
3. MTTR: **5 min**

---

## Key Admin Paths (quick reference)

```
Feature flags:        Settings → Admin → Feature Flags
Sync status:          Settings → Admin → Sync Status
Dead letter queue:    Settings → Admin → Sync Status → Dead Letter Queue
Dev console:          Settings → Developer → Dev Console
Clear auth tokens:    Settings → Developer → Clear Auth Tokens
Reset local cache:    Settings → Developer → Reset Local Cache
Force widget refresh: Settings → Developer → Force Widget Refresh
Hardware (printer):   Settings → Hardware → Printer
Hardware (terminal):  Settings → Hardware → Payment Terminal
```

---

## Rollback commands (engineering)

```bash
# Roll back TestFlight to a specific build
bundle exec fastlane ios rollback_testflight build:<build_number>

# Submit new build to TestFlight
bundle exec fastlane ios beta

# Rotate APNs key
bundle exec fastlane ios rotate_apns
```

---

*For the full crisis playbook and post-mortem template, see `docs/runbooks/crisis-playbook.md`.*
