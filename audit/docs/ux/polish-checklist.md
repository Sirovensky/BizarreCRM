# UX Polish Checklist — §72

Cross-cutting requirements for every screen and component in BizarreCRM iOS.
Tracks against `ios/ActionPlan.md §72`. Lint enforcement via `ios/scripts/ux-polish-lint.sh`.

---

## Empty States

- [ ] Every screen has a dedicated empty state — no blank white void.
- [ ] Empty states use `EmptyStateCard` (`DesignSystem/Polish/EmptyStateCard.swift`).
- [ ] Tickets empty: CTA "Add first ticket" or "Import from contacts".
- [ ] Customers empty: CTA "Add first customer" or "Import from contacts" (CNContactStore).
- [ ] SMS empty: CTA "Connect SMS provider" → Settings §SMS.
- [ ] POS empty: CTA "Connect BlockChyp" → Settings §Payment; "Cash-only POS" enabled by default.
- [ ] Reports empty: placeholder chart with "Come back after your first sale".
- [ ] Inventory empty: CTA "Add first item" or "Import from CSV".
- [ ] Dashboard empty: onboarding checklist card (§71 first-day wizard).
- [ ] Every `EmptyStateCard` has `icon`, `title`, `message`, at least one `primaryAction`.
- [ ] Empty state a11y: container has `.accessibilityElement(children: .combine)`.

---

## Pull-to-Refresh

- [ ] Every `List` has `.refreshable { }` bound to a ViewModel async refresh method.
- [ ] Dashboard overview has pull-to-refresh on the scroll root.
- [ ] Refresh indicator does not fight skeleton shimmer — skeleton shows on first load only, refresh uses system indicator on reload.
- [ ] Offline: pull-to-refresh shows "Last synced Xh ago" toast on failure.

---

## Destructive Action Confirmation

- [ ] Every "Delete" button uses `Button(role: .destructive)`.
- [ ] Every destructive action shows `.confirmationDialog` before executing.
- [ ] Confirmation dialog copy: "Are you sure?" + specific consequence ("This ticket will be permanently deleted.").
- [ ] Swipe-to-delete on list rows shows red background + trash icon before confirm.
- [ ] Bulk delete confirmation names count ("Delete 3 tickets?").

---

## Save / Cancel Visibility

- [ ] Every sheet/form has "Save" (or "Done") and "Cancel" in the toolbar.
- [ ] "Save" is `.principal` or trailing toolbar item; "Cancel" is leading.
- [ ] Disabled "Save" when form is pristine (no changes) or invalid.
- [ ] `.interactiveDismissDisabled(formIsDirty)` prevents accidental swipe-dismiss on dirty forms.
- [ ] On dismiss with unsaved changes: `.confirmationDialog("Discard changes?")`.

---

## Keyboard Types and Submit Labels

- [ ] Every `TextField` carrying a phone number: `.keyboardType(.phonePad)`.
- [ ] Every `TextField` carrying an email: `.keyboardType(.emailAddress)`.
- [ ] Every `TextField` carrying a URL: `.keyboardType(.URL)`.
- [ ] Every numeric entry field: `.keyboardType(.decimalPad)` or `.numberPad`.
- [ ] Every `TextField` has `.submitLabel(...)` matching its role (`next`, `done`, `search`, `go`, `send`).
- [ ] Last field in a form uses `.submitLabel(.done)` and dismisses keyboard.
- [ ] `.onSubmit` chains focus to the next field via `@FocusState`.

---

## Error States and Recovery Hints

- [ ] Every network error shows a recoverable message ("Couldn't load tickets — tap to retry").
- [ ] Every error uses `EmptyStateCard` in error configuration (red icon, retry action).
- [ ] No raw error codes or developer strings shown to users.
- [ ] Validation errors appear inline below the relevant field, not only in a toast.
- [ ] Offline errors: distinguish "no connection" from "server error" in copy.
- [ ] Recovery action is always present: retry button, go-to-settings link, or dismiss.

---

## Long Operation Progress

- [ ] Every async operation lasting >300ms shows `ProgressView` or skeleton shimmer.
- [ ] Skeleton (`SkeletonShimmer`) used for initial list loads — not spinner.
- [ ] Spinners (`ProgressView`) used for in-line actions (save, upload, pay).
- [ ] Upload progress: `ProgressView(value:total:)` with percentage label.
- [ ] Shimmer disabled when Reduce Motion is on (cross-fade only).
- [ ] Skeleton never jumps to content without cross-fade (§72.4).
- [ ] Progress views have `.accessibilityLabel("Loading…")`.

---

## iPad Hover Effects

- [ ] Every tappable `List` row has `.hoverEffect(.highlight)`.
- [ ] Every card/button used on iPad has `.hoverEffect(.lift)` or `.highlight`.
- [ ] Hover effects gated on `Platform.isCompact == false` where needed.
- [ ] `.buttonStyle(.plain)` rows use explicit `.hoverEffect(.highlight)` (system doesn't add it automatically).

---

## Accessibility Labels on SF Symbols

- [ ] Every `Image(systemName:)` used decoratively: `.accessibilityHidden(true)`.
- [ ] Every `Image(systemName:)` used as standalone meaning-bearing icon: `.accessibilityLabel("…")`.
- [ ] Icons inside `Label("title", systemImage:)` inherit label's a11y — no double-labeling.
- [ ] `Button { Image(systemName:) }` has `.accessibilityLabel` on button (not image).
- [ ] No unlabeled icon-only buttons reach production — CI `XCUIAccessibilityAudit` catches these.

---

## SF Symbol Rendering Mode

- [ ] Every `Image(systemName:)` meant to accept `.foregroundStyle(color)`: `.symbolRenderingMode(.template)`.
- [ ] Multicolor / hierarchical symbols (e.g., `exclamationmark.triangle.fill`): `.symbolRenderingMode(.multicolor)` or `.hierarchical`.
- [ ] Palette rendering used for two-tone brand icons: `.symbolRenderingMode(.palette)`.
- [ ] No symbol has rendering mode omitted when a color is explicitly applied — this causes inconsistent tinting.

---

## Chip Shape and Design-Token Padding

- [ ] Every filter chip / tag chip uses `Capsule()` shape.
- [ ] Chip horizontal padding: `DesignTokens.Spacing.md` (12pt).
- [ ] Chip vertical padding: `DesignTokens.Spacing.xs` (4pt) to `DesignTokens.Spacing.sm` (8pt).
- [ ] Chip font: `.caption` or `.footnote` semibold — never `.body`.
- [ ] Selected chip uses `.bizarreOrange` fill; unselected uses `.bizarreSurface2`.
- [ ] Chip text contrast meets WCAG AA (4.5:1) in both light and dark.

---

## Toast Behavior

- [ ] Every toast is a glass pill (`ToastPresenter` in `DesignSystem/Polish/ToastPresenter.swift`).
- [ ] Success toasts auto-dismiss after 4 seconds.
- [ ] Error toasts auto-dismiss after 5 seconds (more time to read).
- [ ] Every toast is tap-to-dismiss.
- [ ] Maximum 3 toasts stacked at once; oldest pushed off bottom.
- [ ] Toast stacks from bottom of screen above tab bar / home indicator.
- [ ] Toasts have `.accessibilityElement(children: .combine)` + `.accessibilityAddTraits(.isStaticText)`.
- [ ] Reduce Motion: toast appears/disappears with opacity only (no slide).

---

## Modal Drag-Dismiss Indicator

- [ ] Every `.sheet` and `.bottomSheet` shows `DragDismissIndicator` at top.
- [ ] Indicator: 36×4pt rounded pill, `.bizarreOnSurfaceMuted` at 40% opacity.
- [ ] Indicator visible in both light and dark modes.
- [ ] Reduce Motion: indicator fades in rather than sliding.
- [ ] Full-screen `.navigationDestination` pushes do NOT show drag indicator (swipe-back is the gesture).

---

## Back-Stack Preservation

- [ ] Cross-package navigation (e.g., Tickets → Customer detail) preserves back-stack.
- [ ] Deep-link into a detail view synthesizes intermediate stack entries where possible.
- [ ] Tab switch preserves each tab's own navigation stack.
- [ ] No `NavigationStack` gets reset on tab re-select unless user is already at root.

---

## Monospaced Numbers

- [ ] Every currency amount: `.monospacedDigit()` applied via `MonospacedDigits` modifier.
- [ ] Every counter / badge number uses `.monospacedDigit()`.
- [ ] Animated counters use `.contentTransition(.numericText())` for smooth digit roll.
- [ ] JetBrains Mono used for large numeric displays (totals, receipt amounts).

---

## Currencies as Cents

- [ ] All monetary values stored and passed as `Int` cents (never `Double`).
- [ ] Display formatting done with `Decimal(cents) / 100` + `Decimal.FormatStyle.Currency`.
- [ ] No `Double` arithmetic on money — prevents floating-point drift.
- [ ] `Text("$\(someDouble)")` is a lint error (`ux-polish-lint.sh` catches it).

---

## Checklist Meta

| Category | Items | Status |
|---|---|---|
| Empty States | 11 | pending |
| Pull-to-Refresh | 4 | pending |
| Destructive Confirmation | 5 | pending |
| Save/Cancel | 5 | pending |
| Keyboard Types | 7 | pending |
| Error + Recovery | 6 | pending |
| Progress / Skeleton | 7 | pending |
| iPad Hover | 4 | pending |
| A11y Labels | 5 | pending |
| Symbol Rendering | 4 | pending |
| Chip Shape | 6 | pending |
| Toast | 8 | pending |
| Modal Indicator | 5 | pending |
| Back-Stack | 4 | pending |
| Monospaced Numbers | 4 | pending |
| Currencies as Cents | 4 | pending |

**Total: 99 items**

Lint script: `ios/scripts/ux-polish-lint.sh`
Audit harness: `ios/Tests/PolishTests.swift`
Design system components: `ios/Packages/DesignSystem/Sources/DesignSystem/Polish/`
