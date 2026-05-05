# BizarreCRM iOS — STRIDE Threat Model

**Scope:** BizarreCRM iOS client (Swift 6.0, iOS 17+). Staff-facing only; no customer-facing binary.
**Date:** 2026-04-20
**Owner:** iOS Lead + Security Reviewer
**Review cadence:** Quarterly + post-incident

---

## 1. Architecture Summary

| Layer | Technology | Security boundary |
|---|---|---|
| Auth | JWT (1h access / 30d refresh), TOTP 2FA, passkey (WebAuthn) | Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Transport | HTTPS/TLS + optional SPKI pinning (`PinnedURLSessionDelegate`) | ATS enforced; bare `URLSession` banned outside `Core/Networking/` |
| Persistence | GRDB + SQLCipher; 32-byte random passphrase per tenant in Keychain | Full DB encrypted at rest; backup-proof |
| Sync | `sync_queue` table with idempotency keys; drain loop | Tamper-evident queue; dead-letter on repeated failure |
| Logging | `AppLog` + `LogRedactor`; `OSLog` `.private` on PII | No PII in crash logs or server telemetry |
| RBAC | Server-authoritative; client enforces display-only | Role checked on every write; `/auth/elevate` gated |
| Audit | §50 SHA-chained server-side audit log | Immutable; repudiation impossible for captured events |

---

## 2. STRIDE Threat Table

Each row: **threat** | **asset at risk** | **attack vector** | **current mitigation** | **residual risk** | **action required**

---

### S — Spoofing

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| S1 | JWT forgery | Staff session | Attacker creates valid-looking JWT with elevated role | Short-lived tokens (1h); server-side signature verification; refresh rotation | Low — server rejects unsigned tokens | No |
| S2 | Session hijack via token theft | Access / refresh tokens | Token extracted from memory, logs, or unencrypted storage | Tokens in Keychain only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); `OSLog` `.private` on token values; `LogRedactor` strips tokens from telemetry | Medium — AFU window: live unlocked device exposes Keychain to our process | Enforce biometric re-auth on high-value actions (§28.10) |
| S3 | Shared-device impersonation | Active staff session | Staff member A walks away; Staff member B uses open session | PIN quick-switch (§2); session timeout (§19.2 / §28.14); shared-device mode with per-user PIN | Medium — session timeout not yet wired on all screens | **YES** — verify session timeout enforced globally; confirm shared-device mode locks after inactivity |
| S4 | Passkey / WebAuthn replay | Passkey credential | Attacker captures WebAuthn assertion and replays it | WebAuthn replay protection is protocol-level (nonce + challenge); `Auth/Passkey.swift` + `Auth/Passkey/Hardware.swift` | Low — replay rejected by server challenge | No |
| S5 | Magic-link interception | One-time login link | Link intercepted via SMS or email compromise | Short expiry (~15 min); single-use server-side; deep-link host locked to `app.bizarrecrm.com` | Medium — email/SMS channel outside our control | **YES** — verify magic-link expiry enforced server-side; document in runbook |
| S6 | Push phishing (fake APNs) | Deep-link navigation | Malicious push with `deepLink` payload navigates to sensitive action | All push payloads validated against `DeepLinkRouter` allowlist; no auto-action without user tap; APNs trust chain intact | Low | No |

---

### T — Tampering

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| T1 | DB tampering at rest | GRDB (customer PII, financial records) | Attacker extracts app container from backup; edits SQLite file | SQLCipher AES-256 with Keychain-held passphrase; key not in backup | Very Low — backup copy unreadable without Keychain key | No |
| T2 | SQLCipher passphrase exposure | DB encryption key | Keychain item exfiltration | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `ThisDeviceOnly` (not migratable); App Attest device binding (§28.11) | Low — mitigated by device binding | No |
| T3 | In-transit tampering (MITM) | API responses / requests | Attacker on local network modifies JSON in transit | HTTPS enforced by ATS; optional SPKI pinning (`PinnedURLSessionDelegate`) — empty pin set by default | Medium — SPKI pinning optional; pin set empty at install time | **YES** — populate default SPKI pin for `bizarrecrm.com`; document rotation in runbook |
| T4 | sync_queue row tampering | Pending write operations | Attacker with local file access modifies queued payloads before drain | `sync_queue` rows inside SQLCipher DB; idempotency key prevents replay | Low — queue inside encrypted DB | No |
| T5 | API response tampering | Envelope data | Malicious server or proxy injects unexpected `data` shape | Envelope `{ success, data, message }` strictly decoded; unexpected fields ignored; `.decode()` errors surface as `AppError` | Low | No |
| T6 | Binary tampering / code injection | App runtime | Attacker injects dylib on jailbroken device | Heuristic jailbreak detection (§28.11); App Attest (DeviceCheck); sealed by Apple code signing | Medium — jailbreak detection can be bypassed; App Attest optional | **YES** — enable App Attest by default; document attestation failure handling |

---

### R — Repudiation

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| R1 | Staff denies performing a high-value action | Audit integrity | Staff claims "I didn't do that" | §50 SHA-chained server audit log; each entry includes actor + action + timestamp + hash of prior entry; immutable once written | Low — chain verifiable | No |
| R2 | Operator action repudiation | Manager-PIN-gated operations (void, refund, delete) | Manager claims PIN was used without consent | Biometric gate + manager PIN required; audit entry includes actor user ID, not just role | Low | No |
| R3 | POS sale provenance disputed | Transaction ledger | "I never sold that" | BlockChyp generates payment record; iOS appends `sync_queue` record with device ID + timestamp + actor; server ledger immutable | Low | No |
| R4 | Refund accountability | Refund records | Unauthorized refund denied after the fact | Refund requires manager PIN + biometric; audit entry with original transaction ref | Low | No |
| R5 | Screenshot of audit export repudiated | Exported audit bundle | Staff exports audit, then denies receiving it | Screenshot detection (`UIApplication.userDidTakeScreenshotNotification`) writes audit entry with user + screen + UTC; export action itself logged | Low | No |

---

### I — Information Disclosure

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| I1 | Token in logs | Access/refresh tokens | Developer adds a log line that includes a token | `LogRedactor` scrubs token-shaped strings; `OSLog` `.private` on all dynamic params enforced by SwiftLint rule | Low — lint + runtime redaction | No |
| I2 | PII in crash reports | Customer names, emails, phones | Exception thrown while processing customer data; stack frame includes string value | `LogRedactor` strips PII from telemetry bundles; crash logs route only to Apple (device-level opt-in) — no third-party crash SaaS | Low | No |
| I3 | Photo EXIF data disclosure | Location in EXIF, device model | Photo attached to ticket uploaded with full EXIF | EXIF stripping required before upload; iOS `PHAsset` + `ImageIO` strip; TODO: enforce stripping in Camera package | **High** — stripping not yet verified enforced | **YES** — verify EXIF strip in `Camera/DocScan`, `Camera/Annotation`; add unit test asserting no GPS tag in uploaded image |
| I4 | PII in URL query params | Customer ID, ticket ID in API URL | Server logs or proxy logs capture URL | IDs use opaque server-assigned integers; no PII (name, email) in query string; `APIClient` builds paths without embedding raw PII | Low | No |
| I5 | Screen recording / mirroring | Payment details, 2FA codes | User screen-records during payment | `UIScreen.capturedDidChangeNotification` swaps sensitive views for blur placeholder while `isCaptured == true`; `isSecure` flag on PIN/OTP fields | Medium — blur logic not yet implemented on all sensitive screens | **YES** — audit all screens in `Pos/`, `Auth/`, `Settings/Audit/` for `isCaptured` handler |
| I6 | App Switcher snapshot | Visible screen content | iOS snapshots screen when app backgrounds | Privacy snapshot (blur overlay on `willResignActive`) always on | Low | No |
| I7 | Clipboard sniffing | Copied customer data | Background app reads `UIPasteboard.general.string` | `PasteButton` (iOS 16+) for user-initiated paste; no background pasteboard reads in code; SwiftLint rule enforced | Low | No |
| I8 | SMS / dictation transcription | Customer PII in dictated text | iOS dictation sends audio to Apple servers | Text fields with PII use `.autocorrectionDisabled(true)`; dictation not explicitly blocked (iOS doesn't allow blocking) | Low — acceptable residual | No |
| I9 | iCloud Backup DB exposure | Full GRDB database | iCloud backup captured; extracted by third party | SQLCipher encryption; Keychain key not in backup | Low | No |
| I10 | Telemetry egress to third party | Usage events, crash data | Third-party analytics SDK exfiltrates data | SDK-ban lint (`sdk-ban.sh`) blocks Sentry/Firebase/Mixpanel/Amplitude/New Relic/Datadog imports at CI; single egress = `APIClient.baseURL` | Low | No |

---

### D — Denial of Service

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| D1 | Endpoint flooding | Server + app session | Attacker sends rapid API requests from compromised client | Client `RateLimiter` (`Networking/RateLimiter.swift`) caps request rate; server-side rate limiting independent | Low | No |
| D2 | OOM from large attachments | App stability | User opens a ticket with hundreds of 50 MB attachments | Tiered Nuke image cache (memory 80 MB / disk 2 GB default); LRU eviction; low-disk guard pauses writes at < 2 GB free | Medium — memory pressure during rapid scroll not stress-tested | **YES** — add memory pressure test in `Tests/Performance/` for 1000-row list with images |
| D3 | Infinite retry loop | Sync queue + battery | Bug causes sync item to retry without backoff | Dead-letter queue after `maxAttempts`; exponential backoff via `next_retry_at`; dead-letter viewer (§20) for manual inspection | Low | No |
| D4 | Terminal spam from BlockChyp | Payment terminal CPU | Terminal firmware loop sends rapid status updates | Terminal comms wrapped in `Hardware/Terminal/`; connection timeouts enforced; debounce on status handler | Low | No |
| D5 | sync_queue deadlock | All pending writes | Two drain loops run concurrently | `SyncFlusher` uses Swift actor serialization; single-consumer drain | Low | No |
| D6 | WebSocket reconnect storm | Network + battery | WS drops; client reconnects immediately in loop | Starscream reconnect uses exponential backoff; max-reconnect-attempts cap | Low | No |

---

### E — Elevation of Privilege

| # | Threat | Asset | Attack Vector | Current Mitigation | Residual Risk | Action Required |
|---|---|---|---|---|---|---|
| E1 | Role escalation via `/auth/elevate` | Admin capabilities | Regular user calls `/auth/elevate` with forged request | Server validates current role and re-authenticates (biometric + credentials) before issuing elevated token; token scoped + short-lived | Low — server authoritative | No |
| E2 | Manager-PIN bypass | Gated operations (void, refund, override) | User guesses or brute-forces 4-digit PIN | `LAContext` biometric gate before PIN entry; lockout after 3 fails; audit entry on each attempt | Medium — PIN brute-force possible if biometric skipped | **YES** — enforce biometric-first on all manager-PIN screens; add lockout test |
| E3 | Debug-flag forcing | Staging code paths in release | Attacker sets feature flag to enable debug UI in release build | `#if DEBUG` compile-time guard on all debug-only code paths; feature flags server-controlled; release scheme has no `DEBUG` compile flag | Low | No |
| E4 | Jailbreak detection gap | OS sandbox | Jailbroken device bypasses sandbox checks | Heuristic file-presence + sandbox-escape check (§28.11); App Attest (DeviceCheck); flag is informational (log + optional block) | Medium — heuristics bypassable | **YES** — enable App Attest mandatory check; document fail-open vs fail-closed policy |
| E5 | RBAC client-side bypass | Role-gated UI | User modifies in-memory role object via debugger | Server re-validates role on every write endpoint; client role is display-only; no privilege decision made client-only | Low | No |
| E6 | Tenant data cross-contamination | Other tenant's DB | Login to tenant B accidentally decrypts tenant A data | Per-tenant passphrase; Keychain item keyed by `tenant_slug`; full-wipe on tenant switch | Low | No |

---

## 3. Top 10 Residual Risks (Severity Ranked)

| Rank | ID | Category | Description | Severity | Owner | Mitigation Action |
|---|---|---|---|---|---|---|
| 1 | I3 | Information | EXIF stripping not verified in upload paths | High | Camera package owner | Strip EXIF in Camera upload path; add unit test |
| 2 | S3 | Spoofing | Session timeout not enforced on all screens | Medium-High | Auth package owner | Wire `SessionTimer` globally; test shared-device lock |
| 3 | I5 | Disclosure | `isCaptured` blur not on all sensitive screens | Medium | Per-feature owners | Audit Pos/, Auth/, Settings/Audit/ for capture guard |
| 4 | T3 | Tampering | SPKI pinning empty by default | Medium | Networking / Release agent | Populate default pin for bizarrecrm.com |
| 5 | T6 | Tampering | App Attest optional; jailbreak detection weak | Medium | Core / Release agent | Enable App Attest by default |
| 6 | E2 | Escalation | Manager-PIN brute-force if biometric skipped | Medium | Auth / POS owner | Enforce biometric-first; add lockout |
| 7 | E4 | Escalation | Jailbreak heuristics bypassable | Medium | Core / Release agent | App Attest mandatory; document fail policy |
| 8 | S2 | Spoofing | AFU window: Keychain readable on live unlocked device | Medium | Auth / all screen owners | Biometric re-auth before all high-value actions |
| 9 | D2 | DoS | OOM under large-attachment load not stress-tested | Medium | Performance / Camera | Add OOM perf test; verify eviction under pressure |
| 10 | S5 | Spoofing | Magic-link server-side expiry unverified | Medium | Auth + Server team | Confirm expiry enforced server-side; add integration test |

---

## 4. Mitigations In Place (Evidence)

| Mitigation | Evidence file / commit |
|---|---|
| Keychain secrets only | `Packages/Auth/Sources/Auth/KeychainStore.swift` (TBD) |
| SQLCipher at-rest encryption | `Packages/Persistence/` migrations; §28.2 |
| ATS enforced | `ios/App/Resources/Info.plist` — no `NSAllowsArbitraryLoads` |
| SPKI pin infrastructure | `PinnedURLSessionDelegate` scaffold (empty pin set) |
| Client rate limiter | `Networking/RateLimiter.swift` |
| SDK-ban CI lint | `ios/scripts/sdk-ban.sh` + `.github/workflows/ios-lint.yml` |
| LogRedactor | `Core/Logging/AppLog.swift`, `LogRedactorTests` (19 tests green) |
| sync_queue idempotency | `Persistence/SyncQueueStore.swift`; SmokeTests 7 cases green |
| App Switcher blur | `willResignActive` privacy snapshot overlay (§28.8) |
| EXIF / photo privacy | **Pending** (Camera package) |
| Screen-capture blur | **Pending** (per-feature) |
| App Attest / jailbreak | **Partial** — heuristic detection only |

---

## 5. Out-of-Scope Threats

- Server-side vulnerabilities — outside iOS client scope; tracked in server runbooks.
- Third-party hardware firmware (BlockChyp, printers) — vendor responsibility.
- Apple OS vulnerabilities — mitigated by staying on latest iOS floor (17+).
- Physical seizure by nation-state with forensic tools — accepted residual; SQLCipher + App Attest is reasonable commercial defense.

---

## 6. Review Sign-off

| Role | Sign-off |
|---|---|
| iOS Lead | [ ] |
| Security Reviewer | [ ] |
| Release Agent | [ ] |
| Date | YYYY-MM-DD |

---

*Actions exported to [`docs/security/threat-model-actions.md`](./threat-model-actions.md).*
