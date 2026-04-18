# ios/TODO.md — iOS follow-ups

Living checklist of deferred items. Check off as completed, don't skip.

## Visual polish (deferred to post-wiring)

- [ ] **Liquid Glass aesthetic** — current surfaces use `.brandGlass(...)` but material fallback still shows on device; audit which surfaces should visibly refract on iOS 26.3 and make sure the real `.glassEffect(...)` path fires.
- [ ] **Dark-mode surface palette** — Login background orbs look flat; re-tune colors + blur radius for iOS 26 Liquid Glass sampling.
- [ ] **Brand fonts end-to-end** — `scripts/fetch-fonts.sh` downloads Inter/Barlow/JetBrains Mono; verify after running it that text renders in the right family (currently SF Pro fallback is visible).
- [ ] **AppIcon** — ship a real 1024×1024 brand icon PNG.
- [ ] **Launch screen** — right now it's a solid `SurfaceBase` color; design a proper branded launch with the wordmark/wave.
- [ ] **Iconography** — review all SF Symbols usages against brand palette; swap to branded assets where appropriate.
- [ ] **Accessibility** — VoiceOver labels on buttons/fields (Login flow first), Dynamic Type at `.accessibilityXL`, Reduce Transparency + Increase Contrast audit.
- [ ] **Motion spec** — apply `BrandMotion.*` durations/springs uniformly; enforce `@Environment(\.accessibilityReduceMotion)` fallback.
- [ ] **iPad layout for Login** — currently phone-first; iPad should use a centered card with wider margins on the big screen.

## Phase 1 — Auth (finish end-to-end)

- [ ] Verify Login → 2FA → PIN → Dashboard round-trips against a live `bizarrecrm.com` tenant on device.
- [ ] Persist last-logged-in username so re-auth is frictionless.
- [ ] Token refresh on 401 (background refresh + retry original request).
- [ ] Sign-out flow in Settings (clears Keychain + resets AppState).

## Phase 2 — Read-only shell (next workflow)

- [ ] Dashboard: `/reports/dashboard` + `/reports/needs-attention` with KPI cards + "Needs Attention" section.
- [ ] Tickets list: `/tickets` with `.swipeActions` + filter chips. GRDB cache via `TicketRepository`.
- [ ] Customers list: `/customers` with search-by-name.
- [ ] Inventory list: `/inventory` with low-stock badge.
- [ ] Invoices list: `/invoices` read-only view.
- [ ] SMS list: `/sms/threads` + WS subscription for live updates.

## Phase 3+ — see docs/howtoIOS.md §26