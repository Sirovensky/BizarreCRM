# ios/agent-ownership.md — Agent assignment & dependency map

Execution layer on top of `ios/ActionPlan.md`. Tells each sub-agent:
- which phase their section lives in
- what must exist before they start
- which files they own and which are off-limits
- what "done" looks like

**ActionPlan.md = spec (what to build).**
**This file = execution map (how work splits).**

---

## How to use

1. Pick a section ID from `ios/ActionPlan.md` (e.g. `§4 Tickets`).
2. Find it in the **Section assignment tables** below.
3. Confirm every prerequisite has `status: done`.
4. Claim only the files listed under **Owns**. Treat everything else as read-only.
5. Open a PR titled `[§N] <section title>`. Small commits > big commits.
6. CI runs the phase gate for the section; merge blocks until green.

## Merged sections (do not pick — content consolidated)

| Deprecated § | See instead |
|---|---|
| §19 Rollout Strategy | §82 |
| §62 Customer-facing app | (out of scope) |
| §66 Haptic custom patterns | §66 |
| §80 Color token system | §80 |
| §80 Typography scale | §80 |
| §45 Staff chat deep | §45 |
| §47 Role matrix deep | §47 |
| §50 Audit log viewer deep | §50 |
| §37 Referral tracking deep | §37 |
| §33 Apple Watch complications | §73 |

Deprecated numbers kept in ActionPlan as pointer stubs so link integrity holds.

---

## Independence rules (hard constraints)

1. **No cross-section edits.** Agent for §4 Tickets does not touch `Packages/Customers/`. If the section needs a new public API on another module, open a sibling PR tagged `[core]` first and wait for merge.
2. **ActionPlan.md is append-only during execution.** Only flip `[ ]` → `[x]` with commit SHA. No re-scoping. Scope changes require human review.
3. **Design tokens only.** Never inline hex, point values, radii, durations. Always `DesignSystem/Tokens.swift` (per §80).
4. **API envelope sacred.** `{ success, data, message }` single unwrap. No branching envelope shapes (per §1.3).
5. **Data sovereignty.** Single network peer = `APIClient.baseURL`. No third-party SDK egress (per §32 / §1 principle).
6. **iPad distinct.** Every screen needs a `Platform.isCompact` branch. Snapshot tests must cover both variants (per §22).
7. **Liquid Glass on chrome only.** Never on content. Never stacked. ≤ 6 visible (per §30, §30).
8. **Tests co-located.** Unit + snapshot tests live in the owning package's `Tests/` directory. 80% coverage gate per PR (per §31).
9. **Accessibility baked in, not bolted on.** Every `Button` / `Text` / icon gets `.accessibilityLabel` at commit time. Final audit in Phase 10 is only verification, not retrofit.
10. **Keychain for secrets.** Never UserDefaults for tokens, passphrases, PINs.
11. **No orphan UI.** Every view wired to a real ViewModel → Repository → API/DB call before PR opens (per CLAUDE.md).

---

## File ownership zones

### Exclusive (single-agent edits)
| Zone | Owner principle |
|---|---|
| `Packages/<Feature>/` | Section owner assigned to that feature only |
| `App/Resources/Locales/<lang>.lproj/` | Localization team (§64) |
| `ios/scripts/` | Tooling agent only |
| `project.yml` | Tooling agent only |
| `fastlane/` | Release agent only |

### Shared additive (many agents append; no one edits existing lines)
| File | Additive rule |
|---|---|
| `Packages/DesignSystem/Sources/DesignSystem/Tokens.swift` | Add new tokens at bottom of relevant enum; never rename / delete |
| `Packages/Networking/Sources/Networking/APIClient+*.swift` | One file per domain (`APIClient+Tickets.swift`). Never edit another domain's file |
| `App/DeepLinkRouter.swift` | Add routes via `DeepLinkRouter.register(path:handler:)` calls from feature module init |
| `Packages/Core/Sources/Core/FeatureFlag.swift` | Add cases; never reorder |

### Advisory-lock required (edits, not just appends)
| File | Lock via |
|---|---|
| `App/BizarreCRMApp.swift` | GitHub comment "Claiming BizarreCRMApp.swift for §N" before push |
| `App/RootView.swift` | Same |
| `App/AppServices.swift` | Same |
| `Packages/Core/Sources/Core/Container+Registrations.swift` | Same |

### Off-limits (read-only for everyone except designated owner)
- `ActionPlan.md` — append to Changelog only; no content edits without human review
- `CLAUDE.md` — human edit only
- `TODO.md` — owner flips `[x]` after commit; no other edits

---

## Phase gates

| Phase | Goal | Parallel? | Gate to next phase |
|---|---|---|---|
| 0 — Foundation | Project gen, DI, DB, tokens, APIClient skeleton, **offline cache + sync queue + cursor pagination (§20)**. Preceded by §74 Server API gap audit (document filed, missing endpoints ticketed + shimmed). | No (serial) | §74 audit document attached; lint green; empty app launches on iPhone / iPad / Mac; airplane-mode smoke passes (read from empty cache, queue a write, drain on reconnect); lint blocks direct APIClient calls outside repositories |
| 1 — Auth & shell | Login, sessions, scene setup | No | Login → empty dashboard; sign-out broadcast works |
| 2 — Sync integrations + polish | POS offline queue, per-domain error recovery | No | Conflict path exercised in at least one domain |
| 3 — Read surfaces | 10 list+detail screens | **Yes** | All lists render from cache; pull-to-refresh round-trips |
| 4 — Write flows | CRUD per entity | **Yes** | Every entity create/edit/delete works online + offline |
| 5 — POS & hardware | Cart, BlockChyp, printer, scanner, drawer, CFD | Partly | Cash + card sale produces receipt; drawer kicks |
| 6 — Platform integrations | Push, widgets, Intents, Wallet, public pages | **Yes** | Push tap → correct screen; widget shows live data |
| 7 — iPad polish | 3-col splits, Pencil, keyboard shortcuts | **Yes** | iPad distinct from iPhone on every listed screen |
| 8 — Reports / loyalty / marketing | Charts, memberships, campaigns | **Yes** | Revenue chart + membership enrol round-trips |
| 9 — Settings / admin | Roles, audit, import/export | **Yes** | Settings search finds every setting; audit immutable |
| 10 — A11y / perf / i18n | Audit, tune, localize | **Yes** | A11y CI clean; p95 budgets met; pseudo-loc passes |
| 11 — Security / release | STRIDE, privacy manifest, TestFlight, App Store | No | Submission accepted; phased rollout armed |

Gate check = CI signal. Human approves phase transition before next phase agents start.

---

## Pre-Phase-0 gate — Server API gap audit (§74)

Runs **before** Phase 0 kicks off. One engineer walks the §74.1 endpoint matrix against `packages/server/src/routes/`, marks each as `exists` / `partial` / `missing`, and files root-TODO tickets for every gap. Phase 0 is allowed to start even with some `missing` entries — §74.3 local shim handles those — but the audit document must exist and be linked from Phase 0's kickoff issue. Re-audit quarterly.

Output: single GitHub issue + corresponding `TODO.md` entries for missing endpoints. Not a coding task; no package owns it.

---

## Section assignment tables

Legend: **§** = section in ActionPlan.md · **Pkg** = owning SwiftPM package · **Deps** = prerequisite sections · **Parallel-with** = sibling sections safe to run concurrently.

### Phase 0 — Foundation (serial)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 1 | Platform & foundation | `Core`, `App` | — | `Packages/Core/Sources/Core/Platform.swift`, `project.yml`, `scripts/write-info-plist.sh`, `scripts/gen.sh`, `scripts/fetch-fonts.sh` |
| 30 | Design system | `DesignSystem` | §1 | `Packages/DesignSystem/Sources/**`, glass primitives, motion tokens |
| 80 | Master token table | `DesignSystem` | §30 | `Tokens.swift` (exclusive) |
| 78 | Data model / ERD | `Core` | §1 | `Core/Models/*.swift` |
| 78 | SwiftData vs GRDB decision | `Persistence` | §78 | `Packages/Persistence/Sources/**` |
| 1 | DB migration strategy | `Persistence` | §78 | `Persistence/Migrations/*` |
| 1 | DI architecture | `Core` | §1 | `Container.swift`, `Container+Registrations.swift` |
| 1 | APIClient internals | `Networking` | §1 | `Packages/Networking/Sources/Networking/APIClient.swift` (base only) |
| 63 | Error taxonomy | `Core` | §1 | `Core/Errors/AppError.swift` |
| 32 | Logging strategy | `Core` | §1 | `Core/Logging/Logger.swift` |
| 33 | Build flavors | `App` / tooling | §1 | `Configs/*.xcconfig`, schemes |
| 33 | Certs / provisioning | `App` / tooling | §33 | `fastlane/Matchfile`, `Fastfile` |
| 20 | Offline, Sync & Caching (foundation) | `Sync` + `Persistence` | §1, §1, §78, §78 | `Packages/Sync/Sources/**`, `Packages/Persistence/Sources/**` repo protocols + sync_queue + sync_state + drain loop |
| 20 | Offline-first viewer UX primitives | `Sync` | §20 | `Sync/OfflineBanner.swift`, `Sync/StalenessIndicator.swift` |
| 20 | Dead-letter queue viewer | `Sync` | §20 | `Sync/DeadLetter/**` |
| 63 | Draft recovery framework | `Core` | §20 | `Core/Drafts/**` |
| 1 | Backup & restore | `Persistence` | Phase 0 | `Persistence/Backup/**` |
| 1 | Client rate-limiter | `Networking` | §1 | `Networking/RateLimiter.swift` |

**Phase 0 gate:** `bash ios/scripts/gen.sh` + `xcodebuild` produce launchable empty app on sim for iPhone / iPad / Mac. Additionally: sync_queue + sync_state schema migrations run; airplane-mode smoke test boots app, reads the empty cache, shows offline banner, queues a synthetic write, drains on reconnect; CI lint blocks any `APIClient.{get,post,patch,put,delete}` call outside a `*Repository` file and any bare `URLSession` outside `Core/Networking/`.

---

### Phase 1 — Auth & shell (serial after Phase 0)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 2 | Auth / Login | `Auth` | Phase 0 | `Packages/Auth/Sources/Auth/**`, `App/SessionBootstrapper.swift` |
| 1 | App lifecycle | `App` | §2 | `App/BizarreCRMApp.swift`, `App/AppState.swift` |
| 2 | Session timeout | `Auth` | §2 | `Auth/SessionTimer.swift` |
| 2 | Remember-me | `Auth` | §2 | `Auth/CredentialStore.swift` |
| 2 | 2FA enrollment | `Auth` | §2 | `Auth/TwoFactor/**` |
| 2 | 2FA recovery codes | `Auth` | §2 | `Auth/TwoFactor/RecoveryCodes.swift` |
| 2 | SSO / SAML | `Auth` | §2 | `Auth/SSO/**` |
| 79 | Multi-tenant session mgmt | `Auth` | §2 | `Auth/TenantSwitcher.swift` |
| 2 | Shared-device mode | `Auth` | §2 | `Auth/SharedDevice/**` |
| 2 | PIN quick-switch | `Auth` | §2 | `Auth/PIN/**` |
| 2 | Magic-link login | `Auth` | §2 | `Auth/MagicLink.swift` |
| 2 | Passkey login | `Auth` | §2 | `Auth/Passkey.swift` |
| 2 | WebAuthn on iPad | `Auth` | §2 | `Auth/Passkey/Hardware.swift` |
| 65 | URL-scheme handler | `App` | §2 | `App/DeepLinkRouter.swift` |

**Phase 1 gate:** Login → empty authenticated dashboard. Sign-out returns to login. 2FA prompts when enabled.

---

### Phase 2 — Sync integrations + domain polish (serial after Phase 1)

§20 foundation moved up to Phase 0. This phase now covers domain-level wiring and integrations that extend that foundation.

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 16 | POS offline queue (domain-scoped) | `Sync` / `Pos` | §20 | shared; see Phase 5 |
| 63 ext | Error recovery patterns per domain | feature modules | §63 | each feature adds per-screen recovery |

**Phase 2 gate:** Every domain module added in Phase 3 uses the §20 repository pattern; airplane-mode walk-through of each read surface and each write flow passes; conflict path exercised for at least one ticket + one inventory + one invoice edit.

---

### Phase 3 — Read surfaces (parallel)

Each row is an independent agent. Zero cross-dependencies between rows except all depend on Phases 0-2.

| § | Title | Pkg | Owns | Parallel-with |
|---|---|---|---|---|
| 3 | Dashboard | `Dashboard` | `Packages/Dashboard/Sources/**` | §4-§18 |
| 4 | Tickets list + detail (read) | `Tickets` | `Packages/Tickets/Sources/**` | §3, §5-§18 |
| 5 | Customers list + detail (read) | `Customers` | `Packages/Customers/Sources/**` | §3, §4, §6-§18 |
| 6 | Inventory list + detail (read) | `Inventory` | `Packages/Inventory/Sources/**` | others |
| 7 | Invoices list + detail (read) | `Invoices` | `Packages/Invoices/Sources/**` | others |
| 8 | Estimates list + detail | `Estimates` | `Packages/Estimates/Sources/**` | others |
| 9 | Leads list | `Customers` | `Packages/Customers/Sources/Leads/**` | others |
| 10 | Appointments list | `Appointments` | `Packages/Appointments/Sources/**` | others |
| 11 | Expenses list | `Expenses` | `Packages/Expenses/Sources/**` | others |
| 12 | SMS threads + messages (read) | `Communications` | `Packages/Communications/Sources/**` | others |
| 13 | Notifications list | `Notifications` | `Packages/Notifications/Sources/**` | others |
| 14 | Employees list | `Employees` | `Packages/Employees/Sources/**` | others |
| 15 | Reports stubs | `Reports` | `Packages/Reports/Sources/**` (read placeholders; full charts in Phase 8) | others |
| 18 | Global search | `Search` | `Packages/Search/Sources/**` | others |
| 18 | On-device FTS5 indexer | `Search` | §18 | `Search/FTS/**` |

Shared rule: each adds its own `APIClient+<Domain>.swift` in `Networking` package — never edits another domain's file.

**Phase 3 gate:** Every list scrolls 1000 rows at 60fps+; pull-to-refresh round-trips; offline fallback banner works.

---

### Phase 4 — Write flows (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 4 | Ticket create / edit deep | `Tickets` | §4 | `Tickets/Create/**`, `Tickets/Edit/**` |
| 4 | Ticket state machine | `Tickets` | §4 | `Tickets/StateMachine.swift` |
| 5 | Customer create / edit / merge | `Customers` | §5 | `Customers/Create/**`, `Customers/Merge/**` |
| 6 | Inventory create / receive | `Inventory` | §6 | `Inventory/Create/**`, `Inventory/Receiving/**` |
| 6 | Stocktake | `Inventory` | §6 | `Inventory/Stocktake/**` |
| 7+4 | Invoice payment / refund | `Invoices` | §7 | `Invoices/Payment/**`, `Invoices/Refunds/**` |
| 8 | Estimate convert to ticket | `Estimates` | §8, §4 | `Estimates/Convert/**` |
| 10 | Appointment create + scheduling engine | `Appointments` | §10 | `Appointments/Create/**` |
| 12 | Message templates | `Communications` | §12 | `Communications/Templates/**` |
| 46 | Employee clock in/out | `Employees` | §14 | `Employees/Clock/**` |
| 46 | Commissions | `Employees` | §46 | `Employees/Commissions/**` |

**Phase 4 gate:** Every entity roundtrips server; audit log entries appear; offline writes survive.

---

### Phase 5 — POS & hardware

| § | Title | Pkg | Deps | Owns | Parallel-with |
|---|---|---|---|---|---|
| 16 | POS checkout | `Pos` | Phase 4 | `Packages/Pos/Sources/**` | §17-subs |
| 39 | Cash register | `Pos` | §16 | `Pos/CashSession/**` | §17-subs |
| 40 | Gift cards / store credit / refunds | `Pos` | §16 | `Pos/GiftCards/**` | §17-subs |
| 41 | Payment links | `Pos` | §16 | `Pos/PaymentLinks/**` | §17-subs |
| 16 | POS keyboard shortcuts | `Pos` | §16 | `Pos/Shortcuts.swift` | — |
| 16 | Gift receipt | `Pos` | §16 | `Pos/Receipt/GiftVariant.swift` | — |
| 16 | Reprint flow | `Pos` | §16 | `Pos/Reprint/**` | — |
| 16 | POS offline queue | `Pos` + `Sync` | §20, §16 | `Pos/OfflineQueue/**` | — |
| 17 | Hardware group (meta) | — | Phase 4 | — | parent of below |
| 4 | Camera stack | `Camera` | Phase 4 | `Packages/Camera/Sources/**` | §17.x siblings |
| 17.2 | Barcode scan | `Camera` | §4 | `Camera/Barcode/**` | siblings |
| 17 | Print engine | `Hardware` | §16 | `Packages/Hardware/Sources/Hardware/Printing/**` | siblings |
| 17 | Label printing | `Hardware` | §17 | `Hardware/Labels/**` | — |
| 17 | BlockChyp terminal pairing | `Hardware` | §16 | `Hardware/Terminal/**` | — |
| 17 | Bluetooth device mgmt | `Hardware` | §4 | `Hardware/Bluetooth/**` | — |
| 17 | Weight scale | `Hardware` | §17 | `Hardware/Scale/**` | — |
| 17 | Cash drawer trigger | `Hardware` | §17 | `Hardware/Drawer/**` | — |
| 16 | Customer-facing display | `Pos` | §16 | `Pos/CFD/**` | — |
| 4 | Photo annotation | `Camera` | §4 | `Camera/Annotation/**` | — |
| 42 | Voice memos | `Camera` | §4 | `Camera/Voice/**` | — |
| 5 | Document scanner | `Camera` | §4 | `Camera/DocScan/**` | — |

**Phase 5 gate:** Cash + card sale both succeed; receipt prints; drawer kicks on cash tender; barcode adds to cart; offline POS queue drains correctly.

---

### Phase 6 — Platform integrations (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 21 | APNs push + silent push + categories | `Notifications` | Phase 1 | `Notifications/Push/**` |
| 13 | Notification channels / categories | `Notifications` | §21 | `Notifications/Categories/**` |
| 13 | Notifications UX polish | `Notifications` | §21 | `Notifications/UX/**` |
| 24 | Widgets (Home / Lock / StandBy) | `App` / widget target | Phase 3 | `App/Widgets/**` (new target) |
| 24 | Siri + App Intents | `App` / intents target | Phase 4 | `App/Intents/**` (new target) |
| 24 | Shortcuts gallery | `App` / intents target | §24 | `App/Intents/Gallery/**` |
| 41 | Apple Wallet pass designs | `Pos` / `Employees` | §38, §40 | `Pos/Wallet/**` |
| 24 | Spotlight indexing | `Search` | §18 | `Search/Spotlight/**` |
| 25 | Handoff / Continuity | `App` | Phase 3 | `App/Handoff.swift` |
| 55+58+208 | Public pages (served by server) | server | — | iOS: just deep-link into `SFSafariViewController`; no work in-app beyond launch |

**Phase 6 gate:** Push tap opens correct screen; widget pulls from App Group DB; Siri phrase creates ticket; Spotlight surfaces customer.

---

### Phase 7 — iPad polish (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 22 | iPad layouts baseline | all feature packages | Phase 3 | per-package `iPad/` subfolder |
| 22 | Multi-window / Stage Manager | `App` | §22 | `App/Scenes/**` |
| 30 | Sidebar adaptive widths | `App` | §22 | `App/Sidebar/**` |
| 22 | iPad Pro M4 features | `DesignSystem` | §22 | tokens + motion adjustments |
| 4 (iPad) | Pencil annotation | `Camera` | §4 | incremental |
| 23 | Keyboard handling | `App` | Phase 1 | `App/Keyboard/**` |
| 23 | Keyboard shortcut overlay | `App` | §23 | `App/Keyboard/Overlay.swift` |
| 22 | Ticket quick-actions | `Tickets` | §4 | `Tickets/QuickActions/**` |

Each feature package gets an iPad polish ticket; owner stays the feature owner from Phase 3.

**Phase 7 gate:** Every listed screen uses 3-col `NavigationSplitView` on iPad; keyboard shortcut overlay lists ≥ 20 shortcuts; Pencil draws on annotation canvas.

---

### Phase 8 — Reports / loyalty / marketing (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 15 | Reports charts | `Reports` | Phase 3 | `Packages/Reports/Sources/**` |
| 15 | Tenant BI | `Reports` | §15 | `Reports/BI/**` |
| 15 | Drill-through | `Reports` | §15 | `Reports/DrillThrough/**` |
| 38 | Loyalty engine | `Customers` | Phase 4 | `Customers/Loyalty/**` |
| 38 | Memberships | `Customers` | §38 | `Customers/Memberships/**` |
| 37 | Referral program | `Customers` | §38 | `Customers/Referrals/**` |
| 37 | Marketing campaigns | `Communications` | Phase 4 | `Communications/Campaigns/**` |
| 64 | Email templates | `Communications` | §37 | `Communications/Email/**` |
| 16 | Discount engine | `Pos` + `Invoices` | Phase 5 | shared; lead: `Pos` owner |
| 37 | Coupon codes | `Pos` | §16 | `Pos/Coupons/**` |
| 6 | Pricing rules engine | `Pos` | §16 | `Pos/Pricing/**` |
| 15 | CSAT + NPS | `Customers` | §6 | `Customers/CSAT/**` |
| 37 | Review solicitation | `Customers` | §15 | `Customers/Reviews/**` |

**Phase 8 gate:** Revenue chart + drill-through works; membership enrollment + wallet pass updates; campaign blast round-trips.

---

### Phase 9 — Settings / admin (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 19 | Settings root + 27 sub-pages | `Settings` | Phase 1 | `Packages/Settings/Sources/**` (sub-pages sharable across agents; each page is its own file) |
| 19 | Settings search | `Settings` | §19 | `Settings/Search/**` |
| 47 | Roles matrix editor | `Settings` | §19 | `Settings/Roles/**` |
| 48 | Data import wizard | `Settings` | §19 | `Settings/DataImport/**` |
| 49 | Data export | `Settings` | §19 | `Settings/DataExport/**` |
| 50 | Audit log viewer | `Settings` | §19 | `Settings/Audit/**` |
| 60 | Multi-location mgmt | `Settings` | §19 | `Settings/Locations/**` |
| 19 | Hours & holiday calendar | `Settings` | §19 | `Settings/Hours/**` |
| 19 | Tenant admin tools + flags UI | `Settings` | §19 | `Settings/TenantAdmin/**` |
| 51 | Training mode | `Settings` | §19 | `Settings/Training/**` |

Ownership within Settings: each sub-page (`Settings/Roles/`, `Settings/Audit/`, etc.) is a separate agent; settings root file is advisory-lock.

**Phase 9 gate:** Settings search surfaces every page; role matrix persists; import / export round-trip; audit entries show diffs.

---

### Phase 10 — Accessibility / performance / i18n (parallel)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 26 | A11y passes (per-feature) | every feature pkg | Phase 3+ | each feature owner runs audit script |
| 26 | A11y label catalog | `Core` | §26 | `Core/A11y/Labels.swift` |
| 29 | Automated a11y audit CI | tooling | §26 | `Tests/A11y/**`, CI config |
| 26 | Sticky a11y tips (TipKit) | `DesignSystem` | Phase 3 | `DesignSystem/Tips/**` |
| 29 | Performance budgets | tooling | Phase 3 | `Tests/Performance/**` |
| 29 | Perf benchmark harness | tooling | §29 | `scripts/bench.sh` |
| 29 | Battery bench per screen | tooling | §29 | per-feature perf tests |
| 27 | i18n (4 locale phases) | tooling + all feature pkgs | Phase 3 | `Locales/*.lproj/` |
| 27 | Localization glossary | `Core` | §27 | `docs/localization/` |
| 27 | RTL layout rules | every feature pkg | §27 | per-package snapshot updates |

**Phase 10 gate:** A11y CI zero violations; p95 perf budgets met on iPhone SE 3 + iPad Pro M4; pseudo-loc run passes (no truncation).

---

### Phase 11 — Security / release (serial)

| § | Title | Pkg | Deps | Owns |
|---|---|---|---|---|
| 28+90 | STRIDE threat model review | security-reviewer agent | Phase 10 | `docs/security/threat-model.md` |
| 32 | Sovereignty guardrails (SDK ban lint) | tooling | Phase 0 | `scripts/sdk-ban.sh`, CI rule |
| 32 | Crash recovery pipeline | `Core` | Phase 2 | `Core/Crash/**` |
| 75 | App Store assets | marketing | Phase 10 | `fastlane/metadata/**` |
| 76 | TestFlight rollout plan | release agent | §75 | `fastlane/Fastfile` lanes |
| 33 | App Review checklist | release agent | §75 | `docs/app-review.md` |
| 34 | Crisis playbook | ops | §32 | `docs/runbooks/*.md` |
| 34 | Incident runbook index | ops | §34 | `docs/runbooks/index.md` |

**Phase 11 gate:** Submission accepted by Apple; phased rollout lane armed; STRIDE review signed; sovereignty SDK-ban lint passes in CI.

---

## Dependency graph (text form)

```
Phase 0 ──► Phase 1 ──► Phase 2 ──► ┬── Phase 3 (parallel fan-out)
                                    │
                                    ▼
                                    Phase 4 ──► Phase 5 ──► ┬── Phase 6
                                                            ├── Phase 7
                                                            ├── Phase 8
                                                            └── Phase 9
                                                                       │
                                                                       ▼
                                                                   Phase 10 ──► Phase 11
```

Notes:
- Phase 3 and Phase 4 can overlap if write flow for one entity waits on its own read flow only.
- Phase 6 / 7 / 8 / 9 can run concurrently once Phase 4 gates.
- Phase 10 audit waits for at least Phase 3-9 to feature-complete per section being audited.
- Phase 11 is final release gate.

---

## PR conventions

- Title: `[§N] <ActionPlan section title>` — exact match so tooling can auto-link.
- Body must include:
  1. `Closes: §N in ActionPlan.md` (triggers auto-flip of `[x]` on merge).
  2. "Deps:" list confirming upstream sections done.
  3. "Testing:" evidence (unit, snapshot, XCUITest).
  4. "A11y:" one-line confirmation of labels + Dynamic Type.
- Size: < 800 lines diff preferred. Split larger work.
- Commit messages: `feat(§N): <thing>` / `fix(§N): <thing>` / `chore(§N): <thing>`.
- Never merge past a failed phase gate. Never skip phases.

---

## Conflict handling

- **Shared additive conflicts** (e.g., two domains adding to `APIClient+*.swift` variants): impossible by design — each domain owns its own file.
- **Advisory-lock conflicts** (two agents want to edit `BizarreCRMApp.swift`): FIFO by claim comment. Second agent rebases.
- **Design token additions**: append-only means no textual conflict even with parallel PRs.
- **Feature-module cross-imports**: not allowed. Use `Core` protocols instead; see §1 DI.
- **Test file conflicts**: never — each package has its own `Tests/` tree.
- **Localization merge conflicts**: loc agent merges last; feature agents commit English only; loc agent translates + commits per-locale file.
- **Phase gate disagreement**: human decision; default = block progression.

---

## What "done" means per section

Every section ticks all of:

1. Feature works end-to-end on iPhone + iPad (+ Mac via "Designed for iPad").
2. Offline path exercised (where applicable).
3. Unit + snapshot + XCUITest coverage ≥ 80%.
4. A11y labels + Dynamic Type + Reduce Motion respected.
5. Liquid Glass applied to chrome only (per §30).
6. No orphan UI (wired to Repository → API/DB).
7. No inline hex / points / durations (tokens only).
8. No third-party network peer beyond `APIClient.baseURL`.
9. Localization keys added (English source + pseudo-loc passes).
10. ActionPlan checkbox flipped with commit SHA.

---

## How to launch a sub-agent

Template prompt:
```
You own §<N> <title> from ios/ActionPlan.md.

Read before coding:
- ios/ActionPlan.md §<N> in full.
- ios/agent-ownership.md (this file) — confirm phase + deps + owned files.
- ios/CLAUDE.md — session rules.

Constraints:
- Touch only files under "Owns" for §<N>.
- No edits to ActionPlan.md content — only flip checkbox on completion.
- All design tokens from DesignSystem/Tokens.swift.
- Liquid Glass only on chrome.
- iPad layout distinct from iPhone.
- Single network peer = APIClient.baseURL.
- 80% coverage floor per PR.
- Respect phase gate: abort if dependency §<X> not yet marked done.

Deliverables:
- PR titled "[§<N>] <title>" with evidence of tests, a11y, iPad variant.
```

---

## Maintenance

- This file updated whenever ActionPlan.md changes scope.
- Single owner for this file: iOS lead + human review.
- Quarterly prune: remove sections flipped to done; archive to `docs/done/`.
