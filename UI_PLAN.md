# UI/UX Overhaul Plan — Workflow & Interaction Focus

**Goal:** Make every page faster, more intuitive, and require fewer clicks for daily repair shop tasks.
**Not about:** Colors, fonts, or visual style (already good). This is about HOW users interact.

**Research sources:**
- [Rossmann Group Forum: RepairDesk vs RepairShopr](https://boards.rossmanngroup.com/threads/recommendations-on-repairdesk-vs-repairshopr.44374/) — users hate when UI changes make sending ticket updates cumbersome
- [CellSmartPOS: 5 Features You Need](https://www.cellsmartpos.com/blog/cell-phone-repair-shop-management-software) — integrated POS, reporting, customer portal
- [RepairDesk vs RepairQ comparison](https://blog.repairdesk.co/2024/03/15/repairdesk-vs-repairq-the-best-pos-software-for-cell-phone-repair-shops/) — workflow speed is the #1 differentiator
- [SoftwareAdvice Reviews](https://www.softwareadvice.com/crm/repairshopr-profile/reviews/) — RepairShopr users frustrated with broken kiosk, bad reporting

**Key insight from research:** Repair shop staff do the SAME 5 tasks 50x/day. Every extra click, scroll, or page load is multiplied by thousands. The fastest CRM wins.

---

## PRINCIPLES (apply to every page)

### P1. One-Click Actions
Every common action should be ONE click, not click → modal → confirm → done. Use inline editing, instant toggles, and immediate feedback.

### P2. Keyboard-First for Power Users
Techs have greasy hands and use keyboards more than mice. Every major action needs a keyboard shortcut. Search should be instant (Ctrl+K already exists — good).

### P3. Zero-Scroll for Critical Info
The most important information on any page should be visible WITHOUT scrolling on a 1080p monitor. If users scroll to see ticket status or customer phone, that's a failure.

### P4. Smart Defaults
Pre-fill everything possible. If the last 10 tickets used "Screen Replacement" as the service, suggest it first. If a customer always has iPhones, show Apple devices first.

### P5. Progressive Disclosure
Show simple view by default, expand details on demand. Don't overwhelm new staff with 15 fields when they only need 3.

### P6. Instant Feedback
Every action shows immediate visual feedback. No "did my click work?" moments. Toasts, inline status changes, optimistic updates.

---

## PAGE-BY-PAGE PLAN

### 1. POS / CHECK-IN PAGE (Most used — 50+ times/day)

**Current workflow:** Search customer → Select category → Select manufacturer → Search device → Select service → Fill details → Add to cart → Create ticket
**Problem:** 8 steps is too many. RepairDesk does it in 4-5.

#### Changes:
- [ ] **UX1.1 — Unified command bar replaces 3 search fields.** Single input at top: type customer name, phone, ticket ID, or IMEI and get instant categorized results. Already partially built (UnifiedSearchBar) but needs to be THE primary input, larger and more prominent.
- [ ] ~~UX1.2~~ **REMOVED** — Most customers are new/infrequent. Recent customers list not useful.
- [ ] **UX1.3 — Returning customer auto-context.** When customer selected, if they have a previous iPhone repair, auto-suggest "iPhone" as category and last service used. Skip category selection entirely for repeat customers.
- [ ] ~~UX1.4~~ **REMOVED** — We want thorough check-ins, not quick ones. Every device should go through the full intake flow with conditions, passcode, photos, etc.
- [ ] **UX1.5 — Cart should show key device details inline.** Currently shows "iPhone 16 - Screen Replacement $80". Add a small expandable arrow that reveals IMEI and passcode only — keep it compact, not overwhelming.
- [ ] **UX1.6 — "Create Ticket" should be the primary action, not "Checkout".** 90% of POS interactions create tickets, not ring up sales. Make "Create Ticket" the big green button, "Checkout" secondary.
- [ ] **UX1.7 — Photo capture during check-in, not after.** During the device details step (DETAILS in repair flow), add a prominent "Send Photo Prompt to Mobile" button. This sends a link/QR to the customer's or tech's phone to upload photos of device condition right during intake. Photos are captured AS PART of check-in, not as an afterthought. Also show "Print Label" + "Next Customer" on the success screen.
- [ ] **UX1.8 — Keyboard shortcuts.** F2 = New ticket. F3 = Customer search focus. F4 = Print last receipt. ESC = Cancel/back.
- [ ] **UX1.9 — Sound feedback on scan.** When barcode scanner sends input, play a beep sound to confirm scan detected. Visual-only feedback is missed in noisy shops.

### 2. TICKET LIST PAGE (Viewed 30+ times/day)

**Current workflow:** Scroll list → Find ticket → Click to open → Read details → Change status → Go back
**Problem:** Too much clicking between list and detail views.

#### Changes:
- [ ] **UX2.1 — Expandable row preview (HIGH PRIORITY).** Single-click a ticket row → expands a compact inline card below the row showing: device name + IMEI/serial | customer phone (clickable tel: link) + email | current issue | last note with timestamp | assigned tech | parts status (in stock/missing). All on 2-3 lines max — dense but scannable. "Open Full" button and "Add Note" inline input in the preview. Double-click row → navigates to full detail page. This eliminates 80% of detail page visits.
- [ ] ~~UX2.2~~ **REMOVED** — Keyboard status shortcuts too error-prone. Inline dropdown already works fine.
- [ ] **UX2.3 — Quick note from list.** "Add note" icon on each row → opens small inline input → type note → Enter to save. No page navigation needed.
- [ ] **UX2.4 — Stale ticket highlighting.** Tickets unchanged for >3 days get amber background. >7 days get red. Makes it obvious what needs attention.
- [ ] **UX2.5 — "My Tickets" quick filter.** One-click button to filter to assigned-to-me tickets. Most techs only care about their own queue.
- [ ] **UX2.6 — Kanban view as third view option.** Add a "Kanban" toggle alongside List and Calendar. Drag tickets between status columns. This is an OPTIONAL view — list view stays the default and primary. Kanban endpoint already exists.
- [ ] ~~UX2.7~~ **REMOVED** — Not a common enough workflow to prioritize.
- [ ] **UX2.8 — Last updated age column.** Show "2d ago" or "5h ago" for the last update time instead of absolute date. Format: "3h ago", "2d ago", "1w ago". Faster to scan when looking for stale tickets.
- [ ] **UX2.9 — Quick SMS button per ticket row.** Small message icon next to the customer name or phone column. Click → opens inline SMS compose popup (same as UX3.4 but from the list). Send a quick update without leaving the list.

### 3. TICKET DETAIL PAGE (Opened 20+ times/day)

**Current workflow:** Scroll through long page → Find the section you need → Edit → Save
**Problem:** Too much vertical scrolling. Notes buried at bottom.

#### Changes:
- [ ] **UX3.1 — Tabbed layout instead of scroll (EXPERIMENTAL — implement last).** Replace vertical scroll with tabs: "Overview | Notes | Parts | Photos | History". Risky — could make navigation worse if done wrong. Try it, but keep ability to revert to scroll layout if it doesn't feel right.
- [ ] **UX3.2 — Sticky status bar at top.** Status dropdown + Assigned To + Due Date always visible at top, even when scrolled. These are the most-checked fields.
- [ ] **UX3.3 — Quick note input always visible.** Note input field pinned at bottom of page (like a chat input). Type → Enter → note added. Don't make users click "Add Note" button first.
- [ ] **UX3.4 — Click phone → call or text popup.** Customer phone number is clickable. Opens a small popup: "Call" (tel: link) | "Text" (opens inline SMS compose popup right on the ticket page, pre-filled with customer phone). No page navigation to Communications needed.
- [ ] **UX3.5 — Part status chips (maybe).** Each part shows its status as colored chip: green (in stock), amber (ordered), red (missing). Click chip to change status. Low priority — evaluate if useful.
- [ ] **UX3.6 — Photo grid (compact).** Show uploaded photos as small thumbnail grid. Click to enlarge. Keep drag-drop zone small — most photos come from mobile upload, not desktop drag-drop. Don't make it dominate the page.
- [ ] ~~UX3.7~~ **REMOVED** — Timer not needed for current workflow.
- [ ] **UX3.8 — "Checkout Ticket" action.** When ticket status is a "completed" type, show a prominent green banner: "Ready for pickup — Checkout". Clicking it should go to POS with this ticket pre-loaded in cart, auto-convert to invoice AND process payment in one flow. Not just "convert to invoice" — full checkout including payment method selection.

### 4. CUSTOMER LIST PAGE (10+ times/day)

#### Changes:
- [ ] **UX4.1 — Inline customer preview on hover.** Hover over customer name → tooltip shows phone, email, last ticket, total spent. No need to open detail page for quick info.
- [ ] **UX4.2 — Click phone to call.** Phone column should be `tel:` link. Click to dial from 3CX.
- [ ] **UX4.3 — "Create Ticket for Customer" action.** In the actions column, add "New Ticket" button that goes to POS with customer pre-selected.
- [ ] **UX4.4 — Customer search auto-selects on Enter (setting).** When searching, pressing Enter navigates to the first result. Make this a toggle in Settings — some staff may prefer explicit click selection.

### 5. CUSTOMER DETAIL PAGE

#### Changes:
- [ ] **UX5.1 — Ticket history timeline.** Show tickets as a visual timeline, not a table. Each entry shows date, device, status, amount. Click to expand.
- [ ] **UX5.2 — Customer lifetime value card.** Show total spent, ticket count, average ticket value prominently at top. Already have the analytics endpoint — needs UI.
- [ ] **UX5.3 — Warranty alert.** If any device is under warranty, show a green badge: "Warranty active until [date]". Uses warranty-lookup endpoint.
- [ ] **UX5.4 — Quick action buttons.** "New Ticket" | "Send SMS" | "Create Estimate" buttons always visible at top. "New Ticket" must navigate to POS with this customer pre-selected (skip customer search step).

### 6. INVOICE LIST & DETAIL

#### Changes:
- [ ] ~~UX6.1~~ **REMOVED** — Payment recording should stay deliberate with full form. Shortcuts risk accidental wrong payments that are hard to reverse.
- [ ] **UX6.2 — Outstanding balance highlight.** Invoices with amount_due > 0 should have red left-border accent. Paid = green.
- [ ] **UX6.3 — Send receipt after payment.** After payment recorded, show options: "Print Receipt" | "SMS Receipt" | "Both". SMS sends formatted receipt message with amount, ticket ID, and store info. Also TODO: make receipt viewable on customer portal (link in SMS).

### 7. INVENTORY PAGE

#### Changes:
- [ ] **UX7.1 — Low stock amber highlight is fine.** Current amber badge is acceptable. No change needed — pulsing animations would be distracting.
- [ ] **UX7.2 — Quick stock adjustment from list (careful placement).** "+/−" buttons in the stock column, but spaced apart to prevent misclicks. Only implement if buttons can be placed safely — if too easy to accidentally click, skip this.
- [ ] **UX7.3 — Reorder button.** When item is low stock, show "Reorder" button that opens supplier URL in new tab.

### 8. COMMUNICATIONS / SMS PAGE

#### Changes:
- [ ] **UX8.1 — Unread conversations always at top.** Unread threads should float to top regardless of last message time (already pinned first).
- [ ] **UX8.2 — Quick open ticket from notification.** When SMS notification appears in bell dropdown, show "View Ticket" button (not reply). Opens the related ticket so you can see context before responding. Prevents replying to wrong person with wrong info.
- [ ] **UX8.3 — Ticket info embedded in right panel.** When viewing an SMS conversation, the right side (or a collapsible sidebar) shows the customer's open tickets with device name, status, and issue — always visible while composing. Not just a link — actual embedded info so you always know what you're discussing.
- [ ] ~~UX8.4~~ **REPLACED** — No auto-substitution. Keep the existing template picker button in compose bar. Templates are selected manually, not auto-suggested. Already built.

### 9. REPORTS PAGE

**NOTE: Reports are currently broken/incomplete. Fix core functionality FIRST, then add UX improvements.**

#### Must Fix First:
- [ ] **UX9.0a — Fix Sales report** — verify data accuracy, totals match invoices
- [ ] **UX9.0b — Fix Ticket report** — verify by-status and by-day counts are correct
- [ ] **UX9.0c — Fix Employee report** — verify hours and commissions data
- [ ] **UX9.0d — Fix Inventory report** — verify low stock and value calculations
- [ ] **UX9.0e — Fix Tax report** — verify tax collected matches actual invoices

#### Then UX Improvements:
- [ ] **UX9.1 — "Today" button.** Quick button to set date range to today. Most common use case.
- [ ] **UX9.2 — Drill-down on charts.** Click a bar in "Popular Models" chart → filters ticket list to that model. Charts should be interactive, not just visual.
- [ ] **UX9.3 — Daily summary card.** At the top of dashboard: "Today: $X revenue, Y tickets closed, Z parts ordered" — visible at a glance without scrolling.

### 10. SETTINGS PAGE

#### Changes:
- [ ] **UX10.1 — Search settings.** With 14 tabs and dozens of toggles, add a search/filter. Type "warranty" → highlights the warranty default setting.
- [ ] **UX10.2 — Preview for print settings.** When editing receipt terms/footer, show a live preview of what the receipt will look like.
- [ ] **UX10.3 — Dangerous actions need confirmation.** "Delete status" should require typing the status name, not just a confirm dialog.

### 11. GLOBAL / CROSS-PAGE

#### Changes:
- [ ] **UX11.1 — Breadcrumb navigation everywhere.** Every detail page should show: Home > Tickets > T-2902. Click any level to go back.
- [ ] **UX11.2 — Global keyboard shortcuts panel.** Press "?" to show all available keyboard shortcuts overlay.
- [ ] **UX11.3 — "Last viewed" in sidebar.** Show the 3 most recently viewed tickets/customers at the bottom of the sidebar for quick back-navigation.
- [ ] **UX11.4 — Persistent draft saving.** If a user starts creating a ticket and navigates away, the draft should be saved. "You have an unsaved draft" notification on return.
- [ ] **UX11.5 — Loading skeleton consistency.** Every page should show skeleton loaders (gray pulsing rectangles) while data loads. Currently some show spinners, some show nothing.
- [ ] **UX11.6 — Empty state consistency.** Every empty list should show: icon + message + primary action button. "No tickets yet — Create your first ticket".
- [ ] **UX11.7 — Toast positioning.** Toasts should appear at top-right, not overlap with the header. Auto-dismiss after 3 seconds.
- [ ] **UX11.8 — Confirm dialog consistency.** Replace `window.confirm()` with custom styled modal that matches the dark theme. Browser confirm looks jarring.

---

## PRIORITY ORDER (by daily impact)

### Phase 1: Quick Wins (1-2 days, massive daily impact)
1. UX2.4 — Stale ticket highlighting
2. UX2.8 — Relative time in ticket list ("2d ago")
3. UX3.3 — Quick note input always visible
4. UX1.6 — Make "Create Ticket" the primary button
5. UX4.2 — Click phone to call
6. UX6.2 — Outstanding balance highlight on invoices
7. UX11.8 — Replace window.confirm() with styled modals

### Phase 2: Workflow Improvements (3-5 days)
8. UX2.1 — Expandable row preview in ticket list
9. UX3.1 — Tabbed ticket detail layout
10. UX3.2 — Sticky status bar
11. UX1.2 — Recent customers quick-pick
12. UX1.4 — Quick Check-in mode
13. UX5.2 — Customer lifetime value card
14. UX7.2 — Quick stock adjustment from list

### Phase 3: Power User Features (5-7 days)
15. UX1.8 — Keyboard shortcuts
16. UX2.6 — Kanban drag-and-drop
17. UX8.4 — Auto-suggest templates
18. UX11.2 — Global shortcuts panel
19. UX11.4 — Persistent draft saving
20. UX1.3 — Returning customer auto-context

### Phase 4: Polish (ongoing)
21. All remaining items
22. Accessibility audit pass
23. Mobile/tablet optimization

---

---

## ADDITIONAL RESEARCH FINDINGS

### From [Fixably: How to Set Up an Efficient Repair Shop](https://www.fixably.com/blog/how-to-set-up-an-efficient-repair-shop)
- **Check-in macros**: Guided intake that FORCES verification of critical steps (e.g., "Is Find My iPhone disabled?"). We should add mandatory check prompts per device type.
- **Auto-assign by certification**: Match device models to certified techs automatically. We have assigned_to but no auto-assignment logic.
- **Centralized workflow**: Techs should NEVER leave the CRM. Every action (diagnose, order part, message customer, print label) should be doable from the ticket detail page.
- **Structured inspection templates**: Pre-built diagnostic workflows (we have condition checklists — should make them more prominent in the flow).

### From [Orderry: Top 10 Features](https://orderry.com/blog/top-features-for-repair-shop-software/)
- **Beginner-friendly**: Clear menus, tutorials, familiar layouts. Our UX should feel like "I already know how to use this" to new staff.
- **Mobile access**: Techs should be able to update ticket status from a phone/tablet on the shop floor. Our responsive design needs work here.

### From [CRM Dashboard Best Practices](https://www.explo.co/blog/crm-dashboards-key-elements-best-practices)
- **5-7 metrics max** visible on dashboard. Our dashboard shows 8 KPI cards — consider consolidating.
- **Role-based views**: Owner wants revenue/profit. Tech wants their queue. Front desk wants check-in/pickup counts. We show same dashboard to everyone.
- **Link to next action**: Every metric should link to what to DO about it. "3 parts missing" → click → parts order page.

### From [Kanban Board for CRM](https://msdynamicsworld.com/blog/complete-guide-using-kanban-boards-dynamics-365-crm)
- **Swim lanes by tech**: Kanban columns = statuses, rows = assigned technician. Visual at a glance.
- **Drag-and-drop triggers actions**: Dragging to "Closed" should auto-prompt invoice creation. Dragging to "Waiting for Parts" should auto-create parts order.
- **Color coding**: Card color = urgency. Red border = overdue. Amber = approaching due date.

---

## ADDITIONAL UX ITEMS FROM RESEARCH

### Check-In Flow Improvements
- [ ] **UX1.10 — Check-in macros/prompts.** Per-category mandatory prompts: Phone → "Is Find My disabled?", "Passcode?", "Backup data?". Laptop → "Charger included?", "Admin password?". Prevents forgetting critical intake info.
- [ ] **UX1.11 — Device photo prompt.** After entering device details, prompt "Take photos of device condition?" with QR code for phone camera. Make it part of the flow, not an afterthought.

### Technician Workflow
- [ ] **UX12.1 — Tech workload dashboard.** New page/view: shows each tech's assigned tickets as cards, grouped by status. Service advisors use this to dispatch work.
- [ ] **UX12.2 — "My Queue" sidebar widget.** In sidebar, show assigned ticket count badge. Click → filtered view of my tickets sorted by priority.
- [ ] **UX12.3 — Quick status update from anywhere.** Global shortcut: Ctrl+Shift+S → type ticket ID → select new status. No page navigation needed.

### Customer Communication Efficiency
- [ ] **UX13.1 — Auto-SMS on key status changes.** Already implemented (CRM1) — ensure all common statuses have templates.
- [ ] **UX13.2 — Customer preference for contact method.** Store "prefers SMS" vs "prefers email" vs "prefers phone call" per customer. Show icon on customer record.
- [ ] **UX13.3 — Scheduled follow-up.** After closing ticket, offer "Schedule follow-up in 7 days?" → creates a reminder to check if customer is satisfied.

### Dashboard Improvements
- [ ] **UX14.1 — Role-based dashboard.** Admin sees revenue + profit. Tech sees their queue + today's repairs. Cashier sees payments + outstanding invoices.
- [ ] **UX14.2 — Actionable metrics.** Every KPI card is clickable: "3 parts missing" → goes to parts order page. "$230 outstanding" → goes to unpaid invoices.
- [ ] **UX14.3 — "Needs Attention" section.** Top of dashboard: stale tickets (>3 days), unanswered SMS, low stock items. Grouped by urgency.

---

## METRICS TO TRACK
After implementing, measure:
- **Clicks to create a ticket** (target: 4 or fewer from empty POS)
- **Time from customer walk-in to ticket printed** (target: under 60 seconds)
- **Scrolls to find ticket status** (target: 0)
- **Daily page loads per user** (lower = users find what they need faster)
- **Time to change ticket status** (target: under 2 seconds, no page navigation)
- **Number of apps/tabs tech uses** (target: 1 — everything in the CRM)
