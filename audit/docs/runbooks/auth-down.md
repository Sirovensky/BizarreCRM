# Runbook: Auth Down

**Severity:** P0 — Customer-impacting
**Expected MTTR:** 10 min
**Last updated:** 2026-04-20

---

## Symptoms

- Login screen shows an error after entering valid credentials.
- The app was previously authenticated but all API calls now return 401 Unauthorized.
- Staff are unable to log in; existing sessions are being rejected.
- Possible UI: "Authentication failed", "Session expired", infinite loading on login.

---

## Triage (follow in order)

### Step 1 — Is the server reachable?

On the affected device:

1. Open Safari and navigate to the server base URL (shown on the login screen, e.g. `https://app.bizarrecrm.com`).
2. If the page does not load: the server is unreachable. Check Wi-Fi/cellular, then contact BizarreCRM ops.
3. If the page loads but returns 5xx: server-side outage. Contact BizarreCRM ops immediately.
4. If the page loads normally: proceed to Step 2.

### Step 2 — Is the TLS certificate valid?

1. In Safari, tap the lock icon on the server URL.
2. Confirm the certificate is valid (not expired, not from an untrusted CA).
3. If the certificate is invalid or self-signed without the custom CA installed: the app will reject the connection.
   - For self-hosted installs: ensure the server's CA root is installed on the device via MDM or Settings → General → VPN & Device Management.
4. If TLS is healthy: proceed to Step 3.

### Step 3 — Is the tenant slug correct?

1. On the login screen, verify the server URL field matches the exact URL configured for the tenant.
2. A mis-typed slug (e.g., `bizarrecrm` vs `bizarrecrm-east`) will authenticate against the wrong tenant and fail.
3. The correct URL is in your onboarding email or admin panel at `https://bizarrecrm.com/admin`.

### Step 4 — Has the token store become corrupt?

If login fails even with correct credentials and a reachable server:

1. **Settings → Developer → Clear Auth Tokens** (or uninstall and reinstall if Settings is inaccessible).
2. Clearing tokens forces a full re-enrollment. See **Mitigation** below.

---

## Mitigation — Offline read-only mode

While authentication is down, previously authenticated sessions degrade gracefully:

- Staff can view tickets, customers, invoices, and appointments from the GRDB local cache (Phase 0 offline cache).
- **Edit, create, and delete operations are blocked** — the app shows an offline write banner.
- POS checkout via offline queue remains available for devices that were already authenticated before auth went down.
- Clock-in/out is queued locally and will drain on re-auth.

This read-only fallback is automatic. No configuration required.

---

## Full re-enrollment

If the token store is confirmed corrupt or if a staff member is locked out completely:

1. Uninstall the app (data is preserved on the server from the last successful sync).
2. Reinstall from the App Store or TestFlight.
3. Enter the correct server URL and credentials.
4. The app will pull down the latest server state into the local cache on first sync.
5. Any locally-queued writes that were not yet drained are lost — confirm with tenant admin whether any offline ops need manual re-entry.

---

## Escalation path

| Tier | Who | When |
|---|---|---|
| 1 | Tenant admin | Verify server URL + credentials; reset staff accounts if needed |
| 2 | BizarreCRM support | `https://bizarrecrm.com/support` — for server-side auth failures |

---

## Post-incident

- Confirm all affected staff successfully re-authenticate.
- Review server logs for the root cause (expired signing key, database issue, mis-config).
- If auth was down for > 30 min, file a P0 post-mortem per [crisis-playbook.md](crisis-playbook.md).
