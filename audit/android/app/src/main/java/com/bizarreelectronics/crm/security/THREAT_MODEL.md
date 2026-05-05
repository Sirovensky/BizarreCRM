# Bizarre Electronics CRM — Android STRIDE Threat Model

**Plan reference:** §28 L2513–L2518  
**Last updated:** 2026-04-23  
**Scope:** Android client (com.bizarreelectronics.crm)

---

## Overview

This document applies the STRIDE framework to the Bizarre Electronics CRM Android
application.  Each category lists the primary threats and the countermeasures
currently implemented or planned.

---

## S — Spoofing (Identity)

**Threats**
- An attacker impersonates a legitimate user by replaying a stolen credential.
- A malicious app claims to be the CRM via a deep-link scheme (`bizarrecrm://`).
- A MITM forges server identity to intercept credentials.

**Countermeasures**
- **2FA / TOTP** — enforced on first login; bypasses require server-side OTP.
- **Passkeys (FIDO2)** — phishing-resistant authentication via CredentialManager
  (`PasskeyManager`).  Hardware security keys (USB-C / NFC) supported transparently.
- **Hardware-bound device binding** — `DeviceBinding` derives a per-install ID
  from the Android Keystore; the server rejects credentials from unbound devices
  when device binding is enabled for the tenant.
- **Deep-link allow-list** — `DeepLinkAllowlist` validates every inbound
  `bizarrecrm://` URI against a static whitelist; unknown routes are silently dropped.
- **Network pinning** — `network_security_config.xml` pins the tenant server cert;
  cleartext is forbidden on all API levels.

---

## T — Tampering (Integrity)

**Threats**
- A rooted device modifies SharedPreferences to inject a different server URL
  and redirect traffic.
- An attacker with adb access modifies the SQLite database to elevate privileges.
- Request payloads are intercepted and modified in transit.

**Countermeasures**
- **HMAC-protected server URL** — `AuthPreferences.setServerUrl` computes an
  HMAC-SHA256 over the URL using a per-install Keystore-backed secret.  The network
  layer calls `verifyServerUrlSignature` before every request; tampering fails closed.
- **SQLCipher** — the Room database is encrypted with a 32-byte random passphrase
  stored in the Android Keystore via `DatabasePassphrase`.  Direct file modification
  produces only gibberish.
- **HTTPS + certificate pinning** — all API traffic is TLS 1.3 with a pinned leaf
  cert.  Modified payloads in transit break the TLS MAC and are rejected.
- **Signed image URLs** — photo URLs include a server-generated signature; expired
  or tampered URLs return 403.
- **Envelope encryption** — sensitive payloads (backup archives) are AES-GCM
  encrypted before leaving the device.

---

## R — Repudiation (Non-repudiation)

**Threats**
- A privileged user performs a destructive action (bulk delete, refund) and later
  denies it.
- An attacker replays a legitimate action to cause duplicate effects.

**Countermeasures**
- **Server audit log** — every state-changing API call is logged server-side with
  the authenticated user's ID, timestamp, IP address, and request body hash.  Logs
  are append-only and tamper-evident via chained hashes.
- **Play Integrity attestation** — high-value actions (refund > $500) trigger a
  `PlayIntegrityClient.requestToken` call; the token is forwarded to `IntegrityApi`
  and included in the server audit entry, binding the action to a verified device.
- **Idempotency keys** — POS and sync endpoints accept a client-generated
  idempotency key to prevent duplicate submissions.

---

## I — Information Disclosure

**Threats**
- A stolen device exposes customer PII (names, phones, emails, device repair history)
  from the screen or the database file.
- A backup restore on a different device exposes auth tokens.
- Log files leak sensitive field values.

**Countermeasures**
- **Android Keystore** — all cryptographic keys (DB passphrase, EncryptedSharedPrefs
  master key, Coil cache key) are hardware-backed via the Keystore.  Keys cannot be
  exported.
- **SQLCipher** — Room DB is AES-256-GCM encrypted at rest.
- **Biometric gate** — `BiometricAuth` requires BIOMETRIC_STRONG or DEVICE_CREDENTIAL
  before the Compose scaffold renders.  The inactivity timeout re-engages the gate
  after configurable idle periods (`SessionTimeout`).
- **FLAG_SECURE** — `WindowManager.FLAG_SECURE` prevents screenshots and Recents
  thumbnails.  `setRecentsScreenshotEnabled(false)` is applied on API 31+ as a
  belt-and-suspenders measure.
- **Lock-screen blur** — `LockScreenBlurHelper` applies a 25 px Gaussian
  `RenderEffect` to the root view on API 31+ when the app moves to the background,
  preventing Recents peek at PII.
- **Encrypted Coil cache** — `EncryptedCoilCache` stores thumbnail files in
  `noBackupFilesDir` (excluded from Auto-Backup) and provides `EncryptedFile`
  helpers for file-level AES-GCM protection.
- **Log redaction** — `RedactorTree` + `LogRedactor` strip tokens, emails, phones,
  and IMEI values from all Timber log calls before they reach Logcat.
- **Clipboard seal** — `ClipboardUtil.clearSensitiveIfPresent` clears any
  CRM-owned clipboard content when the app backgrounds (marker-based detection;
  user-copied text is never touched).
- **EXIF stripping** — `ExifStripper` removes location, device, and timestamp
  metadata from photos before upload.

---

## D — Denial of Service

**Threats**
- A script repeatedly hits auth endpoints to lock out users or exhaust server
  resources.
- A malicious WiFi network creates a captive portal that returns garbage responses
  causing the app to spin forever.
- A rogue tenant floods the WebSocket to starve other tenants.

**Countermeasures**
- **Server-side rate limiting** — all auth endpoints enforce per-IP and per-user
  rate limits with exponential back-off.  429 responses carry `Retry-After` headers
  that the Retrofit client honours.
- **Client-side rate limiter** — `RateLimiter` enforces per-bucket token budgets on
  the Android side; UI actions that exceed their budget are silently dropped.
- **Circuit breaker** — `ServerReachabilityMonitor` switches the app to offline mode
  after three consecutive 5xx responses or timeouts, preventing retry storms.
- **OkHttp timeout** — connect / read / write timeouts are set to 30 s; runaway
  requests are cancelled automatically.
- **WorkManager back-off** — `SyncWorker` uses exponential back-off so a misbehaving
  server does not cause a tight retry loop.

---

## E — Elevation of Privilege

**Threats**
- A low-privilege technician role attempts to access admin-only endpoints directly.
- A malicious app on the same device abuses exported components to obtain a CRM
  session.
- A compromised WebSocket message tricks the app into executing a privileged action.

**Countermeasures**
- **Server-authoritative RBAC** — every API endpoint checks the JWT's `role` claim
  server-side.  The Android client also performs a double-check on role-gated UI
  (technician vs. admin navigation) but this is defence-in-depth only; the server
  is the authority.
- **Minimal component exports** — only `MainActivity`, `QuickTicketTileService`,
  `DashboardWidgetProvider`, and `SmsOtpBroadcastReceiver` are exported.
  `SmsOtpBroadcastReceiver` is protected by the `com.google.android.gms.auth.api.phone.permission.SEND`
  system permission so only Play Services can deliver its intent.
- **Deep-link allow-list** — external callers can only navigate to a static set of
  whitelisted routes; they cannot reach admin screens or trigger mutations.
- **WebSocket message validation** — `WebSocketEventHandler` validates the `type`
  field against an allow-list of known event types; unknown types are discarded with
  a warning log.
- **Play Integrity** — `PlayIntegrityClient` verifies the device environment on
  auth success and high-value actions; a MEETS_BASIC_INTEGRITY failure raises an
  alert (or blocks the action if `strict: true` in tenant policy).
- **StrictMode (debug)** — `StrictModeInit` enables all VM and thread policy checks
  in debug builds, surfacing potential privilege escalation vectors (file descriptor
  leaks, untagged sockets) during development.
