# STRIDE Threat Model — Action Items

Generated from [`docs/security/threat-model.md`](./threat-model.md).
All items are **residual-risk mitigations** — existing controls partially address the threat; these close the gap.

---

## Critical / High

- [ ] **I3 — EXIF stripping**
  Verify GPS + device EXIF tags are stripped before upload in `Camera/DocScan`, `Camera/Annotation`, and the general photo picker path. Add a unit test asserting no `kCGImagePropertyGPSDictionary` key in the uploaded image metadata.
  **Owner:** Camera package owner
  **Priority:** High — PII leakage

---

## Medium

- [ ] **S3 — Session timeout global enforcement**
  Wire `Auth/SessionTimer.swift` so idle timeout fires on every screen, including background-to-foreground transitions. Confirm `SharedDevice` mode locks after configured inactivity period. Add XCUITest for shared-device auto-lock.
  **Owner:** Auth package owner

- [ ] **I5 — Screen-capture blur on all sensitive screens**
  Audit every screen under `Packages/Pos/`, `Packages/Auth/`, `Settings/Audit/` for `UIScreen.capturedDidChangeNotification` handler + blur-placeholder swap while `isCaptured == true`. Document which screens are gated; add snapshot tests for captured state.
  **Owner:** Per-feature owners (Pos, Auth, Settings)

- [ ] **T3 — Populate SPKI pin for bizarrecrm.com**
  Generate SPKI hash for the active Let's Encrypt cert on `bizarrecrm.com`. Configure `PinnedURLSessionDelegate` default pin set in `Networking/NetworkConfig.swift` (or equivalent). Document pin rotation procedure in `docs/runbooks/cert-rotation.md` with 30-day overlap window.
  **Owner:** Networking agent + DevOps

- [ ] **T6 / E4 — App Attest mandatory**
  Enable App Attest (`DCAppAttestService`) by default in release builds. Define fail-open vs fail-closed policy for devices where attestation is unavailable (older devices, simulators). Document in `docs/runbooks/app-attest.md`.
  **Owner:** Core / Release agent

- [ ] **E2 — Manager-PIN biometric-first enforcement**
  Ensure `LAContext` biometric prompt precedes manager-PIN entry on all gated flows (void, refund, role-elevate, delete customer). Add lockout (3 attempts → require full re-auth) with audit entry. Add unit test for lockout state machine.
  **Owner:** Auth + POS owner

- [ ] **S2 — Biometric re-auth on high-value actions**
  Audit all screens in `Packages/Invoices/Payment/`, `Packages/Pos/Refunds/`, `Settings/TenantAdmin/` for `LAContext` re-auth gate. The 10-second reuse window (§28.10) is acceptable; document the threshold.
  **Owner:** Per-feature owners

- [ ] **D2 — OOM stress test under large-attachment load**
  Add a performance test in `Tests/Performance/` that loads a 1000-row ticket list with 5 images per row and asserts peak memory stays below 220 MB (§29.6 budget). Test on iPhone SE 3 simulator.
  **Owner:** Performance / Camera

- [ ] **S5 — Magic-link expiry server-side verification**
  Confirm `/auth/magic-link/verify` server route enforces single-use + ≤15-minute TTL. Add integration test in `ios/Tests/` or server test suite. Document in `docs/runbooks/magic-link.md`.
  **Owner:** Auth package owner + Server team

---

## Low / Informational (track, no immediate action)

- [ ] **S6 — Deep-link allowlist review** — Confirm `DeepLinkRouter` rejects unknown path prefixes; add fuzz test for malformed deep links.
- [ ] **R5 — Screenshot audit entries** — Confirm `userDidTakeScreenshotNotification` observer is registered globally and writes to audit log on all screens classified as sensitive.
- [ ] **I10 — SDK-ban lint coverage** — Confirm `sdk-ban.sh` covers all known analytics / crash-SaaS SDKs; update list on each dependency audit cycle.

---

## Completed (archive when signed-off)

*(Move items here with commit SHA when PR merges.)*

---

*Last updated: 2026-04-20*
*Source: `docs/security/threat-model.md` §3 Top 10 + §2 rows marked Action Required = YES*
