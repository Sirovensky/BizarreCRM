# POS redesign — visual + interaction plan

Consolidated plan from 7 parallel research agents + the existing Android
`pos-phone-mockups.html` spec. Drives the rewrite of `pos-iphone-mockups.html`
and `pos-ipad-mockups.html` and informs the SwiftUI implementation in
`ios/Packages/Pos/`.

---

## 1. Design tokens

### 1.1 Color

Cream-on-warm-dark theme. WCAG-verified ratios (see research agent 3).

| Token | Hex / rgba | Contrast notes |
|---|---|---|
| `bg-deep` | `#0a0710` | App backdrop — darkest layer |
| `bg` | `#120c1a` | Standard surface |
| `surface-solid` | `#1a1422` | Cards, cart rows, catalog tiles |
| `surface-elev` | `#231a2e` | Elevated cards, popovers |
| `surface-glass` | `rgba(36,31,46,0.55)` | Liquid Glass fill. Composited over `#120c1a` = effective `#1c1625` |
| `outline` | `rgba(255,255,255,0.08)` | Hairline borders |
| `outline-bright` | `rgba(255,255,255,0.16)` | Hover / focused border |
| `primary` | `#fdeed0` | **Cream** — tender CTA, selected states |
| `primary-bright` | `#fff7e0` | Top of CTA gradient |
| `primary-soft` | `rgba(253,238,208,0.14)` | Subtle tint for selection |
| `on-primary` | `#2b1400` | AAA 15.23:1 on cream — always dark-on-cream |
| `on` | `#f2eef9` | Body text on dark — AAA 15.39:1 on glass |
| `muted` | `#b4adc5` | Secondary text — **nudged up from `#a79fb8`** to clear AAA 7.0:1 |
| `muted-2` | `#7e778e` | Tertiary labels |
| `success` | `#34c47e` | Status only — never text on cream |
| `warning` | `#e8a33d` | Status only |
| `error` | `#e2526c` | Status only |
| `teal` | `#4db8c9` | Second accent, link text on dark |

Rules:
- Status colors (teal, success, warning, error) **never appear as text on cream** — all fail WCAG (≤3.24:1). Use dark status-tint (`#7a5200`, `#145c37`) for icon+label on cream chips.
- Cream never used for body text — reserved for primary CTAs + selected pills + brand mark.
- Reduce Transparency auto-swaps glass for `surface-elev` at full opacity (already wired in `DesignSystem/ReduceTransparencyFallback.swift`).

### 1.2 Typography

Existing `BrandFonts.swift` stack. No SF Pro promotion for POS display text.

| Context | Face | Size | Weight | Modifiers |
|---|---|---|---|---|
| Tender hero `$274.51` | Barlow Condensed | 57pt | SemiBold | `.monospacedDigit()`, size-locked |
| Change-due hero | `.system` | 48pt | Bold | locked |
| Cart totals amount | Barlow Condensed | 28pt | SemiBold | monospaced, locked |
| Numpad key | Barlow Condensed | 32pt | SemiBold | monospaced, locked |
| Nav title | Inter | 17pt | SemiBold | scales, cap `.accessibility2` |
| Cart line name | Inter | 16pt | Regular | scales |
| Cart line price | Inter | 14–16pt | Regular | monospaced |
| Catalog tile name | Inter | 14pt | SemiBold | 2-line limit, scales cap |
| Section label | Inter | 14pt | Medium | `UPPERCASE 0.14em` |
| SKU / order ID | JetBrains Mono | 12pt | Regular | native monospace |

### 1.3 Spacing

Existing `BrandSpacing`: `xxs 2 / xs 4 / sm 8 / md 12 / base 16 / lg 24 / xl 32 / xxl 48`.

POS-specific placements:
- Cart row v-padding: `xs` (4pt)
- Tender button v-padding: `md` (12pt) → 50pt total height
- Numpad key: `lg` symmetrical (24pt) → 72pt square
- Catalog tile internal: `md` (12pt)
- Quick-amount chip v-padding: `md` (12pt) → clears 44pt gloved-hand target
- Sheet top padding: `xl` (32pt)

### 1.4 Touch targets

- Primary tender: **56pt min height**, within **120pt of home indicator** on iPhone
- Numpad key: **56×56 iPhone**, **72×72 iPad Pro 12.9"**
- Quick-amount chip: padding bumps to clear 44pt
- Stepper: 36pt frame inside 44pt tap region
- Rail sidebar icon: 48×48 button in 64pt wide column

### 1.5 Motion

Kill with Reduce Motion (replace with 0.15s opacity fade):
- Cart-collapse on receipt
- Sheet-present spring
- List insert stagger
- Catalog tile drag reorder
- Bouncy status change

Keep (always, even with Reduce Motion, as opacity fade):
- Barcode-success 0.18s snappy
- Error state reveal
- Spinner during processing

---

## 2. Liquid Glass primitives

Source: research agent 1. Glass on **chrome only** — not on content.

### 2.1 Where glass goes
- Navigation bar / topbar
- Rail sidebar (iPad) / tab bar (iPhone) chrome
- Pinned bottom tender area background material
- Sheet / inspector background
- Floating badges (connectivity chip, sync indicator)
- Selected tender-method tile

### 2.2 Where glass does NOT go
- Cart rows (content)
- Catalog tiles (content)
- Text body / receipts (content)
- Full-screen backgrounds (solid `bg` instead)
- Stacked glass-on-glass (use `GlassEffectContainer` to merge)

### 2.3 SwiftUI primitives (iOS 26, fallback below)
```swift
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
.glassEffect(.regular.tint(.bizarreCream).interactive())
GlassEffectContainer(spacing: 8) { /* multiple glass children */ }
```
Pre-iOS 26 fallback: `.ultraThinMaterial` + top-highlight gradient + 1px white-alpha border. Wrapped in `DesignSystem/GlassKit.swift`.

### 2.4 HTML approximation
```css
background: rgba(36, 31, 46, 0.55);
backdrop-filter: blur(20px) saturate(180%);
border: 1px solid rgba(255, 255, 255, 0.18);
box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.5),
            0 8px 24px rgba(0, 0, 0, 0.3);
```
Top specular highlight via `::before` gradient mask. Matches iOS 26 `.regular` visual.

### 2.5 Performance budget
- Max **4–5** non-contained glass panels per screen
- Wrap adjacent glass in `GlassEffectContainer` to share one sampling pass
- Profile on iPhone 12 / iPad Pro M1 — simulator doesn't render specular correctly

---

## 3. iPhone architecture

Cream cannot live on bottom-dock search (Android pattern). iOS-native: `.searchable(placement: .navigationBarDrawer(displayMode: .always))` — search pinned below title, always visible.

### 3.1 Layout rules
- Portrait lock (Square / Shopify / Toast precedent)
- `NavigationStack` — no custom back button; edge-swipe is the back gesture
- `.safeAreaInset(edge: .bottom)` for tender CTA — above home indicator
- No FAB (Material pattern banned on iOS)
- Sheet detents for mid-flow editing (line edit, discount, customer attach)

### 3.2 Primary placements
- **Topbar**: customer avatar + name (tap = context menu) + overflow `⋯`
- **Search**: `.navigationBarDrawer(.always)` below topbar — SKU, name, barcode
- **Cart strip**: persistent top or bottom strip with item count + total
- **Catalog**: grid of tiles under search, 2 per row on 6.3" iPhone
- **Bottom safe-area**: Tender CTA full-width, 56pt min, cream fill
- **Sheet-up**: line edit, customer picker, device picker, discount entry

### 3.3 6 frames to render
1. **Cold POS** — customer attach CTAs (walk-in / search / create) bottom safe-area; catalog above (empty-state hint)
2. **Customer attached** — cart strip (empty $0.00); catalog; hero "ready for pickup" card; 3 path chips (retail / repair / credit) collapsed into cart header rather than big tile picker
3. **Cart with items** — 3 cart rows, catalog below (scrollable), pinned tender "$274.51" CTA
4. **Line edit sheet** — `.height(300)` detent, qty stepper + unit price + discount + remove/save
5. **Tender** — method grid (4 tiles) + cash quick-amounts + numpad, all inline scroll; Tender CTA stays pinned
6. **Receipt** — full-width (cart collapsed); hero paid amount; share options (SMS hero, Email, Print, None); next-sale CTA

### 3.4 iOS-specific features
- Dynamic Island live activity (cart total + item count while app backgrounded)
- `sensoryFeedback(.success, trigger:)` on charge complete
- `ShareLink(item:)` for receipt share
- App Intents: `NewSaleIntent`, `AddItemIntent(sku:)`, `FindCustomerIntent(query:)`
- Tap to Pay via `ProximityReader` (entitlement required) — no external card reader
- Lock Screen widget: daily sales + open-carts count

---

## 4. iPad architecture

Shopify POS v11 is the target idiom. Side-panel tender (not full-screen), rail sidebar (custom — no native SwiftUI support), inspector pane for contextual editors, drag-drop-catalog-to-cart **skipped** (no production POS ships it, retail reasons).

### 4.1 Layout anatomy
```
┌─────┬─────────────────────────┬───────────┐
│ R   │ Topbar (search + chips) │           │
│ a   ├─────────────────────────┤           │
│ i   │                         │   Cart    │
│ l   │     Items / Catalog     │  column   │
│     │                         │           │
│ 64p │                         │   420pt   │
└─────┴─────────────────────────┴───────────┘
```

- **Rail** (left, 64pt): custom `VStack` of 8 icon buttons; active tab gets cream pill; brand-mark tap expands to 200pt temporarily. Always visible in POS. `NavigationSplitView(columnVisibility: .detailOnly)` suppresses built-in sidebar.
- **Topbar**: title + search field (top-trailing on iPad per iOS 26 Liquid Glass auto-placement) + operator chip
- **Items column**: Smart Grid tiles + chip filters above + inline actions
- **Cart column** (right, 420pt): persistent. Customer card at top, lines middle, totals + tender CTA at bottom
- **Inspector** (right-most, 320pt): slides in for line edit, device pick, customer detail. Pushes cart column, doesn't overlay
- **NO bottom dock** — Scan goes to `.toolbar(.primaryAction)`, Hold / Clear / Discount go to `.secondaryAction` overflow menu

### 4.2 Primary placements
- `.toolbar(.primaryAction)`: Scan barcode button
- `.toolbar(.secondaryAction)`: Hold cart, Clear cart, Add discount, Add note, Add misc item — auto-collapses to `⋯` menu
- `.toolbar(.topBarLeading)`: Back / Home buttons (when needed)
- `.toolbar(.navigation)`: Customers list button (persistent left icon)
- Tender CTA: bottom of cart column (trailing edge, like Shopify v11)

### 4.3 Side-panel tender (Shopify v11 pattern)
Instead of full-screen takeover, tender opens as **extra column pushed in from right**, OR replaces items area while cart stays visible. Cart never hidden during payment.

Implementation option: `.inspector(isPresented:)` with tender VM. Or dedicated 3rd column that replaces items when active.

### 4.4 5 frames to render
1. **Cold POS** — customer attach glass card in cart column, catalog + chip filters in items area, rail visible, tender CTA disabled
2. **Customer attached, items loaded** — cart customer chip + 3 lines, catalog + recent-items tray, Smart Grid tile "Loyalty $42 avail" appears (cart-state-aware)
3. **Inspector line-edit** — user tapped cart line → inspector slides in right with qty / price / discount / remove. Cart stays visible adjacent to inspector
4. **Side-panel tender** — items area replaced by method grid + cash panel + numpad side-by-side; cart stays right with locked rows
5. **Receipt (cart collapsed)** — cart column animates width `420→0px` (240ms spring or opacity fade with Reduce Motion); receipt + share actions fill canvas; rail stays at 64pt

### 4.5 iPadOS-specific features
- `.inspector(isPresented:)` with `inspectorColumnWidth(min:280, ideal:320, max:400)`
- `.hoverEffect(.highlight)` on rail icons + toolbar buttons
- `.hoverEffect(.lift)` on catalog tiles + customer cards
- `.pointerStyle(.grab)` on draggable tiles (layout editing mode only — not catalog→cart)
- `.contextMenu { } preview: { }` on customer card, cart row, catalog tile
- PencilKit `PKCanvasView` for receipt signature + device photo annotation
- Keyboard shortcuts via `Commands`: `⌘N` new ticket, `⌘K` search, `⌘P` pay, `⌘H` hold, `⌘⇧C` customer, `⌘⇧D` discount
- Multi-window `WindowGroup(id:for:)` for parked-cart second window
- Scribble in all text fields — automatic

### 4.6 Size-class responsiveness
- **Regular ≥ 680pt**: full layout (rail + items + cart + optional inspector)
- **Regular 500–679pt** (Split View half): hide inspector, stack no columns change
- **Compact < 500pt** (Slide Over, 1/3 split): fall through to iPhone layout (rail → bottom tabs, cart → sheet)

---

## 4.7 Service bundles — auto-add paired items

Selecting a service line (e.g. `Labor · screen replacement`) must auto-add its paired part(s) to the cart. The cashier should not have to remember to scan the screen part after picking the labor row.

Data model:
- `inventory_items.bundle_children_json` (server) — array of `{ child_inventory_item_id, default_qty, required: true|false }`. Populated on the Labor row for `screen replacement` with the current compatible screen part for the attached device's make/model.
- Resolution is device-aware: when the customer's device (iPhone 14 Pro) is known from the attached ticket draft, "Labor · screen replacement" resolves `iPhone 14 Pro Screen SKU IPH14P-S` as the paired part. When no device is attached, the cashier gets a modal picker for the right part.
- Optional siblings (screen protector, cleaning kit) are presented as `required: false` chips below the cart line — a tap adds them. Not silently added.

UI behavior:
- Tapping a service tile that has children: service + required children land in the cart in a single atomic `cart.addBundle(...)` call with a single undo. A small pill `bundle · 2 lines added` appears beside the service row for 3 s.
- Catalog tile shows a small link-badge icon if the service has required children; tap preview shows the child list.
- Editing the service qty scales the required-children qty proportionally (1 labor = 1 screen part; 2 labor = 2 screen parts).
- Removing the service line prompts "Remove paired parts too?" — default Yes.

Admin catalog surface:
- `Settings → Repair pricing catalog → <service> → Paired items` — table of child parts with device-model scope, default qty, required flag.

Sequence:
- Cashier attaches customer + device → picks `Labor · screen replacement` from catalog → server-side BOM resolves to `iPhone 14 Pro Screen` part → both land in cart tagged with the bundle id → totals roll up → haptic `.success` + brief pill "2 lines added".

Edge cases:
- Part out of stock: cart still adds but line row shows a red `Low / 0` badge; cashier decides to place on hold / order / substitute.
- Device model not in the BOM map: modal picker fires with filtered parts list matching the device's generic category.
- Walk-in (no device attached): modal picker always fires before add.

Implementation anchor: `ios/Packages/Pos/Sources/Pos/Bundles/ServiceBundleResolver.swift` (new file) + extend existing `PosCatalogGrid` to call `resolver.paired(for:service, device:)` on tap and route through `Cart.addBundle(lines:bundleId:)`.

---

## 5. Workflow rules (Square/Shopify-proven ergonomics)

From research agent 6. Non-negotiable:

1. **Customer attach = optional at any moment**. Prompted ONCE at tender tap if missing. 2s dismissible prompt. Never blocks tender.
2. **Repair ticket = separate entry point** on POS home. `[New Sale]` vs `[New Repair Ticket]`. Ticket path = device-pick → diagnostic → quote → deposit-tender. No mid-flow sale→ticket conversion.
3. **Barcode scan → unique match → auto-add** to cart, skip disambiguation. Only show multi-match sheet if ≥2 hits.
4. **Quick-amount strip above numpad**: `[Exact] [+$5] [+$10] [+$20] [Numpad]`. Always visible for cash.
5. **Split tender = top-level button** on tender screen. Partial-payment count badge when active.
6. **Receipt delivery order**: SMS > Email > Print > None. Preselect SMS if customer+phone attached. No-receipt needs explicit tap.
7. **Hold cart = toolbar icon** (`pause.circle`), never buried in `⋯`. Parked carts = numbered badge on Parked tab. Works offline.
8. **Discount placement**: line-level via row context-menu (best), cart-level via pinned coupon field, tender-only = **banned** (highest forgotten-apply rate).
9. **Catalog for 1000+ SKUs**: sticky search + 6–8 category chips (single-tap filter) + recent-items tray (last 10). <3 taps to any item. Search <300ms. No product-detail-page drill-in.
10. **Error recovery**:
    - Every destructive action (void, remove, refund) = exactly one confirmation tap
    - Card declined → toast + "Different Method" CTA, DON'T clear cart
    - Swipe-left cart row = void (≤2 taps anywhere)
    - Never >3s blank spinner without actionable copy
11. **First-transaction target**: <15min for new hire. Home = exactly 2 primary actions. Single obvious CTA per screen. Training Mode toggle for safe simulation.
12. **Post-sale cart collapse**: on Receipt screen, cart column width `420→0px` on iPad (or swap to full-width receipt on iPhone). Next-sale CTA in toolbar triggers re-expand.

---

## 6. HTML mockup generation

Two files regenerate:

### 6.1 `pos-iphone-mockups.html`
- 6 iPhone 16 Pro frames (390×844, Dynamic Island)
- Cream palette, verified WCAG ratios
- Nav-bar-drawer search pattern
- Safe-area-inset tender CTA
- `.sheet` detents for line-edit / tender
- Dynamic Island live-activity preview frame (stretch bonus)

### 6.2 `pos-ipad-mockups.html`
- 5 iPad Pro 11" frames (1194×834, landscape)
- Custom rail sidebar (64pt, icon-only, cream-pill active)
- 3-column layout: rail + items + cart
- Inspector-pane line-edit frame
- Side-panel tender frame (Shopify v11 idiom)
- Receipt frame with cart collapsed to 0px, items area expanded

Both mockups:
- Cream `#fdeed0` as primary, dark `#2b1400` on-primary
- Liquid Glass chrome only (topbar, rail, toolbar, inspector, tender area)
- Solid `surface-solid` for cart rows, catalog tiles, receipts
- 1px hairline gradient border + top-highlight on glass panels
- `backdrop-filter: blur(20px) saturate(180%)` as iOS-26-equivalent
- Self-contained, no JS, no network
- Design principles summary section at bottom matching this plan

### 6.3 SwiftUI implementation crosswalk
Every mockup element maps to an existing or planned SwiftUI type in `ios/Packages/Pos/` or `ios/Packages/DesignSystem/`. Mockup tokens (CSS custom properties) mirror `BrandColors.swift` and `BrandSpacing.swift` so HTML→Swift is a direct port.

| Mockup element | Swift type |
|---|---|
| Rail sidebar | `POSRailSidebarView` (new, in `App/` or `Packages/Core/`) |
| Topbar | `NavigationStack` + `.toolbar` items |
| Items grid | `PosSearchPanel` / `PosCatalogGrid` |
| Cart column | `PosCartPanel` (existing) |
| Inspector pane | `.inspector(isPresented:)` + new `PosLineEditInspectorView` |
| Side-panel tender | `PosTenderSelectSheet` + `PosCashTenderSheet` adapted to inspector column |
| Numpad | `PosNumpadView` (existing + gloved-hand sizing bump) |
| Tender CTA | `PosChargeButton` (existing + Barlow hero amount) |
| Path picker tiles | New `PosHomeCardGrid` — only two cards (Sale / Repair) |
| Context menus | `.contextMenu { } preview: { }` on cart rows + customer card |

---

## 7. Open questions parked

- Dynamic Island live-activity copy: "Cart: 3 items · $274.51" vs "In Progress · $274.51"? Pilot test needed.
- Apple Pay via Tap to Pay on iPhone — entitlement approval takes weeks; stage behind feature flag.
- Training mode data isolation: uses a separate SQLCipher DB or a flag on the real DB? Security review needed.
- Multi-window parked-cart sync — single `@Observable` vs scene-scoped? Covered in agent-ownership follow-up.

---

## 8. Delivery

Both HTML mockups regenerated from this plan in the same PR.
Commit: `docs(pos): add iPhone + iPad Liquid Glass mockups + redesign plan`.
ActionPlan.md gets a new §16.0 "POS redesign plan" pointer to this file.
