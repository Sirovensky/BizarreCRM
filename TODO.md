---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## NEW 2026-04-16 (from live Android verify)

- [ ] NEW-TLIST-GRP. **Android ticket list: show the status *group* for each row, not only the raw status name** — today each ticket shows a specific status badge ("Waiting for asset", "Payment Received & Picked Up", "Cancelled"). Add a second indicator (pill, left border, or small category label) that maps to the high-level group: Waiting / Ready / In Progress / Complete / Cancelled. Group taxonomy already exists server-side in `tickets.routes.ts` (`status_group` filter: `active | open | closed | cancelled | on_hold`). Confirmed live 2026-04-16: easy to see a specific status, hard to scan which tickets are ready to pick up vs waiting on parts.

- [ ] NEW-MSG-EMPTYHINT. **Android Messages empty state still says "Tap the edit icon"** — post-CROSS42, the new-message action is a FAB (pencil icon at bottom-right). The empty-state subtext at `SmsListScreen.kt` still reads "Tap the edit icon to start a new conversation". Needs update to reference the FAB ("Tap the + button to start a new conversation").

## DEBUG / SECURITY BYPASSES — must harden or remove before production

- [ ] DEBUG-SEC1. **Dev-only bare-IP tenantResolver bypass:** `packages/server/src/middleware/tenantResolver.ts` accepts bare-IPv4 Host headers (e.g. `10.1.10.4`) when `NODE_ENV !== 'production'` and routes them to `DEV_TENANT_SLUG` (or the first active tenant). Added 2026-04-16 so the Android self-hosted client can reach a LAN dev server without real DNS. Before production: (a) double-check the `NODE_ENV` gate is enforced at every deploy (prod sets `NODE_ENV=production`), (b) add an `APP_ENV=development` secondary guard so a misconfigured NODE_ENV doesn't silently enable this, (c) consider only accepting the *trusted-proxy* IP as a dev override rather than any-IP, (d) add a startup banner that logs a loud warning when this bypass is active. Commit that introduced this bypass: server-side tenantResolver edit on 2026-04-16.

## CROSS-PLATFORM

- [ ] CROSS3. **Remove Service tab from Inventory (web + Android):** Services are NOT inventory — they're labor (uncountable, no stock). Seeded in `repair_services` table via `010_repair_pricing.sql:43` (~35 rows across phone/laptop/console/tablet/tv). Desktop already treats them separately; Android + any remaining web inventory filter still list "Service" as an item_type tab. Changes: (1) Android `InventoryListScreen.kt:159` remove `"Service"` from `types` list, (2) web `InventoryListPage.tsx` inventory type tabs — drop service, (3) `InventoryCreatePage.tsx` item_type dropdown — drop service option, (4) data migration: audit existing `inventory_items WHERE item_type='service'` rows, migrate into `repair_services` (or mark `is_deleted=1` if already dupes), (5) verify service add-to-cart in POS/TicketWizard still works via `repair_services` path (NOT inventory path) — this is the critical preserve-behavior check. Keep the item_type column itself (other values still valid: product, part).

- [ ] CROSS7. **Phone auto-format on WRITE (Android):** MEMORY rule says store phone must auto-format to `+1 (XXX)-XXX-XXXX`. Confirmed on Android during 2026-04-16 audit: typed `5555551234` into customer create phone field, saved as raw `5555551234` with no formatting applied. Must format on input (ideally as user types via VisualTransformation) OR normalize on save. Detail view shows some formatting (partial — need to verify exact format applied on read vs write). Fix scope: Android `CustomerCreateScreen` phone field — wrap TextField in a phone VisualTransformation matching the `+1 (XXX)-XXX-XXXX` pattern, and normalize the stored value server-side via existing phone normalizer if one exists (check `packages/server/src/utils/phone.ts` or similar).

- [ ] CROSS8. **Phone display inconsistency across Android screens:** confirmed on 2026-04-16 — same phone number renders differently on different Android screens. Detail view: formatted. List view: raw digits. Search result row: raw digits. Pick ONE canonical display format (`+1 (XXX) XXX-XXXX` per MEMORY) and extract a shared `PhoneFormatter` composable / extension function used everywhere a phone is displayed. Grep Android `String.kt` / `PhoneUtils.kt` / similar for any existing utility, extend if present, otherwise create one. Apply to: customer list, customer detail, customer search result, ticket detail (customer row), invoice detail, POS customer picker, employee list, employee detail.

- [ ] CROSS9. **Customer detail screen (Android) missing sections:** on 2026-04-16 audit, CustomerDetailScreen shows only a bare card (name + phone + email) then massive empty space below. Missing vs web parity: ticket history list, notes list + add-note composer, addresses (billing/shipping), tags, recent invoices, lifetime-value summary. Check `packages/web/src/pages/customers/CustomerDetailPage.tsx` for the canonical section list, then add matching sections to Android `CustomerDetailScreen.kt`. Endpoints likely already exist (`/customers/:id/tickets`, `/customers/:id/notes`, `/customers/:id/addresses`) — verify in `server/src/routes/customers.routes.ts` before adding Android API methods. Scope is large — consider splitting into CROSS9a (ticket history), CROSS9b (notes), CROSS9c (addresses), CROSS9d (tags) if implementing incrementally.

- [ ] CROSS10. **Ticket creation wizard: add walk-in shortcut (Android):** Android ticket wizard currently 6 steps with no walk-in fast path. User must either search existing customers or create a new one before reaching device step. Add a "Walk-in" ghost button on the customer-picker step (parity with web CROSS4). Block until CROSS5 decides NULL vs seeded-row representation so we don't build it wrong. Similar to CROSS4, may be not needed.

- [ ] CROSS12. **Lock seeded "Walk-in Customer" row against edit/delete:** confirmed on 2026-04-16 — Walk-in Customer seeded row is fully editable from Android CustomerDetailScreen (Edit button visible in top bar, no guard). Renaming or deleting it breaks every historical ticket that references it. Add server-side protection: `customers.is_system = 1` flag on seeded row via migration, if attempted to be edited, from a ticket, it should create a new customer id in the background, in case information is required to be added.

- [ ] CROSS13. **Phone display format partial on Android detail — missing `+1` prefix:** per MEMORY rule phones should render as `+1 (XXX)-XXX-XXXX`. Android CustomerDetailScreen shows `(555) 555-1234` — correct parens but missing `+1` prefix AND uses space after `)` instead of the MEMORY-spec dash. Either (a) update MEMORY rule to match current code (`(XXX) XXX-XXXX`, no +1), OR (b) fix Android + web phone formatter to emit `+1 (XXX)-XXX-XXXX` exactly as specified. Decision needed before touching code. Not all phones are +1 — consider i18n: strip-or-render country code based on stored E.164 value. Affects: all phone-display sites (see CROSS8 list).

- [ ] CROSS15. **Android ticket wizard step order confusing: Customer → Category → Device → Service → Details → Cart:** "Category" before "Device" is unusual. Typical repair flow: pick customer, pick device (what's broken), pick service (screen/battery/etc.), then details. Two ways to reconcile: (a) if Category = device-type category (phone/tablet/laptop), rename to "Device Type" or merge into Device step with a type-picker first, (b) if Category = repair-category (screen repair, water damage, diagnostic), move it AFTER Device since user needs to know what device before choosing what's wrong with it. Inspect `TicketWizardScreen.kt` to see what Category actually selects, then rename + reorder accordingly. Six steps is already long — consider whether Category can be collapsed into Device or Service.

- [ ] CROSS18. **Android wizard top bar has excess empty space above title:** ~200px of dead space between system status bar and "New ticket" title. Scaffold's `TopAppBar` likely has default padding + statusBarsPadding + extra custom padding stacked. Reduce to one standard `statusBarsPadding()` + Material `TopAppBar` default height. Audit all Android Scaffold headers for same issue — same dead space visible on DashboardScreen, CustomerListScreen.

- [ ] CROSS19. **Android brand-color chaos — three competing accent colors:** confirmed visually on 2026-04-16. Three different accents fight across screens: (1) **orange** — FAB (customer list, dashboard), "View All" link, "Create New Customer" button, active step pill in ticket wizard; (2) **teal/cyan** — "Synced" status badge, bottom nav active tab, search bar magnifying-glass icon, "No tickets assigned to you" empty-state text; (3) **magenta `#bc398f`** — thin divider line under dashboard header (matches MEMORY brand color). Per MEMORY web theme plan (BRAND1) the product accent is magenta + cream. Android currently uses none of that as primary. Pick ONE primary accent and one secondary, apply consistently. Recommend: magenta `#bc398f` as primary (matches web plan + logo), teal as success-only, drop orange entirely OR demote to warning-only. Audit `ui/theme/Color.kt` and replace `colorScheme.primary` / `secondary` / `tertiary` assignments. Touch every accent usage site: FABs, active nav, active tabs, action links, status chips.

- [ ] CROSS22-badge. **Dashboard notifications bell unread-count badge:** the bell icon now exists and routes to `NotificationListScreen` (commit fa2538e 2026-04-16). Still to do: render an unread-count badge via `NotificationApi.getUnreadCount()` so users don't need to open the list to know something is waiting.

- [ ] CROSS25. **Ticket wizard Category step mixes device types and service/flow concepts:** confirmed visually 2026-04-16. Step 2 "Select Category" grid contains 9 tiles but 2 of them aren't device categories: (a) "Data Recovery" — that's a **service** (it doesn't pick a device type, it's what you DO to a device); (b) "Quick Check-in" — that's a **flow shortcut**, not a device type. The remaining 7 are legit device categories (Mobile, Tablet, Laptop/Mac, TV, Desktop, Game Console, Other). Fix: split these two out of the grid. Data Recovery → move to step 4 Service options. Quick Check-in → promote to a top-level action (a "Quick Check-in" ghost button on the Tickets list screen or on the wizard Customer step) that skips straight to a simplified details form. Keeping them in the Category grid forces the user to pick one "device type" that isn't a device type, which breaks later steps (step 3 Device model list won't match).

- [ ] CROSS26. **Ticket wizard Category tiles use inconsistent emoji styles:** confirmed visually 2026-04-16. The 9 Category tiles use wildly mismatched emoji — colorful iOS-style phone emojis (Mobile/Tablet), white sketch laptop (Laptop/Mac), teal retro TV (📺), blue monitor (Desktop), grey controller (🎮), floppy disk (Data Recovery), **red question mark (Other — reads as ERROR)**, yellow lightning (Quick Check-in). No unified icon system. Rest of app uses MaterialIcons line-style glyphs. Fix: replace all 9 with MaterialIcons (`PhoneIphone`, `Tablet`, `Laptop`, `Tv`, `Monitor`, `SportsEsports`, `RestoreFromTrash`, `HelpOutline`, `FlashOn`). Same tint as other icons (`onSurfaceVariant`) — the "Other" red ? is especially bad because it looks like an error state.

- [ ] CROSS28. **Device picker brand-chip row lacks horizontal-scroll affordance:** confirmed visually 2026-04-16. Ticket wizard step 3 (Device) shows 5 brand chips (Apple, Samsung, Google, Motorola, LG) with the 6th chip clipped at the right edge and no fade gradient / arrow / visual hint that the row scrolls. Users may not discover Huawei, OnePlus, Xiaomi, etc. Fix: either (a) make the clipped chip partially visible (classic horizontal-scroll affordance), (b) add a right-edge fade-out gradient, or (c) add a small chevron indicator. Pattern applies to any horizontal LazyRow of chips app-wide — check TicketListScreen filter chips (CROSS23), POS category filters, Inventory type filters.

- [ ] CROSS29. **Device picker "Popular" list dominated by iPhones — no brand mix:** confirmed visually 2026-04-16. Step 3 Popular list shows 17 iPhone models before any non-Apple devices. Even after picking "Mobile" category (not Apple), iPhones fill the first screen. If "Popular" is ordered by shop historic ticket volume that's fine for a shop that repairs mostly iPhones — but for a new shop with no history, Popular should default to a curated mix (top 2-3 from each brand) so users can see the brand spread at a glance. Check `DeviceCatalogService` / seeded `device_models` table for how Popular is computed. Add fallback ordering: when tenant has no ticket history, interleave brands. 

- [ ] CROSS30. **Device picker "Device not listed?" CTA cut off at screen bottom:** confirmed visually 2026-04-16. The fallback button appears in a bar at the very bottom of step 3, but only the top half is visible (the button text "Device not listed?" is clipped). LazyColumn / Column sizing doesn't reserve space for the bottom CTA. Fix: make the fallback CTA a sticky bottom bar (`Box` with `Modifier.align(Alignment.BottomCenter)` + `statusBarsPadding()` on top and `navigationBarsPadding()` on bottom) OR add contentPadding to the list above so the last row can scroll above the CTA.

- [ ] CROSS31. **"No pricing configured" manual-price input is a tenant onboarding gap:** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. That's a correct runtime fallback, but it means every tenant who hasn't filled in `repair_services.price` has to manually type the price on EVERY ticket. Fixes in order of effort: (a) seed baseline prices per device-category + service combo (industry average or mobilesentrix-catalog-price × markup) into `repair_services` during tenant provisioning, so new shops have sensible defaults; (b) when the user enters a manual price, offer a "Save as default for this service" checkbox that upserts the price into `repair_services` so next time it's pre-filled; (c) surface a Settings → Pricing setup page link next to the manual-price field. Part of first-run shop setup wizard (SSW) scope.

- [ ] CROSS32. **Android Price input lacks $ prefix / currency indicator:** confirmed 2026-04-16. The Price field on service step just says "Price" with no $ symbol, no placeholder like "$0.00", and no currency suffix. User might type "50" without knowing if it's dollars, cents, or another currency. Fix: add `leadingIcon = { Text("$") }` OR placeholder `"$0.00"`. Respect the tenant's configured currency (check `store_config.currency`) so international tenants see the correct symbol.

- [ ] CROSS33. **Android button shape inconsistency — fully-rounded pill vs rectangle with corners:** confirmed 2026-04-16. Ticket wizard step 4 shows service pills with medium-corner rounded rectangles AND a primary CTA "Continue to Details" as a FULLY rounded pill button. Elsewhere buttons use medium-corner rectangles (Sign In, Create New Customer). Pick ONE shape — Material 3 default is medium corners — and apply everywhere. Audit `BrandButton` / primary action buttons in `ui/components/*.kt`.

- [ ] CROSS34. **Android BACK key during ticket wizard destroys all progress:** confirmed 2026-04-16. At step 4 (Service) I pressed BACK to dismiss the keyboard after typing a price — instead of hiding the IME or stepping back to step 3, the BACK gesture POPPED THE WHOLE WIZARD off the nav stack, returning to the Tickets list with all selections lost. Reproducible. Two separate problems: (1) when IME is visible, BACK should dismiss IME first — it doesn't because the price TextField isn't properly consuming the back event through `LocalSoftwareKeyboardController`; (2) when IME isn't visible, BACK should step to previous wizard step, not close the wizard. Fix: `BackHandler(enabled = wizardStep > 1) { wizardStep-- }` in TicketCreateScreen, AND let the TextField handle IME-dismiss via Compose's normal flow. Add "Discard ticket?" confirmation dialog if user tries to back out from step 1.

- [ ] CROSS35. **Android login Cut action performs Copy instead of Cut:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the text to the clipboard but does NOT remove it from the field (should do both). Reproducible on both fields. Cause is likely a broken or missing `onCut` handler in the TextField's text-toolbar / selection controller, OR the Compose TextField's `TextToolbar` is overridden without wiring cut properly. Fix: in `LoginScreen.kt` remove any custom `TextToolbar` override, or implement `onCutRequested` to both copy AND clear the selected range. Verify Cut works on OTHER TextFields in the app too (customer create, ticket wizard, notes) — may be a Compose-version regression affecting every field if a global override exists.

- [ ] CROSS36. **Android Reports screen uses ugly brown filled stat cards:** confirmed visually 2026-04-16. On More → Reports, the Dashboard tab shows two stat cards (Revenue Today $0.00, Open Tickets 0) with **saturated brown/tan filled backgrounds** — looks like milk chocolate, very out of place in a dark-theme UI. Dashboard (bottom nav) uses dark-surface cards with orange numeric text — the consistent treatment. Replace `ReportsScreen.kt` stat cards with the same surface style as DashboardScreen. Audit for any other surprise filled-color backgrounds.

- [ ] CROSS37. **Android Reports tabs: all three labels orange, only underline indicates active:** confirmed 2026-04-16. Tabs "Dashboard" / "Sales" / "Needs Attention" all render in orange text; only an orange underline under the active tab signals selection. With low-vision or fast-glance users, labels look identical-weight. Fix: inactive tab labels should be `onSurfaceVariant` (muted grey) and only the active one in primary accent — plus the underline. Applies to any Material3 TabRow anywhere in the app.

- [ ] CROSS38b. **Android Settings: add Edit Profile + Notification preferences rows** — the About card and Sign Out button now exist (commit c2f32a1 2026-04-16). Still missing: Edit Profile row (requires routing `ProfileScreen.kt` — currently orphaned, tracked under AND-20260414-M3), Notifications preferences sub-page (separate from notifications inbox per CROSS54), optional Language + Terms/Privacy rows.

- [ ] CROSS40. **Android role label case inconsistent — "Admin" vs "admin":** confirmed 2026-04-16. Employees screen shows role chip "Admin" (title case, teal pill). Settings screen shows "Role: admin" (lowercase). Same underlying value `role = "admin"`. Pick ONE presentation — Title Case looks more polished — and apply a `String.titlecase()` or enum-based label formatter at render. Audit every role display (Employee list, Employee detail, Settings, Ticket-assigned-to chip).

- [ ] CROSS41. **Android More drawer: no user profile header at top, Dashboard item duplicated:** confirmed 2026-04-16. Common mobile pattern places signed-in user's avatar + name + role at the top of a drawer, with a prominent Log Out at the bottom. Android More drawer has neither. Also "Dashboard" appears BOTH in the bottom nav AND as a row inside the More drawer under CORE — duplicate entry. Fix: drop Dashboard from More drawer (already in bottom nav), add a user-profile header card at the top showing name/email/role with tap → profile edit, add a Log Out row at the bottom (destructive).

- [ ] CROSS44. **Android Employees avatar generic person icon — inconsistent with Customers initial-circles:** confirmed 2026-04-16. Customer list rows render a colored circle with the first letter of the name (T for Testy, W for Walk-in). Employee list rows render a GENERIC grey person icon with no initial. Pick one style — colored initial circle is better (faster visual scan, prevents "every row looks the same"). Apply to Employees list + Employees search results + Customers search results (which also uses generic icon per CROSS8).

- [ ] CROSS45. **Android magenta divider line placement inconsistent across screens:** confirmed 2026-04-16. The thin magenta `#bc398f` squiggle divider appears: right under the dashboard header (high, decorative), under the filter chips on Tickets/Leads (middle, separating header from content), mid-screen on Invoices/Estimates (floating above empty state with no clear purpose), NOT on Messages at all. Pick one rule: "always directly below the TopAppBar / header row" is the cleanest, signaling end-of-header. 

- [ ] CROSS46. **Android date format inconsistent between screens:** confirmed 2026-04-16. Dashboard shows "Thursday, April 16" (no year, full month). Appointments shows "Thursday, Apr 16, 2026" (year included, abbreviated month). Settings shows "2026-04-16 21:17:57" (raw). Pick ONE absolute format (recommend `LLLL d, yyyy` = "April 16, 2026") and ONE relative format ("2 hours ago") and route all date rendering through a single `DateFormatter` util.

- [ ] CROSS47. **Android Customer detail missing "Create Ticket for this customer" CTA:** confirmed 2026-04-16. Common CRM workflow = look up customer, create ticket FOR them. Currently on CustomerDetailScreen the only actions are Call / SMS / Edit. To create a ticket for Testy McTest the user must back out, tap Tickets nav, tap FAB, search for Testy, select. Add either (a) a primary "Create Ticket" button below Contact info, or (b) a FAB on customer detail that opens the ticket wizard with customer pre-selected (skip step 1). Same applies to "Create Invoice", "Create Estimate" for this customer — consider a quick-action row with 3 buttons.

- [ ] CROSS48. **Android primary-button style not standardized — filled vs outlined mismatch:** confirmed 2026-04-16. Customer detail: Call = orange filled (black text), SMS = outlined (orange text) — Call is "primary" somehow even though both are peer actions. Ticket wizard "Continue to Details" = orange filled (text color TBD). Sign In button = orange filled white text. Service pills = outlined grey. No consistent rule for primary vs secondary. Define `BrandButton` variants: `Primary` (filled accent, onPrimary text), `Secondary` (outlined accent, accent text), `Tertiary` (text-only, accent text). Apply one variant per action-level across the app. Also decide on text color for orange filled buttons — current mix of black and white is visible on Call vs Sign In.

- [ ] CROSS49. **Android Customer detail: no avatar shown (list HAS initial-circle, detail DOESN'T):** confirmed 2026-04-16. Customer list row shows big colored initial circle (`T` for Testy on brown background). Customer detail page shows ZERO avatar — just the name in the top bar. Inconsistent. Add the same initial-circle avatar at top of detail page (larger), above or beside the name. Covered in part by CROSS9 (bare detail) but worth its own checklist item.

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.


- [ ] CROSS52. **Android Customer Edit form has DUPLICATE Save buttons (top bar + bottom bar):** confirmed visually 2026-04-16. Top app bar shows "Save" as an orange text action in the right corner. Bottom of form has a sticky action bar with "Cancel" (outlined) + "Save" (filled orange). Two Save buttons that do the same thing. Pick one. Bottom sticky bar is more thumb-friendly — drop the top-right Save, keep bottom. Also applies to any other edit form in the app (TicketEditScreen, InventoryCreateScreen, etc.) — sweep.

- [ ] CROSS53. **Android Customer Edit: Group field styled differently (label above instead of inside):** confirmed visually 2026-04-16. Every other field in the edit form is a Material OutlinedTextField with label floating inside the border outline (First Name, Phone, Email, Organization, Address, City, State, Tags). The Group field renders label "Group" ABOVE the field box with value "None" inside, different visual treatment — likely because it's a Dropdown/Select component with a different container. Unify: either make every field use the dropdown shape OR make the Group dropdown use the OutlinedTextField shape (Material3 `ExposedDropdownMenuBox` wraps the anchor TextField so it can match).

- [ ] CROSS54. **Android Notifications page naming is ambiguous — inbox vs preferences:** confirmed 2026-04-16. More → Settings → Notifications goes to a notification-inbox list screen ("No notifications / You're all caught up"), NOT to notification preferences/settings. Users expect "Notifications" under the SETTINGS section to be preferences (enable push, mute categories, etc.). Two fixes together: (a) rename this list screen to "Activity" or "Alerts" or "Inbox" so Notifications settings is free; (b) add a real Notifications Preferences page in Settings (push enable, categories, quiet hours). Alternately put the Inbox at the TOP of More (not under SETTINGS section) and reserve "Notifications" under SETTINGS for prefs.

- [ ] CROSS55. **Android Notifications list missing filter chips + search + settings gear:** confirmed 2026-04-16. Every other list screen in the app (Customers, Tickets, Inventory, Invoices, Leads, Estimates, Expenses) has a search bar and filter chips at the top. Notifications has neither — just an empty state. Add: (a) search bar ("Search notifications..."), (b) filter chips (All / Unread / Mentions / System), (c) settings-gear icon in top bar routing to notification preferences. Parity matters — users don't want to guess where notification features live.

- [ ] CROSS56. **Android Customer Edit Tags field placeholder "tag1, tag2, tag3" is a literal placeholder, not a template example:** confirmed visually 2026-04-16 — the Tags field shows placeholder text `tag1, tag2, tag3` when empty. That reads like a sample demonstrating the comma-separated format. It's fine as a hint BUT it disappears as soon as the user types. Consider replacing with `"VIP, corporate, loyalty"` or something tenant-relevant — `tag1, tag2, tag3` looks like developer placeholder text that got shipped. Also think about letting the user pick from existing-tags-in-tenant autocomplete instead of free-form comma-separated input.

- [ ] CROSS57. **Web-vs-Android parity audit — surface advanced web features on Android under a "Superuser" (advanced) tab:** 2026-04-16 audit comparing `packages/web/src/pages/` (≈150 files) vs `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/` (39 files). Web has many features missing entirely from Android. User directive: "if too advanced for Android, put under Superuser tab so people know it's advanced". Break into **CORE** (must ship on Android, everyday workflows) and **SUPERUSER** (advanced, acceptable in Settings → Superuser). NOT in scope: customer-facing portal (`portal/*`), landing/signup (`signup/SignupPage`, `landing/LandingPage`), tracking public page, TV display — these are non-admin surfaces that don't belong in the admin app.

  **Consolidation caveat (verified via code read 2026-04-16):** several Android screens roll multiple web pages into one scrollable detail. When auditing parity, check for consolidation before declaring a feature "missing":
  - Android `TicketDetailScreen.kt` (932 lines) has Customer card + Info row + Devices + Notes + Timeline/History + Photos sections inline. This covers web's `TicketSidebar`, `TicketDevices`, `TicketNotes`, `TicketActions` — NOT missing. Only web-exclusive here is `TicketPayments.tsx` (payments likely route through Invoice in Android).
  - Android `InvoiceDetailScreen.kt` (660 lines) has Status + customer + Line items + Totals + Payments sections inline. Covers `InvoiceDetailPage`. Payment dialog is inline.
  - Android `CustomerDetailScreen.kt` (676 lines) renders email, address, organization, tags, notes SECTIONS CONDITIONALLY — only when data is non-empty. I saw only Phone on Testy McTest because email/address/etc. were all blank. CROSS51 was WRONG: the fields DO display when filled. CROSS9 still valid because **no ticket history, no invoice history, no lifetime value** is rendered regardless of data.
  - Android `SmsThreadScreen.kt` (441 lines) is bare conversation UI — genuinely missing every communications-advanced feature (templates inline, scheduled, assign, tags, sentiment, bulk, attachments, canned responses, auto-reply).

  **A. CORE — must add to Android (everyday workflows):**
  - **Unified POS cart/checkout**: `web/unified-pos/*` (14 files). Android currently has POS landing ("Quick Sale: Coming soon" — CROSS14). Needs full cart, product picker, discount, payment, receipt.
  - **Ticket Kanban board**: `web/tickets/KanbanBoard.tsx`. Android parity = alternate view mode on Tickets list (swipe between list/kanban).
  - **Ticket Payments panel**: `web/tickets/TicketPayments.tsx`. Either add a Payments section to TicketDetailScreen or route a "Take payment" action to a new screen.
  - **Communications advanced (genuinely missing on Android)**: in SmsThreadScreen add inline template picker, scheduled-send modal, assign-to-tech, conversation tags, attachment button, canned-response hotkeys; in SmsListScreen add bulk-SMS modal, failed-send retry list, off-hours auto-reply toggle, team-inbox header, sentiment badges.
  - **Lead pipeline (Kanban)**: `leads/LeadPipelinePage.tsx`.
  - **Lead calendar view**: `leads/CalendarPage.tsx`.
  - **Customer LTV/health badges**: `customers/components/HealthScoreBadge.tsx`, `LtvTierBadge.tsx`. Attach to CustomerDetailScreen quick-stats (fits CROSS50 redesign).
  - **Customer photos wallet**: `customers/components/PhotoMementosWallet.tsx`.
  - **Customer ticket/invoice history sections on CustomerDetailScreen**: genuinely missing — add a Tickets section (recent 5 tickets) and Invoices section (recent 5) that tap through to detail screens. Code already has `onNavigateToTicket` callback wired but never renders a list.
  - **Reports tabs**: Web has CustomerAcquisition, DeviceModels, PartsUsage, StalledTickets, TechnicianHours, WarrantyClaims, PartnerReport, TaxReport. Android ReportsScreen has 3 tabs (Dashboard / Sales / Needs Attention — CROSS36). Port the 8 additional report tabs.
  - **SMS templates**: Android HAS SmsTemplatesScreen — verify parity against web `SmsVoiceSettings` (separate audit task).
  - **Photo capture wiring**: Android has `PhotoCaptureScreen` — verify it's wired into TicketDetailScreen photo-add flow and InventoryDetail barcode/photo flow.
  - **Team features**: `team/MyQueuePage` (Android shows "My Queue" card on dashboard but taps "View All" — verify where it lands), `team/ShiftSchedulePage`, `team/TeamChatPage`, `team/TeamLeaderboardPage`. MyQueue + TeamChat highest value on mobile.

  **B. SUPERUSER — put under Settings → Superuser (advanced, power-user):**
  - **Billing & aged receivables**: `billing/AgingReportPage`, `DunningPage`, `PaymentLinksPage`, `CustomerPayPage`, `DepositCollectModal`. Owner/bookkeeper concerns, not day-to-day tech.
  - **Advanced inventory ops**: `AbcAnalysisPage`, `AutoReorderPage`, `BinLocationsPage`, `InventoryAgePage`, `MassLabelPrintPage`, `PurchaseOrdersPage`, `SerialNumbersPage`, `ShrinkagePage`, `StocktakePage`. Ship under Inventory → Advanced or Superuser. Stocktake especially benefits from mobile (barcode + on-floor counting).
  - **Marketing suite**: `marketing/CampaignsPage`, `NpsTrendPage`, `ReferralsDashboard`, `SegmentsPage`. Owner-level, not tech-level.
  - **Team admin**: `team/GoalsPage`, `PerformanceReviewsPage`, `RolesMatrixPage` (permissions matrix). Manager-only.
  - **Settings — 15 tabs missing**: AuditLogsTab, AutomationsTab, BillingTab, BlockChypSettings, ConditionsTab, DeviceTemplatesPage, InvoiceSettings, MembershipSettings, NotificationTemplatesTab, PosSettings, ReceiptSettings, RepairPricingTab (**fixes CROSS31 no-pricing bug**), SmsVoiceSettings, TicketsRepairsSettings, SetupProgressTab. Android Settings is bare (CROSS38: only 3 toggles). All these tabs should be accessible on Android — at minimum RepairPricingTab, ReceiptSettings, TicketsRepairsSettings as CORE, the rest under Superuser.
  - **Catalog browser**: `catalog/CatalogPage.tsx` — supplier device catalog. Useful during ticket intake when tech needs parts price/availability.
  - **Cash register**: `pos/CashRegisterPage.tsx` — open/close shift, cash counts. Ship as CORE if tenant uses cash (most repair shops do).
  - **Setup wizard**: `setup/SetupPage.tsx` + steps. First-run only — lives on SSW1 (existing TODO). Not needed as Settings tab, but Android should respect the `setup_wizard_completed` flag and show the wizard on first login.

  **C. Recommended Android Settings information architecture:**
  ```
  Settings
    ├─ Profile (existing ProfileScreen)
    ├─ Device preferences (biometric, haptic, dark mode — existing)
    ├─ Store
    │   ├─ Store info (hours, address, phone) — maps to web StepStoreInfo
    │   ├─ Receipts — maps to ReceiptSettings
    │   ├─ Tax — maps to StepTax
    │   └─ Repair pricing — maps to RepairPricingTab (fixes CROSS31)
    ├─ Communications
    │   ├─ SMS templates (existing SmsTemplatesScreen)
    │   ├─ SMS/Voice provider — maps to SmsVoiceSettings
    │   └─ Notification templates — maps to NotificationTemplatesTab
    ├─ Tickets & Repairs — maps to TicketsRepairsSettings
    ├─ Team
    │   ├─ Employees (existing)
    │   ├─ Clock in/out (existing ClockInOutScreen)
    │   └─ Roles & permissions — maps to RolesMatrixPage (superuser)
    ├─ Integrations
    │   ├─ BlockChyp / Stripe — maps to BlockChypSettings
    │   └─ Memberships — maps to MembershipSettings (superuser)
    └─ Superuser (advanced)
        ├─ Audit logs — AuditLogsTab
        ├─ Automations — AutomationsTab
        ├─ Billing / subscription — BillingTab
        ├─ Conditions / warranty — ConditionsTab
        ├─ Device templates — DeviceTemplatesPage
        ├─ Invoice settings — InvoiceSettings
        ├─ POS settings — PosSettings
        ├─ Inventory advanced (ABC, auto-reorder, bins, aging, labels, POs, serials, shrinkage, stocktake)
        └─ Marketing (campaigns, NPS, referrals, segments)
    ├─ Data sync (existing)
    └─ Log out (NEW — fixes CROSS38)
  ```
  Superuser tab must be HIDDEN behind a tap-the-logo-5-times-style easter egg OR visible to users with role=owner only, so regular techs don't get lost in power-user surfaces. Toast on first reveal: "Superuser settings unlocked — advanced options may change app behavior."

  **D. Icons / cross-surface notes:**
  - Missing QR/barcode scanner entry from POS and Ticket Detail (intake by barcode). Android has BarcodeScanScreen — wire additional entry points.
  - Missing Z-report / end-of-day report on Android POS (web has ZReportModal).
  - Missing "Training mode" flag on Android POS (web has TrainingModeBanner).
  - Missing Cash Drawer integration on Android POS.

## TENANT-OWNED STRIPE + SUBSCRIPTION CHARGING

- [ ] TS1. **Per-tenant Stripe integration for tenant → customer payments:** the env `STRIPE_SECRET_KEY` is PLATFORM-only (CRM subscription billing). Tenants currently rely on BlockChyp for their customer card payments and have no Stripe option. Add tenant-owned Stripe creds (`stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`) to `store_config`, expose a Settings → Payments UI for the tenant admin to paste them, and route all customer-facing Stripe calls (POS card, payment links, refunds) through the tenant's keys — never env. Webhook dispatcher must identify tenant from the Stripe account ID or dedicated subdomain path (`/api/v1/webhooks/stripe/tenant/:slug`) so each tenant's events land on their own DB. Liability: tenant owns their Stripe account, chargebacks hit their merchant balance, not platform's.

- [ ] TS2. **Recurring subscription charging for tenant memberships:** `membership.routes.ts` supports tier periods (`current_period_start`, `current_period_end`, `last_charge_at`) and enrolls cards via BlockChyp `enrollCard`, but there is NO scheduled worker that actually re-charges stored tokens when a period ends. Today a tenant must manually run a charge each cycle. Add a cron-driven renewal worker: for every active membership where `current_period_end <= now()` and `auto_renew = 1`, invoke `chargeToken(stored_token_id, tier_price)`, extend the period, and record `last_charge_*`. On failure: retry schedule (day 1, 3, 7), dunning email, suspend membership after final failure. Must work for both BlockChyp stored tokens AND (once TS1 lands) Stripe subscriptions.



## TENANT PROVISIONING HARDENING — 2026-04-10 (Forensic analysis)

Root-cause investigation after a `bizarreelectronics` signup on 2026-04-10 got stuck in `status='provisioning'` for hours until manual repair via `scripts/repair-tenant.ts`. Two parallel Explore agents traced the failure. Verdict: **Node 24 / better-sqlite3 Node-22 ABI crash** (libuv assertion `!(handle->flags & UV_HANDLE_CLOSING)`, exit code 3221226505) fired during STEP 3 of `provisionTenant()` — most likely inside `new Database(dbPath)` or the `bcrypt.hash()` worker-thread call. The native module abort killed the process instantly, so the `cleanup()` closure (defined locally inside `provisionTenant`) was never reached. The master row survived at `status='provisioning'`, the filesystem was left half-written, and the HTTP client got a TCP RST with no response body.

Critical gaps found in the current codebase:

- **`cleanupStaleProvisioningRecords()` exists but is never invoked.** Defined at `packages/server/src/services/tenant-provisioning.ts:348`. Grep confirms zero call sites. It would have recovered the stuck row on the next restart if it had been wired into startup.
- **No HTTP request / header / keep-alive timeouts.** `httpsServer.requestTimeout`, `.headersTimeout`, `.keepAliveTimeout` are all default (effectively infinite). A stalled provisioning request can hang indefinitely without abort.
- **Crash was invisible to `crash-log.json`.** Native-module aborts don't produce JavaScript exceptions, so `process.on('uncaughtException')` at `index.ts:1503` never fired and `recordCrash()` was never called. The only evidence of the failure was the stuck row itself.
- **`migrateAllTenants()` silently skips `provisioning` rows.** It queries `WHERE status = 'active'` (see `migrate-all-tenants.ts:45`), so stuck tenants fall through every startup without notice.
- **`cleanup()` is a local closure, not an event handler.** Closures die with the process. The design assumes the process stays alive; it has no recovery story for mid-flow crashes.

All items below MUST respect the project rule: **never delete tenant DB files.** Anything that would auto-`fs.unlinkSync` a tenant artifact is a non-starter.

### TPH — Tenant Provisioning Hardening










## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.

- [ ] SSW1. **First-login setup wizard gate:** on first login after signup, if `store_config.setup_completed` is `'true'` but a new `setup_wizard_completed` flag is missing (or `'false'`), show a full-screen modal wizard instead of the dashboard. Wizard collects all the fields currently buried in Settings → Store, Settings → Receipts, and Settings → Tax. Dismissal is only possible via "Complete setup" (all required fields filled) or "Skip for now" (sets a `setup_wizard_skipped_at` timestamp so we can nag on subsequent logins). After completion, set `setup_wizard_completed = 'true'`.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, phone, webhooks, backup config) → wizard skips entirely, user configures later in Settings
  The audit output should drive which fields appear in the wizard, in what order, and with what defaults.

- [ ] SSW4. **RepairDesk API typo compatibility reminder:** per `CLAUDE.md`, RepairDesk uses typo'd field names (`orgonization`, `refered_by`, `hostory`, `tittle`, `createdd_date`, `suplied`, `warrenty`). Any new import wizard code must preserve these exactly. Add a test that round-trips a fixture through the import to catch anyone who "fixes" a typo.

- [ ] SSW5. **Test plan for first-run wizard:** after SSW1-4 are implemented, add an E2E test that signs up a brand-new shop via `POST /api/v1/signup`, logs in, and asserts:
  - Wizard modal appears (not the dashboard)
  - Each required field blocks "Complete setup" when empty
  - "Complete setup" actually writes every field to `store_config` with the correct key names
  - Subsequent logins do NOT show the wizard
  - "Skip for now" sets the timestamp but re-shows the wizard on next login

## BRAND THEME — full accent-color audit

- [ ] BRAND1. **Unify accent colors across light and dark themes to match the Bizarre Electronics logo palette:** `bizarreelectronics.com` uses a cream + purple gradient. Our current Tailwind config uses generic indigo/blue/primary tokens (`primary-600`, `blue-500`, `indigo-500`) scattered across components. Audit every usage and replace with the brand palette:
  - Primary cream: `#FBF3DB` (background)
  - Primary magenta/purple: `#bc398f` (brand accent, matches logo rectangle + `League Spartan` headers on landing/signup)
  - Gradient option: cream-to-magenta linear gradient for hero CTAs (matches the logo's visual feel)
  - Existing `packages/web/src/components/shared/TrialBanner.tsx`, `LandingPage.tsx`, `SignupPage.tsx`, and the wizard `Step*` components already use `#FBF3DB` + `#bc398f` via inline styles — these are the reference.
  
  **Scope:**
  - Sweep `tailwind.config.js` — replace or extend `primary`, `brand`, and `accent` color definitions so `primary-600` etc. produce the brand tones in both light and dark modes
  - Walk every `packages/web/src/**/*.tsx` file and replace hardcoded `bg-blue-*`, `text-indigo-*`, `bg-primary-600` etc. that should use brand accents
  - Ensure dark mode has accessible contrast ratios against `#bc398f` — may need a slightly lighter shade for dark-mode backgrounds
  - Buttons, links, badges, focus rings, active-nav highlights, the Settings tab indicator, form input focus borders — all should use brand colors
  - Preserve semantic colors where they matter: green for success, red for destructive, yellow for warning, amber for trial expiry. These stay.
  
  **Not in scope:** printable receipts, invoice PDFs (those use their own per-tenant logo + color). Just the web UI.

## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-1. **JWT Rotation:** JWT secrets are validated on startup, but there is no mechanism to rotate secrets gracefully without invalidating all active sessions.
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).

### Agent 2: Database Integrity & Queries
- [ ] SA2-1. **Direct injection via object params:** In `tickets.routes.ts:1659`, `req.body.customer_id` is passed directly into a parameterized query. If `req.body` bypasses validation and `customer_id` is an object, `sqlite3` natively crashes when binding non-primitive types instead of returning a validation error.

### Agent 3: Input Validation & Mass Assignment

### Agent 4: Frontend XSS Vulnerabilities

### Agent 5: Backend API Endpoint Abuse

### Agent 6: Component Rendering & React State

### Agent 7: Background Jobs & Crons
- [ ] SA7-1. **Blocking sleep loops:** Modules like `reimport-notes.ts`, `myRepairAppImport.ts`, and `repairDeskImport.ts` rely on recursive or loop-bound async `setTimeout` sleeps. A crash aborts the entire queue without persistent job state recovery.

### Agent 8: Desktop/Electron App Constraints
- [ ] SA8-1. **Deep link validation:** The Electron app now implements a per-user installation without UAC, but the `setup` URL handlers lack strict deep-link origin validation, allowing potential arbitrary custom protocol abuse.

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt
- [ ] SA10-1. **Lingering Type Mismatches:** Use of `as any` casting is still present in webhook firing and invoice data wrapping hooks, diminishing Typescript's strict enforcement inside the event broadcast components.

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)

### 2. File Corruptions via Non-Atomic Writes

### 3. Synchronous CPU Event-Loop Locks

### 4. Cryptographic Defaults

### 5. SQLite Parameter Array Bounds Execution Halt 

### 6. Idempotency Skips in Financial Bridging

### 7. Global Socket Scope Leakage

### 8. Hardcoded Secret Entanglements 

### 9. Cookie Parsing Signing Exclusions

### 10. Floating Promises in Database Interfacing

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths

### 2. Missing Database Concurrency Locks

### 3. Server OOM via Unbounded Image Streams

### 4. Horizontal Privilege Escalation (IDOR)

### 5. Regular Expression Denial of Service (ReDoS)

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.

### 7. Global Socket Scopes via Offline Maps

### 8. Null-Routing on Background Schedulers

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
- [ ] D4-1. **Laggy State Transitions:** Across core components (`TicketNotes.tsx`, `TicketListPage.tsx`), React Query `useMutation` implementations strictly invalidate queries `onSuccess`. They entirely lack `onMutate` optimistic caching. Users endure a `~200-400ms` perceived lag upon clicking "Save" or dragging a Kanban card, frustrating power users compared to instantaneous modern apps.

### 2. Form Input Hindrances on Mobile/Touch

### 3. Flash of Skeleton Rows (Flicker)

### 4. Poor Error Boundary Granularity

### 5. Infinite Undo/Redo Voids
- [ ] D4-5. **No Recoverable Destructive Actions:** Modifying or deleting tickets/leads pops up a standard `toast.success`. There is no 5-second `Undo` queue array injected into the Toast mappings. Users who misclick a status change are forced to physically navigate backwards through UI pages to hunt down their mistake instead of clicking "Undo" natively via notification popups.

### 6. Modal Focus Traps (WCAG Violation)

### 7. WCAG "aria-label" Screen-Reader Blindness

### 8. FOUC (Flash of Unstyled Content) on Dark Mode

### 9. HCI Touch Target Ratios
- [ ] D4-9. **Fat-Finger Mobile Actions:** Numerous inline badges and interactive buttons (e.g., `px-1.5 py-0.5` inside Ticket notes and pagination) render to roughly `~16-20px` tall. This mathematically violates standard mobile HCI ratios (Minimum `44x44px`), guaranteeing extreme mis-click rates on phones deployed in the field.

### 10. Indefinite Stacking Toasts

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 1. Complete TalkBack Annihilation
- [ ] D5-1. **`contentDescription = null` Globals:** There are over 76+ instances across the Jetpack Compose Android app (`TicketCreateScreen`, `PosScreen`, `SettingsScreen`) where crucial interactive navigational `<Icon>` maps are explicitly set to `contentDescription = null`. This absolutely destroys accessibility, causing native Android TalkBack to loudly ignore critical buttons like "Edit", "Sync", and "Add", leaving visually impaired users entirely stranded.

### 2. Missing Compose List Keys (Jank)
- [ ] D5-2. **`LazyColumn` Recycle Drops:** Numerous native views map lists through `items(filters)` or generic arrays without supplying the explicit `key = { it.id }` parameter. Jetpack Compose defaults to using index positions as keys, causing massive native UI jitter (jank) and unnecessary recompositions whenever a new item is inserted or deleted from the synchronization layer.

### 3. Tactile Ripcords Unplugged
- [ ] D5-3. **Raw Clickable Ghosting:** Mobile UI cards utilize `.clickable(onClick = {})` without wrapping the component in native `<Card>` boundaries or defining hardware `indication = ripple()`. Android power users rely heavily on tactile visual ripples to confirm a tap. The UI feels unresponsive ("ghosted") as users tap buttons without visual acknowledgement until the network resolves.

### 4. Hardcoded Color Contrast Overrides
- [ ] D5-4. **Forced `Color.Gray` Ignorance:** There are ~30 instances spanning `InvoiceDetailScreen.kt` and `EmployeeListScreen.kt` physically hardcoding text or background layouts to explicit `color = Color.Gray` or `Color.White`. This directly bypasses Jetpack Compose's `MaterialTheme.colorScheme.onSurface` engines, forcing glaring white text to blindly paint over grey UI themes during dark-mode switches, turning features invisible.

### 5. Infinite Snackbar Queues
- [ ] D5-5. **Offline Spam Escalation:** When a user repeatedly smashes "Complete Payment" inside `CheckoutScreen.kt` on a broken Wi-Fi map, the `SnackbarHostState` queues the network error infinitely. Jetpack sequentially loads these native Snackbars for the duration of the timeout, forcing the user to wait a literal physical minute while 15 identical "Network error" snackbars rotate off the screen individually. While here, also check if the offline error will only show up for credit card processing - we are ok to accept cash without internet, just schedule it to be posted to server later.

### 6. Missing Contextual Search Actions
- [ ] D5-6. **Keyboard Enter Detachment:** While inputs map `KeyboardOptions(imeAction = ImeAction.Search)` in screens like `GlobalSearchScreen.kt`, the actual `KeyboardActions(onSearch = { execute() })` trigger bindings are frequently omitted. Users tap the magnifying glass strictly on their native keyboard, but nothing happens, forcing them to manually stretch their thumb up to hit the UI "Search" button.

### 7. Missing Pull-To-Refresh Sync Maps
- [ ] D5-7. **Trapped Offline States:** Dense synchronization arrays (`TicketListScreen.kt`) lack nested `PullRefreshIndicator` or `Modifier.pullRefresh` implementations. If the Room DB gets out of sync with the Web API and automated jobs fail, the technician has zero physical UI method to vertically "swipe down" to force an immediate refresh hook. They are forced to restart the entire Android app.

### 8. Viewport Edge Padding Overlaps
- [ ] D5-8. **Keyboard Splices:** Inconsistent application of `Modifier.imePadding()` mixed with hardcoded `padding(16.dp)` means lower-viewport Android inputs physically disappear beneath standard screen-rendered keyboards during chat/SMS loops instead of naturally shifting the view up to accommodate the hardware boundary.

## FUNCTIONALITY AUDIT - MOVED FROM functionalityaudit.md

# Functionality Audit

Scope: static audit of the BizarreCRM web/server codebase for user-visible usability bugs, disconnected buttons, TODO/stub behavior, and partially implemented enrichment features. This pass read `CLAUDE.md`, `README.md`, and used parallel code-review agents plus manual verification of the highest-risk findings.

## Executive Summary

- Highest risk area: public/customer-facing payment and messaging flows. Several buttons look live but either hit missing routes or mark payment state without a real provider checkout.
- Main staff-facing risk: settings and workflow controls are sometimes rendered as normal live controls even when metadata or code says the behavior is only planned.
- Most valuable quick wins: hide or badge incomplete controls, wire missing backend routes for customer-facing CTAs, and add navigation/entry points for pages/components that already exist.

## Medium Priority Findings

## Low Priority / Usability Findings

  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

- [ ] FA-L4. **Several enrichment components are present but appear unmounted:**

  Evidence:

  - Search results show `FinancingButton`, `InstallmentPlanWizard`, `QrReceiptCode`, and `CommissionPeriodLock` only in their own component files.

  User impact:

  The README advertises parts of these enrichment flows, but the components are not reachable from current pages, so users cannot discover or exercise them.

  Suggested fix:

  mount them into the relevant invoice/POS/team pages 

## Second Pass Additions

These items were found in a fresh second pass and are not duplicates of the findings above.

## Medium Priority Findings

- [ ] FA-M12. **POS photo-capture QR codes produce invalid links:**

  Evidence:

  - `packages/web/src/pages/unified-pos/SuccessScreen.tsx:127-128` builds QR URLs as `/photo-capture/:ticketId/:deviceId` without a token.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:9-10` requires `?t=...`.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:72` sends that token as the upload bearer token.
  - `packages/web/src/pages/photo-capture/PhotoCapturePage.tsx:86` immediately shows "Invalid Link" when the token is missing.

  User impact:

  Staff or customers scanning the QR code from the POS success screen cannot upload pre-condition photos.

  Suggested fix:

  Generate a scoped, short-lived photo-upload token on ticket creation and include it in the QR URL, or change the upload flow to use a server-side QR session that does not depend on a bearer token in the URL. We also want to make sure that we would first send a push to a phone logged into the same account, the scannable qr is a FALLBACK. We also want to make sure that people cant just spam the server with random secrets on this route - we dont want to have random images uploaded by bots. By the way, is it sanitized? should look into it as well.

- [ ] FA-M13. **Public Track by Ticket # search intentionally calls a token-protected endpoint with an invalid token:**

  Evidence:

  - `packages/web/src/pages/tracking/TrackingPage.tsx:207-226` sends ticket-number searches to `/api/v1/track/:orderId?token=no-token-use-phone`.
  - `packages/server/src/routes/tracking.routes.ts:41-46` rejects tokens shorter than the minimum valid tracking token length.
  - `packages/server/src/routes/tracking.routes.ts:109-125` requires the order ID and token to match the ticket.
  - `packages/web/src/pages/tracking/TrackingPage.tsx:234` catches that failure and tells the user to use phone lookup instead.

  User impact:

  The page offers a "Track by Ticket #" mode that is effectively guaranteed to fail unless the user already has a valid tracking link.

  Suggested fix:

  Either remove the ticket-number mode from the public form, or implement a safe order-ID lookup flow that pairs the ticket number with a second factor such as phone last four or email.

- [ ] FA-M15. **Marketing enrichment pages are present but not routed, and two have stale API contracts:**

  Evidence:

  - `packages/web/src/pages/marketing/CampaignsPage.tsx`, `SegmentsPage.tsx`, `NpsTrendPage.tsx`, and `ReferralsDashboard.tsx` exist, but search results show no imports/usages outside their own files.
  - `packages/web/src/App.tsx:266-316` registers the authenticated app routes and has no marketing, campaigns, segments, NPS, or referrals route.
  - `packages/web/src/pages/marketing/NpsTrendPage.tsx:37-54` calls `/reports/nps/trend` and expects `overall`, `monthly`, and `recent`.
  - `packages/server/src/routes/reports.routes.ts:2801-2834` exposes `/reports/nps-trend` and returns `trend` plus `current_nps`; `packages/web/src/api/endpoints.ts:475` also points to `/reports/nps-trend`.
  - `packages/web/src/pages/marketing/ReferralsDashboard.tsx:79` calls `/portal-enrich/referrals`, while `packages/server/src/index.ts:950-960` mounts portal enrichment at `/portal/api/v2` and `packages/server/src/routes/portal-enrich.routes.ts:857-860` only exposes customer referral-code minting.

  User impact:

  Marketing dashboards and campaigns are effectively hidden from the app. Even if someone wires the routes later, NPS and referral analytics will still silently show empty states instead of real data.

  Suggested fix:

  Add first-class marketing routes/navigation and align each page with the canonical API helpers. For referrals, add an authenticated analytics endpoint such as `/api/v1/crm/referrals` or `/api/v1/reports/referrals`.


## Medium Priority Findings

- [ ] FA-M25. **Lead pipeline Lost drop target cannot complete the lost workflow:**

  Evidence:

  - `packages/web/src/pages/leads/LeadPipelinePage.tsx:20` includes a visible `Lost` pipeline column/drop target.
  - `packages/web/src/pages/leads/LeadPipelinePage.tsx:205-208` intercepts `newStatus === 'lost'`, navigates to the lead detail page, and shows a toast saying to mark the lead lost there.

  User impact:

  Dragging a lead into Lost does not complete the workflow from the pipeline. Staff have to navigate away and repeat the status change elsewhere.

  Suggested fix:

  Add the lost-reason modal to the pipeline move flow, or remove the Lost drop target and make the required detail-page workflow explicit.

- [ ] FA-M26. **CRM referral and wallet-pass enrichment has no user path:**

  Evidence:

  - `packages/web/src/pages/customers/CustomerDetailPage.tsx:208-209` mounts health/LTV badges, and `packages/web/src/pages/customers/CustomerDetailPage.tsx:279` mounts the photo mementos wallet, but the customer header/actions around `packages/web/src/pages/customers/CustomerDetailPage.tsx:207-279` do not expose wallet-pass or referral actions.
  - `packages/web/src/api/endpoints.ts:925-927` exposes `walletPassUrl` and `mintReferralCode` helpers.
  - `packages/web/src/pages/portal/CustomerPortalPage.tsx:505-524` renders pay, receipt, and warranty actions but no loyalty/referral/wallet-pass block.

  User impact:

  The README-advertised referral code and wallet pass features are API-reachable but not discoverable by staff or customers.

  Suggested fix:

  Add customer-profile and/or portal actions for generating referral codes, copying share links, and opening/downloading wallet passes.

## Low Priority / Usability Findings

- [ ] FA-L8. **Refund reason picker exists but credit notes still use free text:**

  Evidence:

  - `packages/web/src/components/billing/RefundReasonPicker.tsx:2-3` describes a structured refund-reason selector, and `packages/web/src/components/billing/RefundReasonPicker.tsx:56-83` renders the code picker plus note field.
  - `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:521-569` renders the actual "Create Credit Note" modal with a plain `Reason` textarea.
  - `packages/web/src/pages/invoices/InvoiceDetailPage.tsx:124-125` submits only the free-text reason string.

  User impact:

  Refund/credit-note reasons remain inconsistent even though a canonical picker exists.

  Suggested fix:

  Mount `RefundReasonPicker` in the credit-note flow and pass both the selected code and note through the mutation payload.

## APRIL 14 2026 CODEBASE AUDIT ADDITIONS

Static audit scope: global deploy config, server authorization/business logic, reachable web UI, Electron management IPC, Android sync/storage/networking, and shared permission contracts. No source-code changes were made; these items capture follow-up work only.

## High Priority Findings


  Evidence:

  - `docker-compose.yml:7` maps `"443:443"` and `docker-compose.yml:16` sets `PORT=443`.
  - `packages/server/Dockerfile:84` says containerized runs should set `PORT=8443`, while `packages/server/Dockerfile:89` switches to `USER node` and `packages/server/Dockerfile:92` still exposes `443`.

  User impact:

  The default container path can fail at boot because a non-root Linux process cannot bind privileged port 443 without extra capabilities.

  Suggested fix:

  Align the container contract around an unprivileged internal port: set compose to `443:8443`, set `PORT=8443`, expose `8443`, and update any health checks or docs that still assume in-container 443.


  Evidence:

  - `packages/server/src/middleware/auth.ts:167` authorizes requests from the shared hardcoded `ROLE_PERMISSIONS[req.user.role]` map plus `users.permissions`.
  - `packages/server/src/routes/roles.routes.ts:228-236` reads the editable `role_permissions` matrix for display/update flows.
  - `packages/server/src/routes/roles.routes.ts:316-320` assigns roles by writing `user_custom_roles`, but the auth middleware never reads `user_custom_roles` or `role_permissions`.

  User impact:

  Admins can edit and assign custom roles that look real in the management UI but do not change route authorization. Staff may keep access they were supposed to lose, or lose access that the custom role appears to grant.

  Suggested fix:

  Resolve effective permissions in one server-side place: join the user to `user_custom_roles`/`role_permissions`, keep the default role fallback for legacy users, and align the permission key list with `@bizarre-crm/shared`.

- [ ] AUD-20260414-H3. **`/pos/checkout-with-ticket` can leave partial invoices/payments after checkout failure:**

  Evidence:

  - `packages/server/src/routes/pos.routes.ts:895` documents the route as creating ticket, invoice, and payment "in one transaction".
  - `packages/server/src/routes/pos.routes.ts:1043` inserts the ticket with an independent `await adb.run(...)`, and `packages/server/src/routes/pos.routes.ts:1471` / `packages/server/src/routes/pos.routes.ts:1490` independently insert payment rows later.
  - `packages/server/src/routes/pos.routes.ts:1508-1511` explicitly notes that a stock-deduction failure leaves the invoice intact and that a full wrapping transaction is out of scope.

  User impact:

  A checkout can create or update tickets, invoices, payments, and POS rows before a later stock/status write fails. Staff then see partially completed sales that require manual reconciliation or risky retries.

  Suggested fix:

  Split preflight validation from writes, then execute the ticket/invoice/payment/stock/status changes as a single atomic transaction, or route this workflow through the already-batched POS transaction path.

- [ ] AUD-20260414-H4. **Android release builds have certificate pinning enabled with placeholder pins:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:78` sets `ENABLE_CERT_PINNING` to `true`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:81` and `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:83` still contain `PRIMARY_LEAF_PIN_REPLACE_ME` and `BACKUP_LEAF_PIN_REPLACE_ME`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/RetrofitClient.kt:489-495` installs those pins for the production host and wildcard subdomains in non-debug builds.

  User impact:

  A release APK/AAB will fail closed for every production HTTPS request until real pins are configured, making login, sync, and POS workflows unusable.

  Suggested fix:

  Replace placeholder pins before release, add a backup pin, and add a build/CI guard that fails release builds when either placeholder string is still present.

## Medium Priority Findings


  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.

- [ ] AUD-20260414-M2. **Electron management root resolution checks the drive root instead of the trusted app anchor:**

  Evidence:

  - `packages/management/src/main/ipc/management-api.ts:85-90` says the resolved update script must sit under a trusted anchor.
  - `packages/management/src/main/ipc/management-api.ts:108` checks `isPathUnder(dir, path.parse(anchorRoot).root)`, which is the filesystem drive root, not the resolved app anchor.
  - `packages/management/src/main/ipc/service-control.ts:80` uses the same drive-root check in the service-control resolver.

  User impact:

  The resolver is weaker than its security comments claim. A marker-bearing ancestor on the same drive can be accepted as the project root, which increases the blast radius for update/service script redirection on compromised or unusual installs.

  Suggested fix:

  Compare candidate roots against the resolved trusted anchor or an explicit packaged `crm-source` directory, require the full project-root marker set in both resolvers, and add unit tests for sibling/ancestor marker rejection.

- [ ] AUD-20260414-M3. **Reachable web tables still clip on mobile instead of scrolling or collapsing:**

  Evidence:

  - `packages/web/src/pages/expenses/ExpensesPage.tsx:161-162` wraps a full-width table in `card overflow-hidden`.
  - `packages/web/src/pages/team/MyQueuePage.tsx:96-97` does the same for the queue table.
  - `packages/web/src/components/reports/ForecastChart.tsx:49` and `packages/web/src/components/reports/TechLeaderboard.tsx:65` render plain `w-full` tables inside report cards.

  User impact:

  On small screens, columns and action controls can be clipped rather than scrollable, especially in expenses, queue, and report widgets.

  Suggested fix:

  Wrap table surfaces in `overflow-x-auto` with explicit `min-w-*` table widths, or render card/list layouts below the mobile breakpoint for rows with actions.

- [ ] AUD-20260414-M4. **Android SQLCipher rollout has no upgrade path for existing plaintext databases:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:35-43` documents that pre-SQLCipher installs will crash on DB open with "file is not a database".
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:58` opens Room with `SupportOpenHelperFactory` immediately, and `packages/android/app/src/main/java/com/bizarreelectronics/crm/di/DatabaseModule.kt:66` only adds schema migrations.

  User impact:

  Users upgrading from a build that created an unencrypted Room database can hit an app-start crash before they can re-sync or log out cleanly.

  Suggested fix:

  Ship a one-shot migration path: detect plaintext DBs, either `sqlcipher_export()` them into an encrypted DB or safely quarantine/wipe and force a full server re-sync with clear user messaging.

- [ ] AUD-20260414-M5. **Android dead-letter sync failures have persistence but no user-facing recovery path:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/dao/SyncQueueDao.kt:21-22` still has a `TODO(UI)` to surface dead-letter entries.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/dao/SyncQueueDao.kt:78-86` exposes dead-letter listing/count queries.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/components/SyncStatusBadge.kt:45-61` only renders pending sync count and "unsynced" state, not dead-letter failures.

  User impact:

  After retries are exhausted, a failed offline action can disappear from the normal sync badge even though it is still stored as `dead_letter`. Technicians have no visible retry/discard workflow.

  Suggested fix:

  Add a "Failed Syncs" settings screen or dashboard panel backed by `observeDeadLetterEntries()`, show dead-letter counts in the sync badge, and expose retry/discard actions using `resurrectDeadLetter()`.

## Low Priority / Audit Hygiene Findings

- [ ] AUD-20260414-L1. **Room schema history is missing `3.json` while the database is at version 4:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/db/BizarreDatabase.kt:36-37` declares Room `version = 4` with `exportSchema = true`.
  - `packages/android/app/build.gradle.kts:115` exports schemas to `app/schemas`.
  - The checked-in schema directory contains `1.json`, `2.json`, and `4.json`, but not `3.json`, under `packages/android/app/schemas/com.bizarreelectronics.crm.data.local.db.BizarreDatabase/`.

  User impact:

  Migration tests and reviewers cannot verify the exact v3 schema that `MIGRATION_3_4` expects, which makes future migration work more fragile.

  Suggested fix:

  Regenerate and commit `3.json` from the matching v3 entity state if possible. If not, document the gap and add explicit migration tests from `2 -> 3 -> 4` and fresh `4` creation.

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers

- [ ] AND-20260414-H1. **Android shortcuts, App Actions, and the Quick Ticket tile resolve routes but never navigate:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:58-59` stores `pendingDeepLink`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:76` assigns `pendingDeepLink = resolveDeepLink(intent)`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:98-103` creates `AppNavGraph(...)` without passing the pending route.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:109-116` repeats the same issue for `onNewIntent()` and leaves a TODO to push the route into navigation later.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:151-182` allows `ticket/new`, `customer/new`, and `scan`.
  - `packages/android/app/src/main/res/xml/shortcuts.xml:24-59` advertises those same launcher shortcut routes.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/QuickTicketTileService.kt:32-37` launches `MainActivity` with `ACTION_NEW_TICKET_FROM_TILE`.

  User impact:

  Long-press shortcuts, Google Assistant actions, external deep links, and the Quick Settings tile can all land on the dashboard/login instead of opening New Ticket, New Customer, or Scanner.

  Suggested fix:

  Add a navigation handoff that `AppNavGraph` can observe, map `ticket/new` to `Screen.TicketCreate.route`, `customer/new` to `Screen.CustomerCreate.route`, and `scan` to `Screen.Scanner.route`, and queue the route through login/biometric unlock when needed.

- [ ] AND-20260414-H2. **FCM push notification tap targets are written into extras that the app never consumes:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/FcmService.kt:92-100` puts `navigate_to` and `entity_id` extras on the notification `Intent`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/MainActivity.kt:151-168` only resolves URI deep links and the quick-ticket tile action; it does not inspect `navigate_to` or `entity_id`.
  - Project search found `navigate_to` only in `FcmService.kt`, so there is no downstream consumer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/service/FcmService.kt:41-44` whitelists many entity types, but `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:458-466` only routes in-app notification-list taps for `ticket` and `invoice`.

  User impact:

  Tapping a push notification can open the app without opening the ticket, invoice, customer, SMS thread, lead, appointment, or other referenced record.

  Suggested fix:

  Normalize FCM extras into the same route bus used for external deep links. Also expand `NotificationListScreen` routing for supported entities or explicitly disable/list non-navigable notification rows.

- [ ] AND-20260414-H3. **Ticket "Convert to Invoice" succeeds but the invoice navigation callback is not wired:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:222-235` calls the conversion API and stores `convertedInvoiceId`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:340-345` calls `onNavigateToInvoice(invoiceId)` when conversion succeeds.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:308-315` defaults `onNavigateToInvoice` to a no-op.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:307-315` creates `TicketDetailScreen` without passing an invoice navigation callback.

  User impact:

  A technician can convert a ticket, see "Invoice created", and remain stranded on the ticket with no direct path to review or collect payment on the newly created invoice.

  Suggested fix:

  Pass `onNavigateToInvoice = { id -> navController.navigate(Screen.InvoiceDetail.createRoute(id)) }` from the ticket-detail route and consider adding a snackbar action for the same destination.

- [ ] AND-20260414-H4. **Android checkout is unreachable and would read the wrong argument types if linked:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:74-79` defines `Screen.Checkout.createRoute(...)`.
  - Project search found no call sites for `Screen.Checkout.createRoute(...)` or any navigation into `Screen.Checkout`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:367-376` declares the checkout composable but does not pass the extracted `ticketId`, `total`, or `customerName` into the screen.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/pos/CheckoutScreen.kt:86-90` reads `ticketId` with `savedStateHandle.get<Long>("ticketId")`, while the route has no typed `navArgument`, so path args arrive as strings.

  User impact:

  The payment screen is effectively unavailable in normal Android workflows. If a future button links to it as-is, checkout can initialize with ticket `0`, a blank customer, and a `$0.00` total or crash on an argument type cast.

  Suggested fix:

  Route ticket/invoice/POS payment actions into checkout, declare `navArgument("ticketId") { type = NavType.LongType }` and typed args for total/customer name, or pass resolved values through a shared state object.

- [ ] AND-20260414-H5. **Creating a customer offline and then creating a ticket for that customer can sync with a dead temp customer id:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketCreateScreen.kt:379-423` lets the ticket wizard create and select a new customer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/CustomerRepository.kt:95-143` returns a negative temp customer id when offline and queues `customer/create`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketCreateScreen.kt:786-790` builds `CreateTicketRequest(customerId = s.selectedCustomer.id, ...)` from that selected customer.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/TicketRepository.kt:95-117` queues the ticket create payload unchanged when offline.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:381-389` reconciles a temp customer by inserting the real customer and deleting the temp row, but does not rewrite queued ticket payloads or repoint ticket `customer_id` values.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:287-295` later posts the queued ticket request exactly as stored.

  User impact:

  A common field workflow, new customer plus new repair while offline, can later POST a ticket with a negative `customerId`, fail server validation, and fall into the dead-letter path.

  Suggested fix:

  Persist a temp-to-server id map during customer reconciliation, rewrite pending queue payloads that reference the temp customer id, and repoint local tickets/leads/invoices/estimates before deleting the temp customer row.

- [ ] AND-20260414-H6. **Offline lead, estimate, and expense creates are sent to the server without reconciling the local temp rows:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/LeadRepository.kt:78-103`, `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/EstimateRepository.kt:74-99`, and `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/ExpenseRepository.kt:79-102` create offline rows using `-System.currentTimeMillis()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/local/prefs/OfflineIdGenerator.kt:10-25` documents why this pattern is collision-prone and why the shared generator exists.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/sync/SyncManager.kt:442-477` dispatches queued lead/estimate/expense creates by calling the API, but never replaces the negative local row with the server id or deletes the temp row.

  User impact:

  Offline-created leads, estimates, and expenses can remain as stale negative-id rows after sync, then duplicate when the next server refresh downloads the canonical server record. Any later edit/delete against the negative id will hit the wrong endpoint path.

  Suggested fix:

  Move these repositories to `OfflineIdGenerator.nextTempId()` and add reconciliation logic like tickets/inventory: insert the server entity, repoint children if needed, delete the temp row, and treat create conflicts idempotently.

## Medium Priority / Android UX and Navigation Gaps

- [ ] AND-20260414-M1. **Ticket photo upload exists but is not reachable from ticket detail:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:120-123` defines a ticket photo upload screen.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:86-90` posts selected images to `uploadTicketPhotos(...)`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:49-129` defines the route set without a photo-capture route.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:871-900` only displays existing photos; there is no add-photo action.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/camera/PhotoCaptureScreen.kt:248` still tells the user live camera capture is "coming soon".

  User impact:

  Technicians can view ticket photos already returned by the API, but cannot attach new repair photos from the Android ticket screen. The "camera" workflow is effectively gallery-only and orphaned.

  Suggested fix:

  Add a `tickets/{id}/photos` route, expose an Add Photo action on ticket detail, and either wire CameraX capture or rename the current workflow to "Pick From Gallery" until real camera capture lands.

- [ ] AND-20260414-M2. **Inventory item creation is registered in navigation but no inventory UI opens it:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:597-605` registers `InventoryCreateScreen`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/inventory/InventoryListScreen.kt:180-190` only exposes scan and refresh actions in the inventory top bar.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:405-421` wires inventory list callbacks for item click, barcode scan, and barcode lookup, but no create callback.

  User impact:

  Users can browse and edit existing inventory, but cannot add a new item from the Inventory screen even though a create screen exists.

  Suggested fix:

  Add an `onCreateClick` callback to `InventoryListScreen`, show an Add action/FAB, and navigate to `Screen.InventoryCreate.route`.

- [ ] AND-20260414-M3. **The Android profile/password/PIN screen is orphaned:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/ProfileScreen.kt:96-132` implements change-password and change-PIN calls.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/ProfileScreen.kt:170-223` defines the actual `ProfileScreen` UI.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:640-653` lists the More menu entries without Profile.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/settings/SettingsScreen.kt:151-296` shows server info, signed-in user info, sync, device preferences, and sign out, but no profile/password/PIN entry.

  User impact:

  Users cannot change password or PIN from the Android app despite the screen and API hooks existing.

  Suggested fix:

  Add a `Screen.Profile` route, link it from Settings or the signed-in user card, and wire a back button into the profile screen.

- [ ] AND-20260414-M4. **SMS templates are routed but have no launcher and no compose-screen consumer:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:128` defines `Screen.SmsTemplates`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/navigation/AppNavGraph.kt:616-623` writes the selected template body into `previousBackStackEntry.savedStateHandle["sms_template_body"]`.
  - Project search found `sms_template_body` only in `AppNavGraph.kt`; `SmsThreadScreen` never reads it.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/communications/SmsThreadScreen.kt:200-218` top-bar actions include flag, pin, and refresh, but no template picker.

  User impact:

  SMS templates are loaded by a real screen, but users cannot get to that screen from the SMS composer and selected templates would not populate the message field anyway.

  Suggested fix:

  Add a template action in `SmsThreadScreen`, navigate to `Screen.SmsTemplates.route`, and collect the returned `sms_template_body` into `messageText`.

- [ ] AND-20260414-M6. **Ticket star is a visible top-bar action with no backend behavior:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:297-300` only sets `actionMessage = "Star feature coming soon"`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:455-461` always renders the star icon button in the ticket-detail top bar.

  User impact:

  Users can tap a highly visible ticket affordance and receive a "coming soon" message instead of the ticket being starred.

  Suggested fix:

  Either implement the star endpoint/repository path or remove the button until the server supports it.

- [ ] AND-20260414-M7. **Estimate delete asks for destructive confirmation and then does nothing:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:177-196` shows a "Delete Estimate" confirmation dialog.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:218-246` exposes Delete from the overflow menu.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/estimates/EstimateDetailScreen.kt:120-128` sets "Delete not supported yet" instead of deleting.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote/api/EstimateApi.kt:30-31` already declares `DELETE estimates/{id}`.

  User impact:

  Users are asked to confirm an irreversible delete, but after confirmation the estimate remains and the app says deletion is unsupported.

  Suggested fix:

  Add `EstimateRepository.deleteEstimate(...)`, wire it to `EstimateApi.deleteEstimate(...)`, update/delete the local Room row, and navigate back or refresh after success.

- [ ] AND-20260414-M8. **Invoice payment and void actions leave cached invoice status/totals stale:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:115-130` records payment and then calls only `loadOnlineDetails()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:140-149` voids an invoice and then calls only `loadOnlineDetails()`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/invoices/InvoiceDetailScreen.kt:95-111` shows that `loadOnlineDetails()` refreshes line items/payments but does not refresh or write the `InvoiceEntity`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/repository/InvoiceRepository.kt:95-119` contains the detail-to-entity refresh path that would update status, amount paid, and amount due.

  User impact:

  After recording a payment or voiding an invoice, the detail screen and invoice list can continue showing the old amount due/status until a separate refresh happens.

  Suggested fix:

  After payment/void success, refresh the invoice entity through the repository or update the local `InvoiceEntity` from the returned server detail before closing the dialog.

- [ ] AND-20260414-M9. **Ticket detail bottom bar is likely to overflow on phone widths:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:473-582` places five labeled `TextButton`s in one `BottomAppBar` row: Status, Call, Note, SMS, and Print.
  - The row uses `Arrangement.SpaceEvenly` with fixed horizontal padding and no overflow menu, horizontal scroll, or compact icon-only mode.

  User impact:

  On narrow phones or larger accessibility font sizes, the action row can clip labels, push actions off screen, or create difficult touch targets.

  Suggested fix:

  Collapse secondary actions into an overflow menu, use icon-only actions with tooltips/content descriptions, or switch to an adaptive bottom action layout at compact width.

## Low Priority / Android Polish

- [ ] AND-20260414-L1. **Ticket Print is always enabled and builds a browser URL from raw local server settings:**

  Evidence:

  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:87` reads `authPreferences.serverUrl ?: ""`.
  - `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/tickets/TicketDetailScreen.kt:567-575` always enables Print and launches `"$serverUrl/print/ticket/$ticketId?size=letter"`.

  User impact:

  If the server URL is missing, stale, or the device is offline, tapping Print launches an invalid browser intent instead of giving a clear in-app message.

  Suggested fix:
  Allow the app to build receipts, same as the server, if offline.


## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory

- [ ] PROD1. **Confirm public repo target + license decision:** note GitHub org/user that will host, and chosen license (MIT/Apache-2.0/AGPL/proprietary). Blocks first commit.

- [ ] PROD2. **Identify default branch & current commit hash:** likely `main`. Record before publish so we can verify what flipped public.

- [x] ~~PROD3. **History depth audit (post `git init`):**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD4. **List + prune branches before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD5. **List + prune tags before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD6. **Drop / commit stashes:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD7. **Submodule check:**~~ — migrated to DONETODOS 2026-04-16.

### Phase 1 — Secrets sweep (post-init verification)

- [x] ~~PROD8. **Untrack any DB/WAL/SHM files:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD9. **Untrack APK/AAB:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD10. **Untrack build output:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD11. **Cross-reference env vars vs `.env.example`:**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD12. **DECISION: Default PIN `1234` policy.** Hardcoded at `auth.routes.ts:436` + `tenant-provisioning.ts:278`. Three options: (a) random PIN shown once at provisioning, (b) keep `1234` + add `pin_set` flag mirroring `password_set` for forced first-use change, (c) document loudly + accept. Recommendation: (b) for consistency.

### Phase 2 — JWT, sessions, auth hardening

- [x] ~~PROD13. **VERIFY refresh token deleted from `sessions` on logout:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD14. **VERIFY 2FA server-side enforcement:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD15. **VERIFY rate limiting wired on `/auth/forgot-password` + `/signup`:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD16. **VERIFY admin session revocation UI exists:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD17. **Spot-check `requireAuth` on every endpoint of 5 routes:**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD18. **Grep for routes querying by `id` alone w/o tenant scope:** any `WHERE id = ?` without `AND tenant_id = ?` (or equivalent tenant-DB scoping) is a cross-tenant read risk.

### Phase 3 — Input validation & injection

- [ ] PROD19. **Hunt SQL injection via template-string interpolation:** grep `db.prepare(\`...${...}...\`)` patterns where the interpolated value reaches the SQL string. Convert to `?` placeholders.

- [ ] PROD20. **Audit `db.exec(...)` calls for dynamic input:** `exec` cannot use parameters. Should never receive user data.

- [ ] PROD21. **Deep-audit dynamic-WHERE routes:** `search.routes.ts`, `import.routes.ts`, `reports.routes.ts`, `customers.routes.ts` bulk ops. These build dynamic WHERE clauses and are highest injection risk.

- [ ] PROD22. **Confirm validation library in use (zod/joi/express-validator):** if absent, flag for user. Required for Phase 3.2 schema validation.

- [ ] PROD23. **Spot-check 3 high-risk routes for `req.body` schema validation:** signup, billing, settings.

- [ ] PROD24. **VERIFY multer `limits.fileSize` set in every upload route.**

- [ ] PROD25. **VERIFY uploaded files served via controlled route (not raw filesystem path).**

- [ ] PROD26. **Audit `dangerouslySetInnerHTML` usage in `packages/web/src`:** justify each, sanitize with DOMPurify if rendering user-supplied HTML (notes, descriptions).

- [ ] PROD27. **Email/SMS templates escape variables before substitution:** confirm template engine escapes interpolated values.

- [ ] PROD28. **Path traversal grep:** `path.join(... req.` and `fs.readFile(... req.` — any user input in filesystem path needs `path.basename()` or strict allowlist.

- [ ] PROD29. **SSRF audit on URL-fetching code:** `services/catalogScraper.ts`, `services/webhooks.ts`, `services/githubUpdater.ts`. Verify (a) no requests to private IP ranges (10/8, 172.16/12, 192.168/16, 127/8, 169.254/16, ::1, fc00::/7), (b) DNS rebinding protection (resolve once, validate IP, then connect to resolved IP), (c) timeout on every outbound request.

- [ ] PROD30. **Open-redirect guard on `redirect`/`next`/`returnUrl` params:** validate same-origin or allowlist.

### Phase 4 — Transport, headers, CORS

- [ ] PROD31. **Force HTTPS in prod config:** self-signed cert in `packages/server/certs/` is dev-only. Production must use real cert (Cloudflare, Let's Encrypt, commercial). Document in README.

- [ ] PROD32. **HSTS header:** `max-age=15552000; includeSubDomains`. No `preload` unless user wants to register.

- [ ] PROD33. **Secure cookies:** `Secure`, `HttpOnly`, `SameSite=Lax|Strict` on all session/auth cookies.

- [ ] PROD34. **VERIFY CSP config in `helmet({...})` block (`index.ts`):** `default-src 'self'`, no `unsafe-inline` for scripts in production build.

- [ ] PROD35. **CORS allowlist not `*` in production:** `https://{tenant}.{BASE_DOMAIN}` and master domain only.

- [ ] PROD36. **`credentials: true` only paired with explicit origins.**

- [ ] PROD37. **VERIFY unauthenticated WS upgrade rejected (401/close):** not silently ignored.

- [ ] PROD38. **VERIFY Stripe webhook signature verified before processing:** `STRIPE_WEBHOOK_SECRET`.

- [ ] PROD39. **VERIFY Vonage webhook JWT signature verified.**

- [ ] PROD40. **VERIFY BlockChyp webhook signature scheme.**

- [ ] PROD41. **VERIFY GitHub webhook HMAC (if `githubUpdater` accepts pushes).**

### Phase 5 — Multi-tenant isolation

- [ ] PROD42. **Confirm per-tenant SQLite isolation:** each tenant has own file under `packages/server/data/tenants/`; queries cannot cross tenants.

- [ ] PROD43. **`tenantResolver` fails closed:** unresolved tenant → request rejected, NOT silent fallthrough to default.

- [ ] PROD44. **Super-admin endpoints gated by separate auth check:** `super-admin.routes.ts` + `master-admin.routes.ts` use distinct check from regular `requireAuth`.

- [ ] PROD45. **Tenant code cannot write to master DB:** confirm tenant-scoped DB connection has no master DB handle.

- [ ] PROD46. **Master DB backups encrypted with `BACKUP_ENCRYPTION_KEY`.**

- [ ] PROD47. **Cross-tenant ID guessing audit:** if ticket/invoice IDs are sequential ints, every endpoint must verify ownership before returning.

- [ ] PROD48. **Switch public-facing IDs (portal, payment links) to UUIDs/random strings if not already.**

### Phase 6 — Logging, monitoring, errors

- [ ] PROD49. **VERIFY no accidental body logging:** grep `console\.(log|info)\(.*req\.body` across route handlers.

- [ ] PROD50. **VERIFY `services/crashTracker.ts` does NOT snapshot request bodies on crash.**

- [ ] PROD51. **VERIFY 403 vs 404 indistinguishable for non-owned resources:** fetching another tenant's ticket → 404, not 403 (prevents enumeration).

- [ ] PROD52. **Correlation IDs:** every request gets a UUID logged so support can match user-reported error ID to log entry.

- [ ] PROD53. **PII masking in non-debug logs:** customer phone, email, address masked or omitted.

### Phase 7 — Backups, data, recovery

- [ ] PROD54. **`services/backup.ts` uses `BACKUP_ENCRYPTION_KEY` (or fail-closed in prod):** fallback to `JWT_SECRET` w/ one-time warning per `.env.example`. Production must fail-closed if neither set.

- [ ] PROD55. **Only `.db.enc` artifacts in backup_path:** plaintext `.db` should never leak there.

- [ ] PROD56. **Retention policy via `services/retentionSweeper.ts`:** confirm sane defaults (e.g. 7 daily + 4 weekly + 12 monthly).

- [ ] PROD57. **One-page restore drill in README/docs:** stop server → decrypt backup → copy to `data/` → start. User runs once before launch to confirm.

- [ ] PROD58. **Per-tenant "download all my data" capability:** GDPR/CCPA basics.

- [ ] PROD59. **"Delete tenant" capability (admin-only, multi-step confirm):** wipes tenant DB. Per memory rule: this is the ONE allowed deletion path — explicit user-initiated termination only.

### Phase 8 — Dependencies & supply chain

- [ ] PROD60. **`npm audit --omit=dev` in `bizarre-crm/`, `packages/server/`, `packages/web/`:** fix `high` + `critical`. Document `moderate` if not fixable.

- [ ] PROD61. **`npm outdated` review:** case-by-case, do NOT bump React/Vite majors days before launch.

- [x] ~~PROD62. **`package-lock.json` committed at every package root.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD63. **No `node_modules/` tracked.**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD64. **Dependency typo-squat audit:** read top-level `dependencies` in each `package.json`. Flag unknown packages, look for typo-squats (`reqeust`, `loadsh`, etc.).

- [ ] PROD65. **`package.json` `repository`/`bugs`/`homepage` fields:** point to right URL or absent.

- [ ] PROD66. **Strip local absolute paths from `scripts` blocks:** no `C:\Users\...`.

- [ ] PROD67. **No sketchy `postinstall` scripts.**

### Phase 9 — Build & deploy hygiene

- [ ] PROD68. **Confirm `npm run build` in `packages/web/` produces `dist/` and `index.ts` serves it.**

- [ ] PROD69. **Source maps decision:** if shipped, intentional. Fine for OSS but document.

- [x] ~~PROD70. **`dist/` not in tree.**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD71. **Single source of truth for `NODE_ENV=production` at deploy:** mention in README.

- [ ] PROD72. **Audit `if (process.env.NODE_ENV === 'development')` blocks:** confirm none expose debug routes / dev-only endpoints / relaxed auth in prod.

- [ ] PROD73. **VERIFY `repair-tenant.ts` does no DB deletion.**

- [ ] PROD74. **Migrations idempotent + auto-run on boot:** re-running a completed migration must be safe.

- [ ] PROD75. **No migration deletes data without a guard.**

- [ ] PROD76. **Migration order deterministic:** numbered, no naming collisions. (See Phase 99.3 — `049_*` and `050_*` prefix collisions exist; verify `migrate.ts` handles.)

- [ ] PROD77. **VERIFY `scripts/reset-database.sh` + `scripts/clear-imported-data.sh` have `NODE_ENV` guard if they exist.**

### Phase 10 — Repo polish for public release

- [ ] PROD78. **Update `bizarre-crm/README.md` for public audience:** tagline, architecture overview (1 paragraph), setup steps, env vars (link `.env.example`), default credentials / first-boot, license, contributing, disclaimers (alpha software, self-host at your own risk).

- [ ] PROD79. **Decide repo-root README:** mirror or simplified.

- [ ] PROD80. **Single primary `LICENSE` at repo root with chosen license.** Ask user which (MIT/Apache-2.0/AGPL/proprietary).

- [ ] PROD81. **`LICENSES.md` lists transitive third-party license obligations.**

- [ ] PROD82. **Manually read each `docs/*.md` before publish:** `product-overview.md`, `developer-guide.md`, `tech-stack-and-security.md`, `android-field-app.md`, `android-operational-features-audit.md`, `operator-guide.md`. Strip internal IPs, SSH hosts, customer data, personal email/phone, derogatory competitor mentions. Grep already clean for `pavel`/`bizarre electronics`/IPs — manual read catches informal notes.

- [x] ~~PROD83. **Verify scratch markdowns excluded:**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD84. **Repo-root markdown decision:** `Repair_Shop_CRM_UIUX_Audit_Instructions.md`, `UsersPavel.claudeplansmighty-...md`, `antigravity.md` — default untrack.

- [ ] PROD85. **Hidden personal data sweep:** owner real name, personal email/phone, home address, store address, RepairDesk account ID. Replace with placeholders or remove.

- [ ] PROD86. **`pavel` / `bizarre` / owner-username intentionality audit:** confirm each occurrence intentional, not accidental.

- [ ] PROD87. **Internal-IP scrub:** `grep -E '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'`. Replace any ips with the .env value for domain situations or make sure localhost works for non-public self hosted>`.

- [ ] PROD88. **TODO/FIXME/HACK/XXX inventory:** list all. Decide per-item: leave / inline-fix / move to TODO.md. Don't bulk-fix — many are legit future work.

- [ ] PROD89. **Strip personal-opinion comments about people/customers/competitors.**

- [ ] PROD90. **Confirm no JSON dump of real customer data in `seed.ts`/`sampleData.ts`/fixtures.**

- [ ] PROD91. **Confirm `services/sampleData.ts` generates fake data, not real exports.**

- [x] ~~PROD92. **Create `SECURITY.md` at repo root with private disclosure email.**~~ — migrated to DONETODOS 2026-04-16.

- [ ] PROD93. **Verify `.github/ISSUE_TEMPLATE/*.md` not blocked by `*.md` rule:** `git check-ignore -v .github/ISSUE_TEMPLATE/bug_report.md` before assuming included.

- [ ] PROD94. **Optional: `CODE_OF_CONDUCT.md` for community engagement.**

- [ ] PROD95. **CI workflows in `.github/workflows/`:** no inline secrets, use repo secrets.

- [ ] PROD96. **Minimal CI:** install + lint + typecheck + build. NO deploy workflows pointing to user's prod server.

### Phase 11 — Operational

- [ ] PROD97. **Read `ecosystem.config.js` (PM2) — confirm no local-only paths.**

- [ ] PROD98. **Graceful shutdown handlers in `index.ts`:** close DB, drain WS, finish in-flight requests on SIGTERM/SIGINT.

- [ ] PROD99. **Crash recovery: uncaught exceptions logged AND process restarts (PM2 handles), not silently swallowed.** Confirm `middleware/crashResiliency.ts` + `services/crashTracker.ts`.

- [ ] PROD100. **`/healthz` returns 200 quickly without DB heavy work** (LB probe-suitable).

- [ ] PROD101. **`/readyz` (if present) checks DB connectivity.**

- [ ] PROD102. **Per-tenant upload quota enforced BEFORE write (not after):** per migration `085_upload_quotas.sql`.

- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.

- [ ] PROD104. **Outbound kill-switch env var (e.g. `DISABLE_OUTBOUND_EMAIL=true`) for emergencies.**

- [ ] PROD105. **SMS sender ID / from-email per-tenant config, not global.**

### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).

- [ ] PROD108. **`npm run build` succeeds in `packages/web/`.**

- [ ] PROD109. **Server starts cleanly with fresh `.env`** (only `JWT_SECRET`, `JWT_REFRESH_SECRET`, `PORT`).

- [ ] PROD110. **Manual smoke: login as default admin → change password → 2FA flow.**

- [ ] PROD111. **Manual smoke: signup new tenant → tenant DB created → data isolation verified.**

- [ ] PROD112. **Backup → restore on scratch dir → data round-trips.**

- [ ] PROD113. **`git status` clean, `git log` reviewed for embarrassing commit messages.**

- [ ] PROD114. **Push to PRIVATE GitHub repo first → verify CI passes → no secret-scanning alerts → THEN flip public.**

- [ ] PROD115. **Post-publish: subscribe to GitHub secret scanning + Dependabot alerts.**

### Phase 99 — Findings (open decisions/risks from executor)

- [ ] PROD116. **Migration prefix collision risk (Phase 99.3):** three files share `049_` (`049_customer_is_active.sql`, `049_po_status_workflow.sql`, `049_sms_scheduled_and_archival.sql`) and two share `050_`. Verify `db/migrate.ts` sorts by filename + handles duplicates gracefully (no non-deterministic order, no silent skips).

- [ ] PROD117. **`scripts/full-import.ts` + `scripts/reimport-notes.ts` are shop-specific (Phase 99.4):** one-time RepairDesk import for Bizarre Electronics. Move to `scripts/archive/` or document as single-use migration tools. `ADMIN_PASSWORD` env var already added.

## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

- [ ] SEC-C1. **Wrap every async route handler in `asyncHandler`** so thrown `AppError` reaches `next(err)` and `errorHandler` returns 4xx/5xx. Currently `POST /api/v1/invoices` and any async handler that throws in `pos.routes.ts`, `tickets.routes.ts`, `customers.routes.ts`, `refunds.routes.ts`, `giftCards.routes.ts` triggers `index.ts:2632` `unhandledRejection` → full server SIGTERM (platform DoS by any authenticated user). Alternative: make `crashResiliency.ts` whitelist `AppError` as non-fatal. Both recommended. `packages/server/src/routes/invoices.routes.ts:201-210`, `packages/server/src/index.ts:2632`. **Verified live — reproduced 3× against sandbox.** (LIVE-02 / LIVE-09)
- [ ] SEC-C2. **Call `stripe.refunds.create` / `blockchyp.reverse` before flipping refund to `completed`** and decrementing `invoices.amount_paid`. Current approve handler is DB-only; card never credited. Add `processor_refund_id` column; block flip on processor failure. `packages/server/src/routes/refunds.routes.ts:148-251`. (PAY-13)
- [ ] SEC-C3. **Wrap Stripe webhook `INSERT OR IGNORE stripe_webhook_events` + tenant side-effects in a single `masterDb.transaction()`.** Crash between claim and tenant update leaves event marked-processed while tenant stays on old plan — Stripe retries short-circuit (`existing→return`). Two-phase alternative: `status='received'` → `status='applied'`, startup scanner re-drives `received`. `packages/server/src/services/stripe.ts:546-770`. (PAY-09)
- [ ] SEC-C4. **Reject `POST /invoices/:id/payments` when `invoice.status='paid' AND amount_due=0`.** Current code books overpayment directly to `store_credits` (money-theft cover: pay $1000 vs $1 paid invoice → $999 store credit minted, spendable via `/credits/:customerId/use`). Alternative: require explicit `allow_overpayment=true` admin flag and book to tipping ledger, not store credit. `packages/server/src/routes/invoices.routes.ts:377-587`. (LOGIC-005)
- [ ] SEC-C5. **Migrate `better-sqlite3` → SQLCipher fork.** Add `PRAGMA key` with PBKDF2-SHA512-derived (≥100k iters) key from dedicated `DB_ENCRYPTION_KEY` env var — NOT `JWT_SECRET`. Migrate existing DBs via `sqlcipher_export`. Tenant DBs + master.db + WAL sidecars currently plaintext; GDPR Art. 32 requires at-rest encryption. `packages/server/src/db/connection.ts:11`, `master-connection.ts:19`, `tenant-pool.ts:99`. (P3-PII-01)
- [ ] SEC-C6. **Stand up minimum viable test suite + CI.** Vitest unit for bcrypt/JWT/TOTP; Supertest integration for `/auth/login`, `/auth/refresh`, `/signup`, Stripe webhook, BlockChyp webhook, refund approve; Playwright smoke for login→2FA→POS→refund→logout. Add `.github/workflows/ci.yml`. The `security-tests*.sh` referenced in CLAUDE.md do not exist on disk. Zero tests today. (TEST-ZERO)

### HIGH — auth

- [ ] SEC-H1. **`/reset-password` UPDATE+DELETE in single `adb.transaction()`** (pattern exists in `/change-password` L1547-1556). `packages/server/src/routes/auth.routes.ts:1221-1225`. (P3-AUTH-01)
- [ ] SEC-H2. **Refresh-token reuse detection:** `jti` on session row, rotate + kill-family on replay. `auth.routes.ts:837-922`. (P3-AUTH-03)
- [ ] SEC-H3. **2FA enroll-over bypass:** `/login/2fa-setup` must refuse when `totp_enabled=1` unless caller supplies valid current TOTP; `/login/2fa-verify` must reject when both `totp_enabled` AND `pendingTotpSecret` are set. `auth.routes.ts:662-762`. (P3-AUTH-04)
- [ ] SEC-H4. **Device-trust rotation:** rotate on every login, move to server-side `trusted_devices` row, include client-localStorage nonce in fingerprint, cap at 30d. `auth.routes.ts:221-225, 589-619, 770-787`. (P3-AUTH-05 / CRYPTO-M03)
- [ ] SEC-H5. **IP rate limit at top of `/login/2fa-backup`** (user-keyed only today). `auth.routes.ts:794-834`. (P3-AUTH-06)
- [ ] SEC-H6. **Unify error messages** on `/account/2fa/disable` and `/recover-with-backup-code` (400 vs 401 vs 429 leak 2FA state / email existence). `auth.routes.ts:1240-1311, 1385-1482`. (P3-AUTH-07, 08)
- [ ] SEC-H7. **Build password-reset URL from `config.baseDomain`**, not `req.headers.host` (Host-header injection in single-tenant). `auth.routes.ts:1147-1149`. (P3-AUTH-12 / PUB-010)
- [ ] SEC-H8. **Delete other sessions + clear deviceTrust cookie on `/account/2fa/disable`.** `auth.routes.ts:1302-1310`. (P3-AUTH-19)
- [ ] SEC-H9. **`/login/set-password` needs `AND password_set = 0` guard** (consumed challenge can overwrite set password). `auth.routes.ts:636-659`. (trace-login-002 / C3-036)
- [ ] SEC-H10. **Clear login_user + login_ip rate counters on success** (targeted 30-min lockout DoS today). `auth.routes.ts:549-574`. (trace-login-005)
- [ ] SEC-H11. **PIN rate limit key on (tenant, actor.userId, target.userId, ip)** — currently cross-user PIN brute-force feasible. `auth.routes.ts:140, 959`. (trace-login-007)
- [ ] SEC-H12. **`/auth/refresh` must assert `payload.tenantSlug === req.tenantSlug`** (constant-time); prevents cross-tenant session laundering. `auth.routes.ts:848-888`. (trace-refresh-004)
- [ ] SEC-H13. **WebSocket auth adds server-side session/user-active DB check** (revoked JWT keeps streaming up to 1h). `ws/server.ts:349-395`. (P3-THOR-01 / CRYPTO-M04)
- [ ] SEC-H14. **Per-user login rate limit case-sensitive (SQLite BINARY)** — 'admin', 'Admin' each get separate buckets. Normalize lower-case before key. (P3-THOR-02)
- [ ] SEC-H15. **Default PIN `1234` also seeded by `services/tenant-provisioning.ts:316`** (PROD12 covers auth seed). [uncertain — verify overlap with PROD12] (BH-S006) - shouls require a setup on user creation

### HIGH — authz

- [ ] SEC-H16. **Ticket nested-resource handlers require `requirePermission` + closed/invoiced guards:** DELETE/PUT `/tickets/notes/:noteId`, DELETE `/tickets/photos/:photoId`, PUT/DELETE `/tickets/devices/:deviceId`, PATCH checklist, DELETE parts. `tickets.routes.ts:2151, 2235, 2657, 2901, 3001`. (AZ-001…005)
- [ ] SEC-H17. **`/settings/users/:id` sensitive-change bypass:** admins lacking `password_hash` (OAuth/imported rows) skip current-password check; `/recover-with-backup-code` also bypasses. Add 24h post-recovery cooldown on role mutations. `settings.routes.ts:881`. (AZ-006)
- [ ] SEC-H18. **Role-matrix: `PUT /roles/users/:userId/role`** writes to `user_custom_roles` but not `users.role`; `requirePermission` hard-bypasses `users.role === 'admin'`. Either also update `users.role` or remove admin bypass. `roles.routes.ts:282-327` + `middleware/auth.ts:193`. (AZ-007)
- [ ] SEC-H19. **`startAutoClockoutSweep` wrap in `forEachDbAsync`** across tenant DBs (only runs on `config.dbPath` — every tenant's clock entries open forever). `employees.routes.ts:624-630`. (AZ-008)
- [ ] SEC-H20. **Step-up TOTP on super-admin destructive endpoints** (delete tenant, PUT /tenants/:slug plan, force-disable-2fa, DELETE /sessions, PUT /config); shorten session TTL to 30m. `super-admin.routes.ts`. (AZ-009 / AZ-023 / BH-B-016)
- [ ] SEC-H21. **`POST /gift-cards` admin/manager gate** (any authed user can mint $10k bearer cards today). `giftCards.routes.ts:213-214`. (AZ-018)
- [ ] SEC-H22. **`POST /inventory/:id/adjust-stock` role gate + atomic differential UPDATE** (`WHERE in_stock + ? >= 0`). `inventory.routes.ts:1076-1117`. (BH-B-009 / C3-002)
- [ ] SEC-H23. **`DELETE /customers/:id` admin/manager gate + name-typing CSRF;** cascade-anonymize sms_messages/FTS/uploads/customer_phones/customer_emails. `customers.routes.ts:1207-1245`. (BH-B-013…015)
- [ ] SEC-H24. **Tracking `/api/v1/track/lookup` don't return raw `tracking_token`** — require SMS-OTP before reveal. `tracking.routes.ts:77-94, 199-227`. (BH-B-019 / AZ-011)
- [ ] SEC-H25. **Enforce `requirePermission` on every mutating tenant endpoint** (role matrix advisory today). `routes/{tickets,invoices,customers,inventory,refunds,giftCards,deposits}.routes.ts`. (AZ-027)
- [ ] SEC-H26. **`POST /invoices/:id/payments` re-check `body.customer_id === invoice.customer_id`** when supplied. `pos.routes.ts:249`. (trace-pos-004)
- [ ] SEC-H27. **Tracking token out of URL query** — hash at rest, move to `Authorization` header, add expiry. `tracking.routes.ts:99-141`. (BH-B-020 / P3-PII-06)
- [ ] SEC-H28. **Refund approve `WHERE status='pending'` guard + single transaction** + WHERE-clause prior-status guard on amount_paid decrement. `refunds.routes.ts:165-251`. (BH-B-001 / C3-007)
- [ ] SEC-H29. **Role gate on `POST /refunds`** + idempotent middleware to block double-submit. `refunds.routes.ts:79-158`. (BH-B-028, 029)
- [ ] SEC-H30. **Trade-in `status=accepted` manager/admin gate + accepted_price sanity guard.** `tradeIns.routes.ts:104-132`. (BH-B-006 / AZ-016)
- [ ] SEC-H31. **`POST /tickets/:id/quick-track` requirePermission + RMA transitions.** `rma.routes.ts:88, 133`. (AZ-017)
- [ ] SEC-H32. **Tracking `/portal/:orderId/message` require portal session** for `customer_message` writes. `tracking.routes.ts:466`. (AZ-022)
- [ ] SEC-H33. **Payment-link public routes explicit tenant_id match** on click/pay. `paymentLinks.routes.ts:243`. (AZ-028)

### HIGH — payment

- [ ] SEC-H34. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01)
- [ ] SEC-H35. **Stripe webhook handlers for `charge.dispute.created`, `charge.refunded`, `payment_intent.payment_failed`, `customer.subscription.trial_will_end`.** Unhandled events silently record `tenant_id=NULL`. `stripe.ts:523-751`. (PAY-07)
- [ ] SEC-H36. **Recompute `tax_amount` server-side** from `tax_classes.rate` in `POST /invoices` (match `pos.routes.ts /transaction` pattern). `invoices.routes.ts:240-250`. (PAY-10) only on web, android could be offline
- [ ] SEC-H37. **Add `currency` column** on invoices/payments/refunds/gift_cards/deposits; default 'USD'. (PAY-17)
- [ ] SEC-H38. **Store SHA-256 of gift card code, not plaintext;** mask in `audit_log.details`; bump `generateCode` to 128 bits. **Verified live — code `3B2681D6E6416C5B` in audit_logs plaintext.** `giftCards.routes.ts:33-35, 237`. (PAY-14 / BH-B-004 / CRYPTO-H02 / LIVE-04)
- [ ] SEC-H39. **Decrement `tenant_usage.tickets_created` on insert failure** (or two-phase reserve/commit). `estimates.routes.ts`, `pos.routes.ts:978-1006`. (PAY-40 / LOGIC-013)
- [ ] SEC-H40. **Deposit DELETE must call processor refund;** link to originating `payment_id`; update invoice amount_paid/amount_due on apply. `deposits.routes.ts:218-245, 165-215`. (PAY-19, 20)
- [ ] SEC-H41. **BlockChyp `/void-payment` must call `client.void()`** at processor + add BlockChyp webhook receiver (none today). `blockchyp.routes.ts:359-397`. (trace-pos-005 / trace-webhook-002)
- [ ] SEC-H42. **BlockChyp double-charge window dedup 30s on (invoice_id, client_ip, amount).** `blockchyp.routes.ts:133-173`. (trace-pos-002)
- [ ] SEC-H43. **Role check on BlockChyp `/process-payment`** (any authed user today). `blockchyp.routes.ts:129-349`. (PAY-37)
- [ ] SEC-H44. **`acquireCustomerLock` TTL + fencing** (stuck forever if crash between acquire/release). `stripe.ts:254-278`. (C3-030)
- [ ] SEC-H45. **Membership `/subscribe` verify `blockchyp_token` with processor** before activating subscription. `membership.routes.ts:140-203`. (LOGIC-024)
- [ ] SEC-H46. **Cap `pct_adjustment` at ±50% + dual-admin approval for > 20%** (1000% markup possible today). `repairPricing.routes.ts:407-430`. (LOGIC-007)
- [ ] SEC-H47. **Bulk `mark_paid` route through `POST /:id/payments`** (currently hardcodes cash, skips dedup/webhooks/commissions). `invoices.routes.ts:695-725`. (LOGIC-006)
- [ ] SEC-H48. **Bulk-void invoice must restore stock** like single-void. `invoices.routes.ts:726`. (P3-THOR-04)
- [ ] SEC-H49. **Ticket delete stock-restore skip `missing`/`ordered` parts** (currently mints inventory). `tickets.routes.ts:1752-1768`. (LOGIC-029)
- [ ] SEC-H50. **Estimate `/approve` disallow self-approval** (`created_by=current_user`). `estimates.routes.ts:902-935`. (LOGIC-016)
- [ ] SEC-H51. **Estimate `/:id/convert` atomic** — `UPDATE...WHERE status NOT IN ('converted','cancelled')` + check `changes=1`. `estimates.routes.ts:645-744`. (LOGIC-026)
- [ ] SEC-H52. **Hash estimate `approval_token` at rest** (currently plaintext). `estimates.routes.ts:793-808`. (LOGIC-028)

### HIGH — pii

- [ ] SEC-H53. **Extend GDPR-erase** to scrub FTS, `ticket_photos` on disk, `audit_log.details` JSON, Stripe customers, SMS suppression. `customers.routes.ts:1692-1773` + migrations. (P3-PII-03, 04, 11)
- [ ] SEC-H54. **Gate `/uploads/<slug>/*` behind auth;** signed-URL + HMAC(file_path+expires_at) for portal/MMS; separate `/admin-uploads` for licenses. `index.ts:845-865`. (P3-PII-07 / PUB-022)
- [ ] SEC-H55. **Audit `customer_viewed` on GET `/:id` + bulk list-with-stats.** `customers.routes.ts:88, 991-1019`. (P3-PII-05)
- [ ] SEC-H56. **Step-up auth + email notification on PII exports** (`/customers/:id/export`, `/settings-ext/export.json`, `/reports/*?export_all=1`). (P3-PII-12, 13, 20)
- [ ] SEC-H57. **Retention rules for sms_messages, call_logs, email_messages, ticket_notes** (default 24mo, tenant-configurable). `services/retentionSweeper.ts:54-70`. (P3-PII-08)
- [ ] SEC-H58. **Upload retention:** unlink `ticket_photos` files for closed tickets > 12mo; scrub on GDPR-erase. `tickets.routes.ts:2173-2229`. (P3-PII-15)
- [ ] SEC-H59. **Full tenant export endpoint** for data portability (zip of all tables + uploads, tenant passphrase). (P3-PII-16)
- [ ] SEC-H60. **Backup restore filename slug+tenant_id match + HMAC over metadata** to prevent tampered `.db.enc` swap. `services/backup.ts:82-139, 432-458`, `super-admin.routes.ts:1161-1183`. (P3-PII-17, 18)
- [ ] SEC-H61. **Reset-password link `Referrer-Policy: no-referrer`** + `history.replaceState` to strip token from URL. [uncertain] (P3-PII-14)

### HIGH — concurrency

- [ ] SEC-H62. **Differential atomic UPDATEs on every stock mutation path** (POS `stock_membership`, stocktake, ticket parts delete/quick-add, gift card reload). (C3-001, 003, 004, 010, 011)
- [ ] SEC-H63. **Transactional stocktake commit** with `WHERE status='open'` guard inside txn. `stocktake.routes.ts:267-325`. (BH-B-011)
- [ ] SEC-H64. **Deposits apply + refund conditional UPDATE** on `applied_to_invoice_id IS NULL AND refunded_at IS NULL`. `deposits.routes.ts:165-245`. (C3-005, 006)
- [ ] SEC-H65. **Password reset UPDATE `WHERE reset_token = ?` + single transaction** with DELETE sessions. `auth.routes.ts:1198-1231`. (trace-reset-001 / C3-014)
- [ ] SEC-H66. **pruneOldSessions + INSERT in single `adb.transaction()`** with atomic CTE-based prune. `auth.routes.ts:157-169, 247-250`. (C3-013)
- [ ] SEC-H67. **store_credits UPSERT + `UNIQUE(customer_id)` constraint.** `refunds.routes.ts:222-237`. (C3-035)
- [ ] SEC-H68. **`commissions UNIQUE(ticket_id)` partial index WHERE type != 'reversal'** + single-statement atomic status change. `tickets.routes.ts:1861-1948`. (C3-009, 049)
- [ ] SEC-H69. **Notification/SMS/email retry queues SELECT-and-claim** pattern + backoff jitter. `services/notifications.ts:220-266` + `index.ts:2138-2180`. (C3-019…022, 045)
- [ ] SEC-H70. **Stripe webhook `processPaymentFailed` differential UPDATE** + wrap full switch in `masterDb.transaction()`. `stripe.ts:418-509`. (C3-031)
- [ ] SEC-H71. **Idempotency store → tenant DB table `idempotency_keys`** with `UNIQUE(user_id, key)`. `middleware/idempotency.ts:49-100`. (C3-017)
- [ ] SEC-H72. **UNIQUE partial index on `customer_subscriptions(customer_id) WHERE status IN ('active','past_due')`.** `membership.routes.ts:164-195`. (C3-033)
- [ ] SEC-H73. **Backup code consume atomic UPDATE** (`JSON_REMOVE` + `WHERE json_extract`). `auth.routes.ts:754-762, 818-830`. (C3-016)

### HIGH — reliability

- [ ] SEC-H74. **Explicit 15s timeouts + `maxNetworkRetries`** on Stripe, BlockChyp, Nodemailer (80s / 10min defaults today). (REL-001, 002, 003)
- [ ] SEC-H75. **Promisified `execFile` in githubUpdater** (30s sync git blocks Express process hourly). `services/githubUpdater.ts:89-96, 239-247`. (REL-005)
- [ ] SEC-H76. **Wallclock ceiling (90min) on catalogScraper** + async spawn in backup disk-space check. `services/catalogScraper.ts:42-68` + `backup.ts:215-256`. (REL-006, 007)
- [ ] SEC-H77. **Circuit breakers on outbound providers** (Stripe/BlockChyp/Twilio/Telnyx/Vonage/Plivo/Bandwidth/SMTP/Cloudflare/GitHub). (REL-008)
- [ ] SEC-H78. **Single-query kanban + tv-display** (ROW_NUMBER / IN-clause vs Promise.all). `tickets.routes.ts:1130-1176, 1362-1389`. (REL-011, 012)
- [ ] SEC-H79. **dashboardCache single-flight** to prevent cache stampede. `utils/cache.ts`. (REL-013)
- [ ] SEC-H80. **Cap reports date range 90d default / 365d flag;** long range = async job. `reports.routes.ts:22-27`. (REL-016)
- [ ] SEC-H81. **Drop global `express.json` limit to 1mb** + per-route carve-outs (10mb × 300req/min = 3GB RAM DoS today). `index.ts:776-779`. (REL-019 / PUB-005)
- [ ] SEC-H82. **RepairDesk import to Piscina worker + wallclock + business-hours throttle.** `services/repairDeskImport.ts`. (REL-028)

### HIGH — public-surface

- [ ] SEC-H83. **Migrate global `/api/v1` rate limiter + `webhookRateMap` to DB-backed** (auth paths already migrated via 069). `index.ts:719-770, 906-927`. (PUB-001, 002)
- [ ] SEC-H84. **Trust proxy = explicit CF/LB IPs**, not integer 1. `index.ts:374`. [uncertain] (PUB-012)
- [ ] SEC-H85. **CAPTCHA on `/auth/login` + `/forgot-password`** after N failures. (PUB-013, 014)
- [ ] SEC-H86. **WebSocket origin allowlist fail-closed on parse/DB error;** cap per-IP + per-tenant concurrent sockets. `ws/server.ts:181-225, 242-462`. (BH-0011 / PUB-018, 019)
- [ ] SEC-H87. **Portal PIN 6 digits + per-customer_id rate limit + SMS notification on lockout.** `portal.routes.ts:478, 661-664, 706`. (P3-AUTH-13 / P3-PII-09)
- [ ] SEC-H88. **Portal quick-track per-order_id + per-phone-last4 lockout;** portal comments require portal session. `portal.routes.ts:337-415, 1057`. (AZ-010 / P3-AUTH-14 / AZ-022)
- [ ] SEC-H89. **CSRF token on `/api/v1/auth/refresh`** + tighten CSP on `/admin` + `/super-admin` panels (remove `'unsafe-inline'` script-src). `index.ts:593-622, 885-895`. (PUB-007, 008, 023)
- [ ] SEC-H90. **Host-header sanitation on HTTP→HTTPS redirect** (only redirect to approved baseDomain). `index.ts:406-411, 567-574`. (PUB-028)
- [ ] SEC-H91. **Remove legacy `master-admin.routes.ts`** (kill-switch theatre). (P3-AUTH-16 / PUB-027)
- [ ] SEC-H92. **SSRF guards on `services/webhooks.ts webhook_url`:** reject RFC1918/link-local/loopback after DNS; strict http(s); block cross-host redirect follow. `services/webhooks.ts:86`. (sinks-001)
- [ ] SEC-H93. **Allowlist provider domains for MMS/voice recording fetches** before GET with Authorization. `routes/{sms,voice}.routes.ts`. (sinks-005, 006)
- [ ] SEC-H94. **Signup fail-closed on missing `HCAPTCHA_SECRET` in prod + email-verification gate** before provisioning subdomain + CF DNS record. **Verified live — empty captcha_token provisioned tenant `probetest` id 9.** `signup.routes.ts:~274`. (LIVE-01 / BH-0001 / BH-0002)

### HIGH — electron + android

- [ ] SEC-H95. **Sig-verify auto-update (`update.bat`):** signed git tag / tarball before `git pull` + confirm dialog + EV Authenticode cert. `management/src/main/ipc/management-api.ts:336-482` + `electron-builder.yml`. (electron-002, 004)
- [ ] SEC-H96. **`@electron/fuses`:** disable RunAsNode, EnableNodeOptionsEnvironmentVariable, EnableNodeCliInspectArguments; enable OnlyLoadAppFromAsar + EnableEmbeddedAsarIntegrityValidation. (electron-005, 006)
- [ ] SEC-H97. **Zod schemas on every `ipcMain.handle` + senderFrame URL check + path normalization/UNC-reject** in admin:browse-drive / admin:create-folder. `management/src/main/ipc/management-api.ts:234-273, 612-620`. (electron-007, 008)
- [ ] SEC-H98. **Pin cert fingerprint of `packages/server/certs/server.cert`** in management api-client (port-squat impersonation risk). `management/src/main/services/api-client.ts:92-99`. [uncertain] (electron-009)
- [ ] SEC-H99. **Replace Android `PRIMARY_LEAF_PIN_REPLACE_ME`/`BACKUP_LEAF_PIN_REPLACE_ME`** with real SPKI SHA-256 pins + CI guard rejecting `REPLACE_ME` in release builds. [uncertain — may overlap AUD-20260414-H4] (BH-A001)
- [ ] SEC-H100. **Android release signing fail-closed** when `~/.android-keystores/bizarrecrm-release.properties` missing (falls back to global debug keystore today). `android/app/build.gradle.kts:65-95`. (BH-A010)
- [ ] SEC-H101. **Move `fcmToken` from plain `AppPreferences` to `EncryptedSharedPreferences`.** `android/.../AppPreferences.kt:16, 40-46`. (BH-A003)
- [ ] SEC-H102. **`AuthInterceptor.clearAuthState()` POST `/auth/logout`** before wiping local prefs. `android/.../AuthInterceptor.kt:96-177`. (BH-B-021)

### HIGH — crypto

- [ ] SEC-H103. **Split `JWT_SECRET` into dedicated env vars:** `ACCESS_JWT_SECRET`, `REFRESH_JWT_SECRET`, `CONFIG_ENCRYPTION_KEY`, `BACKUP_ENCRYPTION_KEY`, `DB_ENCRYPTION_KEY`. Require `BACKUP_ENCRYPTION_KEY` + `CONFIG_ENCRYPTION_KEY` in production (fatal, not warn). `utils/configEncryption.ts:17-19` + `backup.ts:60-75` + `config.ts`. (CRYPTO-H01 / BH-S003 / BH-S008 / BH-S009 / P3-PII-02)
- [ ] SEC-H104. **Remove inbox bulk-send HMAC fallback `|| 'bizarre-inbox-bulk'`.** `inbox.routes.ts:414, 429`. (BH-S004)
- [ ] SEC-H105. **Super-admin fallback secret `'super-admin-dev-secret'`** in single-tenant mode — require `SUPER_ADMIN_SECRET` whenever router mounts. `config.ts:188`. (BH-S007)

### HIGH — supply-chain + tests

- [ ] SEC-H106. **Resolve `bcryptjs` 2.4.3 vs ^3.0.2 drift:** `npm install` at repo root, commit `package-lock.json`.
- [ ] SEC-H107. **Minimum CI:** `npm ci && npm run build && npm audit --audit-level=high && npm ls --all` on PR.
- [ ] SEC-H108. **Pin `app-builder-bin` exact version** + move to devDependencies. `management/package.json:25`.
- [ ] SEC-H109. **Bump `dompurify` >=3.3.4** + audit every `ADD_TAGS` usage. (CVE GHSA-39q2-94rc-95cp / BH-0013)
- [ ] SEC-H110. **Bump `follow-redirects` >=1.15.12** via `npm audit fix`; set `maxRedirects:0` on BlockChyp axios. (CVE GHSA-r4q5-vmmm-2653 / BH-0014)
- [ ] SEC-H111. **`.npmrc ignore-scripts=true` in CI** + SHA256 verification of Electron/native-binary prebuilds.

### HIGH — logic

- [ ] SEC-H112. **Ticket status state machine + transition guard** on UPDATE. `tickets.routes.ts:1803-1895`. (LOGIC-001)
- [ ] SEC-H113. **Invoice + lead status enums + state-machine validation.** (LOGIC-002, 003, 027)
- [ ] SEC-H114. **Gift card expiry cron + redeem atomic** `AND (expires_at IS NULL OR expires_at > datetime('now'))`. `giftCards.routes.ts:312-351`. (LOGIC-004)
- [ ] SEC-H115. **SMS send checks `customers.sms_opt_in` (TCPA)** + admin override for transactional-exempt. `sms.routes.ts:414-590`. (BH-B-022)
- [ ] SEC-H116. **Customer merge `Number(keep_id) === Number(merge_id)`** (string-vs-number type confusion enables self-merge soft-delete). `customers.routes.ts:404-538`. (LOGIC-008)
- [ ] SEC-H117. **Cap line-item qty ≤ 10000 + invoice.total ≤ $1M** without admin override. `invoices.routes.ts:240-250`. (LOGIC-025)
- [ ] SEC-H118. **Trade-ins state machine + soft-delete** (accepted → deleted loses audit). `tradeIns.routes.ts:104-132`. (LOGIC-012, BH-B-006, 008)
- [ ] SEC-H119. **Pagination guard reject `OFFSET > 100000`** across trade-ins/loaners/gift-cards/rma/refunds/payment-links. (LOGIC-011)
- [ ] SEC-H120. **Universal `MAX_PAGE_SIZE=100` constant.** (PUB-015)
- [ ] SEC-H121. **Soft-delete + `is_deleted` filter** on trade-ins, loaners, rma, gift cards. (LOGIC-019)
- [ ] SEC-H122. **`automations.executeChangeStatus` reuse HTTP handler guards** (post-conditions, parts, diagnostic note). `services/automations.ts:270-286`. (LOGIC-023)

### HIGH — ops (additional)

- [ ] SEC-H123. **Per-tenant/per-IP WebSocket connection cap + back-pressure** (`ws.bufferedAmount` threshold). `ws/server.ts:508-545`, `index.ts:547-562`. (REL-020, 021 / PUB-019)
- [ ] SEC-H124. **Tenant-DB pool refcounting** + MAX_POOL_SIZE review. `db/tenant-pool.ts:55-78`. [uncertain — overlap AUD-M19] (REL-009)

### MEDIUM

- [ ] SEC-M1. **Move `pendingSignups` Map to master DB** (`token_hash+expires_at`). `signup.routes.ts:37-57`. (P3-AUTH-10)
- [ ] SEC-M2. **Single-tenant `/setup` bind first-setup to `.setup-token` chmod-0600** or 127.0.0.1 only. `auth.routes.ts:353-492`. (P3-AUTH-11)
- [ ] SEC-M4. **Super-admin TOTP replay prevention** — track last used counter. `super-admin.routes.ts:388`. [uncertain]
- [ ] SEC-M5. **Super-admin login dummy-hash** for unknown usernames. `super-admin.routes.ts:245-275`. (BH-B-018)
- [ ] SEC-M6. **Super-admin force-disable-2fa:** parallel tenant audit_log + step-up MFA + out-of-band email delay. `super-admin.routes.ts:1071-1159`. (BH-B-017 / AZ-023)
- [ ] SEC-M7. **Normalize emails via NFKC+punycode** before dedupe/referral. `customers.routes.ts:477-492`. (LOGIC-014)
- [ ] SEC-M8. **2FA challenge Map → SQLite table** (lost on restart). `auth.routes.ts:80-113`. (P3-AUTH-15)
- [ ] SEC-M9. **Refresh rotation preserves original lifetime category** (30d regardless of trustDevice 90d today). `auth.routes.ts:897-909`. (P3-AUTH-09)
- [ ] SEC-M10. **Refresh handler audit + logTenantAuthEvent** on success/failure. `auth.routes.ts:837-922`. (trace-refresh-002)
- [ ] SEC-M11. **Delete session row when refresh hits inactive user** (zombie sessions). `auth.routes.ts:877-880`. (trace-refresh-005)
- [ ] SEC-M12. **`/change-password` clear `reset_token` + `reset_token_expires`** in same UPDATE. `auth.routes.ts:1491`. (trace-reset-006)
- [ ] SEC-M13. **Hide 2FA-enrollment state error variance.** `auth.routes.ts:735-749`. (trace-login-004)
- [ ] SEC-M14. **Deposits `POST /` manager/admin role gate.** `deposits.routes.ts:97-159`. (PAY-21)
- [ ] SEC-M15. **Per-email signup rate limit** (in addition to per-IP). `signup.routes.ts:62-68`. (trace-signup-003)
- [ ] SEC-M16. **Role-gate + page-cap on GET lists:** `/deposits`, `/customers`, `/payment-links`, `/rma`. (AZ-012, 013, 014, 030)
- [ ] SEC-M17. **Trade-ins accept atomic inventory + store_credit INSERT** on status→accepted. `tradeIns.routes.ts:104-132`. (BH-B-007)
- [ ] SEC-M18. **RMA + loaner listings role-gated on `inventory.adjust` OR admin;** redact supplier/tracking. (AZ-015, 030, 029)
- [ ] SEC-M19. **Portal/embed/config tenant allowlist + IP rate limit.** `portal.routes.ts:1263`. (AZ-021)
- [ ] SEC-M20. **Management routes require master-auth + per-handler tenantId guard.** `management.routes.ts` + `index.ts:1094`. (AZ-024)
- [ ] SEC-M21. **Portal register/send-code 24h per-phone hard cap + CAPTCHA on first new IP.** `portal.routes.ts:510`. (AZ-025)
- [ ] SEC-M22. **Redact super-admin tenant list `db_path`** on list view. `super-admin.routes.ts:546`. (AZ-032)
- [ ] SEC-M23. **`recordLockoutFailure` transactional** (INSERT OR IGNORE + conditional UPDATE). `utils/rateLimiter.ts:98-117`. (C3-018)
- [ ] SEC-M24. **password_history insert inside `adb.transaction`** for change-password. `auth.routes.ts:1543-1561`. (C3-015)
- [ ] SEC-M25. **Stripe webhook: on exception DELETE idempotency claim** so retries work; or DLQ. `stripe.ts:745-753`. (trace-webhook-001)
- [ ] SEC-M26. **Import worker yield 100-row batches + `PRAGMA wal_checkpoint(PASSIVE)`** periodically. (C3-028, 029)
- [ ] SEC-M27. **Master DB retention cron** for master_audit_log, tenant_auth_events, security_alerts. `master-connection.ts:116-156`. (REL-035)
- [ ] SEC-M28. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015)
- [ ] SEC-M29. **`/health` probe DB liveness;** `/ready` gate on PRAGMA user_version round-trip. **Verified live — currently 200 regardless of dep state.** `index.ts:1178-1185`. (REL-018 / LIVE-07)
- [ ] SEC-M30. **Lower tenant DB `cache_size` pragma** (64MB × 50 pool = 3.2GB locked). `db/tenant-pool.ts:103`. (REL-037)
- [ ] SEC-M31. **Per-tenant cron timeout wrapper** (`forEachDbAsync` unbounded today). `index.ts:177-198`. (REL-025)
- [ ] SEC-M32. **forgot-password timing equalization** (async sendEmail). `auth.routes.ts:1121-1156`. (trace-reset-003)
- [ ] SEC-M33. **`reference_type='credit_note_overflow'`** on overflow store_credit. `invoices.routes.ts:856-889`. (PAY-38)
- [ ] SEC-M34. **BlockChyp terminal offline:** invalidate client cache on timeout + reconcile via terminal query before marking failed. `services/blockchyp.ts:57-104, 318-420`. (PAY-23)
- [ ] SEC-M35. **Stripe idempotency key derive from (tenant_id, price_id, epoch_day)** — latent fix pending Enterprise checkout. `stripe.ts:215-245, 323-341`. (PAY-03)
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
- [ ] SEC-M37. **`parseFloat` price parsing via `validatePrice`** in inventory + repairPricing. `inventory.routes.ts:1664-1665`, `repairPricing.routes.ts:45-46`. (PAY-02)
- [ ] SEC-M38. **Stripe webhook `constructEvent` pass `{ tolerance: 300 }`.** `stripe.ts:364-370`. (PAY-06)
- [ ] SEC-M39. **BlockChyp test-mode flip check** — pass config snapshot to `getClient()`. `blockchyp.ts:329-355`. (PAY-24)
- [ ] SEC-M40. **Stripe `updateSubscription proration_behavior` param.** `stripe.ts:866-873`. (PAY-25)
- [ ] SEC-M41. **BlockChyp payment_idempotency scope by user_id** (prevent credential replay). `blockchyp.routes.ts:182-199`. (PAY-05)
- [ ] SEC-M42. **Janitor cron** for stuck `payment_idempotency.status='pending'` > 5min → `failed`. (PAY-04 / trace-pos-003)
- [ ] SEC-M43. **`checkout-with-ticket` auto-store-credit on card overpayment.** `pos.routes.ts:1334-1370`. (PAY-11)
- [ ] SEC-M44. **Add `capture_state` column on payments** + gate refund on 'captured'. `refunds.routes.ts:79-158`. (PAY-12)
- [ ] SEC-M45. **Portal sessions idle-timeout 2-4h;** migrate CSRF to synchronizer token server-side store. `portal.routes.ts:36, 80-92, 1057`. (P3-AUTH-14)
- [ ] SEC-M46. **Stripe customer delete on tenant deletion** (best-effort). (P3-PII-10)
- [ ] SEC-M47. **scheduled_report_email → scheduled_report_recipients table** with status + audit. `services/scheduledReports.ts:201-242`. (LOGIC-022)
- [ ] SEC-M48. **Per-task timeout on Piscina runs + maxQueue 2000→200** with 503 Retry-After. `db/worker-pool.ts:33-39`. (REL-022)
- [ ] SEC-M49. **Per-tenant DB size monitoring + archive audit_logs >90d.** `index.ts:474-477`. (REL-023)
- [ ] SEC-M50. **SQLite `busy_timeout=5000`:** serialize same-tenant cron ticks. `db/tenant-pool.ts:104`. (REL-033)
- [ ] SEC-M51. **TOTP AES-256-GCM HMAC-based KDF + version AAD.** `auth.routes.ts:40, 45` + `super-admin.routes.ts:94, 103`. (CRYPTO-M01, 02)
- [ ] SEC-M52. **CORS tighten production allowlist** (drop RFC1918/CGNAT auto-accept). `index.ts:661-684`. (PUB-006)
- [ ] SEC-M54. **Estimate bulk-convert: decrement tier reservation on skip/fail** + move increment to per-estimate success. `estimates.routes.ts:302-436`. (LOGIC-013)
- [ ] SEC-M55. **Per-tenant daily SMS cap** (carrier-fraud). `sms.routes.ts:408-423`. (BH-B-023)
- [ ] SEC-M56. **SMS per-destination rate limit 3/hr + redact phone in logger.** `sms.routes.ts:563-569`. (BH-B-024, 030)
- [ ] SEC-M57. **Reject control/RTL codepoints** in customer names/notes/tags. `customers.routes.ts`. (LOGIC-018)
- [ ] SEC-M58. **Dunning scheduler tenant_timezone cutoff** (UTC-vs-local drift). `services/dunningScheduler.ts:407-411`. (LOGIC-010)
- [ ] SEC-M59. **Estimate expiry reject NULL `approval_token_expires_at`.** `estimates.routes.ts:893-900`. (LOGIC-009)
- [ ] SEC-M60. **Payment-link `/click` + `/pay` auto-expire on `expires_at`.** `paymentLinks.routes.ts:243-321`. (LOGIC-015)
- [ ] SEC-M61. **user_permissions fine-grained capability table** (replace role='admin' grab-bag). (LOGIC-017)
- [ ] SEC-M62. **`DELETE /tickets/:id` requirePermission('tickets.delete') + block paid-invoice tickets.** `tickets.routes.ts:1735-1770`. (AZ-020)

### LOW

- [ ] SEC-L1. **2FA-disable 400 message distinct** leaks already-disabled state (same-user minor). `auth.routes.ts:1266`. (P3-AUTH-07 low)
- [ ] SEC-L2. **Portal phone lookup full-normalized equality** instead of SQL LIKE suffix. `portal.routes.ts:443-464, 539-565`. (P3-AUTH-23)
- [ ] SEC-L3. **Multi-tenant `/setup` require email** (fallback `username@shop.local` today). `auth.routes.ts:413-419`. (P3-AUTH-21)
- [ ] SEC-L5. **`/change-password` per-user rate limit 10/hour** (closes password_history bcrypt-loop DoS). `auth.routes.ts:175-191`. (P3-AUTH-25)
- [ ] SEC-L6. **Loaner history redact last names for non-admin.** `loaners.routes.ts:32`. (AZ-029)
- [ ] SEC-L7. **Customer merge: re-key sms_messages to `keep_id`.** `customers.routes.ts:437-445`. (AZ-031)
- [ ] SEC-L8. **Node engines tighten `>=22.11.0 <23`** + `engine-strict=true`.
- [ ] SEC-L9. **Renovate.json** for Electron/Android auto-bump group.
- [ ] SEC-L10. **OAuth state persistence in short-TTL DB row.** `import.routes.ts:1360-1399`. (C3-048)
- [ ] SEC-L11. **metrics.db daily `PRAGMA incremental_vacuum(50)`.** `services/metricsCollector.ts:78-96`. (REL-036)
- [ ] SEC-L12. **Graceful shutdown 5s cron drain wait.** `index.ts:443-470, 2471-2537`. (REL-024)
- [ ] SEC-L13. **Piscina worker LRU cache:** reduce `MAX_CACHED_DBS` or route same-tenant to same worker. `db/db-worker.mjs:14-84`. (C3-027)
- [ ] SEC-L14. **Per-provider probe endpoint** for SMS/email/Stripe/BlockChyp. (REL-031)
- [ ] SEC-L15. **`webhooks.deliverWithRetry` jitter ±500ms.** `services/webhooks.ts:51`. (C3-022 / REL-027)
- [ ] SEC-L16. **`getOrCreateWebhookSecret` race-safe `INSERT OR IGNORE`.** `services/webhooks.ts:56-73`. (C3-026)
- [ ] SEC-L17. **CF DNS retry jitter** during signup bursts. `services/cloudflareDns.ts:93-101`. (REL-004)
- [ ] SEC-L18. **Per-tenant failure circuit on cron handlers.** `index.ts:1524-1761`. (REL-029)
- [ ] SEC-L19. **Backup disk-space check include uploads dir.** `services/backup.ts:291-310`. (REL-040)
- [ ] SEC-L20. **catalogScraper hard-cap Content-Length 10MB** before cheerio parse. `services/catalogScraper.ts:180-316`. (REL-030)
- [ ] SEC-L21. **Dashboard cache key include `req.user.role`.** `reports.routes.ts:31-40`. (REL-038)
- [ ] SEC-L23. **stripeClient refresh on config change** (restart required today). `services/stripe.ts:94-104`. (REL-039)
- [ ] SEC-L24. **`/api/v1/info` auth-gate in multi-tenant** (leaks LAN IP — **verified live** Tailscale 100.x). `index.ts:868-878`. (PUB-020 / LIVE-08)
- [ ] SEC-L27. **Portal widget.js client-side regex on `data-server`** against CNAME pattern. `portal.routes.ts:1281-1360`. (AZ-026)
- [ ] SEC-L29. **Payment-links `/click` token-length regex match generator** (allows 8-char today). `paymentLinks.routes.ts:188-271`. (PAY-27 / PUB-030)
- [ ] SEC-L31. **Outbound webhook HMAC bind X-Webhook-Timestamp** (sign `${timestamp}.${body}`). `services/webhooks.ts:252`. (CRYPTO-L02)
- [ ] SEC-L32. **API key hashing bcrypt cost 12** (10 today). `settings.routes.ts:1860`. (CRYPTO-L03)
- [ ] SEC-L33. **Explicit TLS cipher whitelist + `honorCipherOrder:true`.** `index.ts:389`. (CRYPTO-L04)
- [ ] SEC-L35. **sms_messages zombie recovery** on startup. `sms.routes.ts:499-570`. (BH-B-026)
- [ ] SEC-L36. **`incrementSmsCount` fail-closed** (silently allows plan overage today). `sms.routes.ts:542-551`. (BH-B-027)
- [ ] SEC-L37. **SMS E.164 destination validation.** `sms.routes.ts:425-430`. (BH-B-025)
- [ ] SEC-L38. **import_runs zombie recovery** on startup. `import.routes.ts:304-335`. (BH-B-012)
- [ ] SEC-L39. **Recurring appointments use `date-fns addMonths` in tenant-local TZ.** `leads.routes.ts:475-513`. (LOGIC-030)
- [ ] SEC-L40. **payment_plan installments × amount_per ≈ invoice.total** server recompute. `invoices.routes.ts:326-337`. (LOGIC-021)
- [ ] SEC-L41. **Slug-check captcha after first call per IP.** `signup.routes.ts:75-83`. (trace-signup-005)
- [ ] SEC-L42. **Signup validation order leak:** combine slug-taken + invalid-email into single error (**verified live**). `signup.routes.ts`. (LIVE-10)
- [ ] SEC-L44. **2FA backup codes:** switch hex → Crockford base32. `auth.routes.ts:757`. (P3-AUTH-18)
- [ ] SEC-L45. **Collapse signup step-specific error messages** into generic. `services/tenant-provisioning.ts:269-372`. (trace-signup-004)
- [ ] SEC-L46. **Membership renewal raise `MEMBERSHIP_MAX_PER_RUN`** after adding timeouts + shorter cron. `index.ts:1371-1461`. (REL-026)
- [ ] SEC-L47. **Zero-dollar invoice reject guard** (config flag). `pos.routes.ts:488-508`. (trace-pos-001)

### Uncertain overlaps — verify before starting (human review)

- AZ-019 (SMS inbound-webhook forge) — verified.jsonl rejected as CRITICAL (drivers fail-closed). Latent: `getSmsProvider` not tenant-scoped. Possibly overlap AUD-M22/23/24 in DONETODOS.md.
- PROD12 (PIN 1234) ↔ BH-S006 / SEC-H15 — same default PIN. Keep one.
- PROD15 (rate limit signup / forgot-password) ↔ SEC-H85 CAPTCHA — both needed (rate limit + captcha complementary).
- PROD29 (SSRF audit) ↔ SEC-H92 / SEC-H93 — consolidate under PROD29 or split.
- PROD32/33/34 (HSTS, cookies, CSP) ↔ SEC-H89 — review merge.
- PROD44 (super-admin auth separate check) ↔ SEC-H105 — subtask.
- TS1/TS2 (tenant-owned Stripe) ↔ SEC-C3 / SEC-M36 — adjacent, keep separate.
- AUD-M19 (LRU pool eviction refcounting) ↔ SEC-H124 — dedupe.
- AUD-L19 (super-admin TOTP replay) ↔ SEC-M3/M4 — dedupe.
- SA1-2 (localStorage token storage) ↔ SEC-H61 — consolidate.
- AUD-20260414-H4 (Android cert pins) ↔ SEC-H99 — same placeholder-pin finding; dedupe.

### Phase 4 live-probe positive controls (no action — reference only)

Verified working. Not TODOs.

- JWT `algorithms:['HS256']` + iss/aud pinned on every verify.
- Stripe webhook signature + 300s replay window + INSERT OR IGNORE idempotency (forge rejected 400).
- Helmet HSTS `max-age=63072000 includeSubDomains preload` + CSP + Referrer-Policy + Permissions-Policy.
- bcrypt cost 12 users / 14 super-admins; constant-time password compare with dummy-hash + 100ms floor.
- DB-backed rate limits (migration 069) SURVIVE server restart (login 429 persisted 3 restarts). (LIVE-06)
- POS `/transaction` single `adb.transaction()` with `expectChanges` guards.
- Gift-card redeem guarded atomic UPDATE (no double-spend).
- Store-credit decrement guarded atomic UPDATE.
- `counters.allocateCounter` transactional `UPDATE...RETURNING`.
- `stripe_webhook_events` PK + `INSERT OR IGNORE` (+ SEC-C3 transaction-wrap still needed).
- requestLogger redacts Authorization/Cookie/CSRF/API-key/password/token/pin/auth.
- `/uploads` path traversal blocked 403 (`/uploads/%2e%2e%2f%2e%2e%2f.env` → 403).
- `.env` not HTTP-reachable (all enumerated paths serve SPA fallback).
- `/super-admin/*` localhostOnly fix shipped in commit 585a06c — BH-S002 / LIVE-03 mitigated, external requests 404 (see DONETODOS.md).
