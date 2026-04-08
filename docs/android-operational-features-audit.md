# Android App Operational Features Audit

**Date:** 2026-04-05
**Scope:** Inventory, POS, invoices, expenses, reports, employees, leads, estimates, catalog, calendar, cash register, and related operational features.

---

## Current Android App State

The BizarreSMS app has exactly 4 screens:
- **ConversationListScreen** -- SMS inbox
- **ChatScreen** -- SMS conversation thread
- **TicketDetailScreen** -- Read-only view of ticket data (fetched from RepairDesk API)
- **SettingsScreen** -- App configuration

It has zero operational/business features. The entire app is an SMS client with ticket lookup.

---

## 1. Complete List of Missing Operational Features

### A. Inventory Management
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Inventory list with search, filter by type/category/manufacturer | Full CRUD | Nothing |
| Inventory detail view (item info, pricing, stock level, history) | Full view + edit | Nothing |
| Stock adjustment (manual, purchase, return, defective write-off) | Full | Nothing |
| Low stock alerts / reorder level warnings | Dashboard widget | Nothing |
| Inventory create (product, part, service) | Full form | Nothing |
| Bulk operations (price adjustment, import/export CSV) | Full | Nothing |
| Column visibility preferences | Saved per-user | Nothing |
| Advanced filters (manufacturer, supplier, price range, out-of-stock toggle) | Full | Nothing |
| Purchase orders (create, list, status tracking) | Full CRUD | Nothing |
| Barcode/UPC lookup | Search by barcode | Nothing |

### B. POS / Checkout System
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Unified POS (repairs + products + misc items in one cart) | Full system | Nothing |
| Customer selection / search in POS | Inline search | Nothing |
| Repair check-in wizard (category > device > service > details) | Multi-step wizard | Nothing |
| Product search and add to cart | Search + barcode | Nothing |
| Misc item entry (ad-hoc line items) | Full | Nothing |
| Barcode scanner integration (keyboard wedge) | Auto-detect | Nothing |
| Cart management (quantities, discounts, tax toggle) | Full | Nothing |
| Checkout modal (Cash / Card / Other payment methods) | Full with change calculation | Nothing |
| Quick cash buttons (exact, round-up amounts) | Full | Nothing |
| Customer signature capture | Canvas component | Nothing |
| Post-checkout success screen (print receipt, view ticket/invoice) | Full | Nothing |
| Ticket hydration from URL (load existing ticket into POS) | Full | Nothing |
| Inactivity timeout with auto-reset | 10-minute timer | Nothing |
| Member/group discount auto-application | Full | Nothing |

### C. Cash Register
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Daily cash summary (in/out/payments/balance) | Full dashboard | Nothing |
| Cash-in / cash-out recording | Full with reasons | Nothing |
| Transaction history | Scrollable list | Nothing |

### D. Invoice Management
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Invoice list with search, status filters, date range | Full with KPIs | Nothing |
| Invoice detail view (line items, payments, status) | Full | Nothing |
| Payment recording (manual cash/card/other) | Full | Nothing |
| BlockChyp terminal payment processing | Full integration | Nothing |
| Invoice voiding | With confirmation | Nothing |
| Invoice stats/KPIs (total sales, outstanding, tax collected) | Dashboard cards + pie charts | Nothing |
| Receipt printing / thermal printer support | Multiple paper sizes | Nothing |
| SMS receipt sending | Via SMS API | Nothing |
| Payment status distribution charts | Pie charts | Nothing |
| Payment method distribution charts | Pie charts | Nothing |

### E. Expense Tracking
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Expense list with search and category filter | Full | Nothing |
| Expense CRUD (add, edit, delete) | Full | Nothing |
| Expense categories (14 predefined) | Full | Nothing |
| Summary cards (total amount, count, top categories) | Full | Nothing |

### F. Reports & Analytics
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Sales reports (daily revenue, by method, date range) | Charts + CSV export | Nothing |
| Ticket reports (by status, by day, by tech, summary stats) | Charts + tables | Nothing |
| Employee reports (tickets assigned/closed, commission, hours, revenue) | Full | Nothing |
| Inventory reports (low stock, value summary, top moving items) | Full | Nothing |
| Tax reports (by tax class, rate, collected amount) | Full | Nothing |
| Business insights (AI-suggested) | Dashboard tab | Nothing |

### G. Employee Management
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Employee list with details | Full | Nothing |
| Clock in / clock out | Full | Nothing |
| Time tracking (weekly/monthly hours) | Full | Nothing |
| Commission tracking (per ticket/invoice) | Full | Nothing |
| PIN management | Full | Nothing |

### H. Leads Management
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Lead list with status filters and search | Full | Nothing |
| Lead detail (customer info, service type, notes, status) | Full | Nothing |
| Lead creation (inline form) | Full | Nothing |
| Lead-to-ticket conversion | One-click convert | Nothing |
| Lead status tracking (new/contacted/scheduled/converted/lost) | Full pipeline | Nothing |

### I. Estimates
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Estimate list with status filters | Full | Nothing |
| Estimate creation (customer, line items, pricing) | Full modal | Nothing |
| Estimate detail view | Full | Nothing |
| Estimate-to-ticket conversion | Full | Nothing |
| Estimate sending (email/SMS) | Full | Nothing |
| Status tracking (draft/sent/approved/rejected/converted) | Full | Nothing |

### J. Calendar / Appointments
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Calendar view (month/week/day) | Full interactive calendar | Nothing |
| Appointment creation | Full | Nothing |
| Appointment status tracking | Full | Nothing |
| Employee assignment to appointments | Full | Nothing |

### K. Supplier Catalog
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Browse Mobilesentrix / PhoneLcdParts catalogs | Full | Nothing |
| Search catalog items | Full with device model filter | Nothing |
| Import catalog item to local inventory | One-click import with markup | Nothing |
| Sync job management | Full | Nothing |
| Device model browsing | Full | Nothing |

### L. Dashboard
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| KPI summary (sales, tax, profit, expenses, receivables) | Full with date presets | Nothing |
| Daily sales chart | Line chart | Nothing |
| Open tickets list | Sortable table | Nothing |
| Missing parts queue with supplier links | Full interactive | Nothing |
| Sales by type breakdown | Table | Nothing |

### M. Other
| Feature | Desktop Has | Android Has |
|---------|------------|-------------|
| Photo capture (QR code link for device photos) | Full upload system | Nothing |
| Print system (receipt, label, work order, letter) | Multiple formats | Nothing |

---

## 2. Mobile Priority Rating

### ESSENTIAL FOR MOBILE
These are features a technician actively needs while walking around the shop or helping a customer at the counter.

1. **Inventory quick lookup** -- Technician needs to check if a part is in stock before promising a repair time.
2. **Barcode/UPC scan to check stock** -- Scan a part bin label to see what it is and if stock is sufficient.
3. **Stock adjustment** -- When a technician pulls a part from the shelf, they should log it immediately rather than walking back to a desktop.
4. **Invoice lookup (read-only)** -- Customer calls or walks in asking about a payment; technician needs to pull it up fast.
5. **Quick expense logging** -- Bought something at the hardware store for the shop? Log it before you forget the receipt.
6. **Employee clock in/out** -- Technicians arriving/leaving should punch in from their phone rather than queueing at a shared desktop.
7. **Dashboard KPIs (read-only)** -- Shop owner checks daily revenue on their phone during the commute home.
8. **Missing parts queue (read-only)** -- See which parts need ordering without being at the desktop. Useful when at a supplier.

### NICE TO HAVE ON MOBILE
These add value but are not critical workflow blockers.

9. **Lightweight POS / quick checkout** -- Simple product sale (accessories, screen protectors) when the desktop POS station is occupied. Not the full repair check-in wizard, just "scan product, take payment."
10. **Cash register view (read-only)** -- Check daily cash balance without walking to the register.
11. **Invoice payment recording** -- Customer walks up to a technician to pay; record a cash payment on the spot.
12. **Lead creation (quick-add)** -- Customer calls while technician is on the floor; capture name, phone, issue as a lead.
13. **Purchase order status (read-only)** -- Check if a supplier order has shipped.
14. **Estimate quick-view (read-only)** -- Pull up an estimate to discuss with a customer on the shop floor.
15. **Appointment/calendar view (read-only)** -- See today's scheduled appointments.
16. **Low stock alerts / notifications** -- Push notification when stock drops below reorder level.
17. **Supplier catalog search** -- Look up a part price from a supplier while talking to a customer about repair cost.
18. **Photo capture for devices** -- Use phone camera to photograph device condition at check-in (the desktop already generates QR codes for this, but native integration would be smoother).
19. **Reports summary (read-only)** -- Quick glance at sales/ticket trends.

### DESKTOP ONLY IS FINE
These features require large screens, detailed data entry, or are rarely needed away from the desk.

20. **Full repair check-in wizard** -- Multi-step form with device selection, service pricing, parts selection, pre-conditions, customer signature. This needs a large screen.
21. **Inventory CRUD (create/edit full form)** -- Setting up new inventory items with SKU, pricing, tax class, stock levels, etc. is detailed data entry best done at a desk.
22. **Bulk inventory operations** -- CSV import, bulk price adjustments. Purely back-office.
23. **Full invoice creation** -- Invoices are auto-generated from tickets, not manually created. No need on mobile.
24. **Invoice voiding** -- Rare, consequential action. Desktop only.
25. **BlockChyp terminal payment** -- Terminal is physically at the counter, tied to desktop POS.
26. **Full report generation with charts** -- Detailed analytics with charts, CSV export. Desktop.
27. **Employee management (admin)** -- Creating employees, setting permissions, managing PINs. Admin-only, desktop.
28. **Commission management** -- Reviewing and adjusting commissions. Desktop back-office.
29. **Full lead management pipeline** -- Editing lead details, status changes, conversion. Desktop workflow.
30. **Full estimate CRUD** -- Creating detailed multi-line estimates. Desktop.
31. **Estimate sending (email/SMS)** -- Can trigger from desktop.
32. **Calendar management (create/edit appointments)** -- Best done at a workstation.
33. **Catalog sync jobs** -- Admin operation, desktop.
34. **Catalog import to inventory** -- Setting markup, mapping fields. Desktop.
35. **Receipt/label printing** -- Printers are connected to desktop stations.
36. **Settings and configuration** -- Admin-only, desktop.

---

## 3. Mobile-Friendly Designs for Essential and Nice-to-Have Features

### ESSENTIAL FEATURES

#### 3.1 Inventory Quick Lookup
**What it does:** Technician searches for a part and instantly sees stock level, location, and price.
**Mobile design:**
- Single search bar at top of screen with instant-filter
- Results show: item name, SKU, stock count (color-coded: green = good, amber = low, red = zero), shelf/bin location
- Tap a result to see detail card: cost price, retail price, last movement date, category
- Search supports SKU, name, UPC, and partial text
- Filter chips: All / Parts / Products / Services
- No edit capability -- just lookup

#### 3.2 Barcode Scan to Check Stock
**What it does:** Scan a barcode, see stock info immediately.
**Mobile design:**
- Camera-based barcode scanner (react-native-camera or expo-barcode-scanner)
- Full-screen camera view with scan target overlay
- On successful scan: slide-up card showing item name, stock count, location, price
- "Scan another" button to dismiss and scan again
- Accessible from inventory lookup screen AND as a standalone quick-action on the home screen

#### 3.3 Stock Adjustment
**What it does:** Log when parts are pulled, received, returned, or written off.
**Mobile design:**
- Accessible from inventory detail card (after lookup or scan)
- Simple bottom sheet: type dropdown (adjustment/purchase/return/defective), quantity (+/-), notes field
- Large +/- buttons for easy one-handed operation
- Submit button with immediate feedback
- Confirmation toast with undo option (5-second window)

#### 3.4 Invoice Lookup (Read-Only)
**What it does:** Find and view invoice details.
**Mobile design:**
- Search bar at top (searches by invoice ID, customer name, ticket ID)
- Status filter tabs: All / Unpaid / Partial / Paid
- Card-style list: invoice ID, customer name, total, amount due, status badge
- Tap to expand: line items, payment history, dates, linked ticket
- Quick-action: tap customer phone to call

#### 3.5 Quick Expense Logging
**What it does:** Log a business expense on the spot.
**Mobile design:**
- Big "+" button on a minimal expense list screen
- Bottom sheet form: category picker (scrollable pills), amount (large number input), date (defaults to today), description
- Camera button to photograph receipt (attach as note)
- One-tap submit
- Recent expenses list below for reference

#### 3.6 Employee Clock In/Out
**What it does:** Punch in when arriving, punch out when leaving.
**Mobile design:**
- Prominent clock in/out toggle button on home screen
- Shows current status: "Clocked in since 9:02 AM" or "Not clocked in"
- Optional PIN entry for verification
- Today's hours summary below the button
- This week's hours summary (simple list)

#### 3.7 Dashboard KPIs (Read-Only)
**What it does:** Glance at daily business performance.
**Mobile design:**
- Home screen of the app (replace or augment current SMS-only home)
- Top row: Today's sales, open tickets count, outstanding receivables
- Second row: ticket count by status (horizontal colored bar)
- Date preset pills: Today / Yesterday / This Week / This Month
- Pull-to-refresh
- Compact -- no charts, just numbers with trend arrows

#### 3.8 Missing Parts Queue (Read-Only)
**What it does:** See which parts are needed for open tickets.
**Mobile design:**
- Card list: part name, SKU, needed quantity, for which ticket (order ID), customer name
- Stock status badge (missing/ordered/received)
- Tap part to see supplier link (opens in browser for ordering)
- Filter: All / Missing / Ordered
- Useful when at a supplier's warehouse -- check what you need to buy

### NICE-TO-HAVE FEATURES

#### 3.9 Lightweight Quick Checkout
**What it does:** Sell a product (accessory) without the full POS.
**Mobile design:**
- Barcode scan to add product to simple cart
- Manual search fallback
- Cart shows items with quantities and prices
- Total with tax
- Payment method selection (Cash / Card / Other)
- Simple cash tendered / change calculation
- Generate invoice on submit
- NOT the full repair check-in wizard -- accessories only

#### 3.10 Cash Register View (Read-Only)
**What it does:** See today's cash drawer status.
**Mobile design:**
- Four number cards: Cash In, Cash Out, Cash Payments, Balance
- Scrollable transaction history below
- No cash-in/out actions on mobile (that's a desktop register operation)

#### 3.11 Invoice Payment Recording
**What it does:** Record a payment against an existing invoice.
**Mobile design:**
- From invoice detail view: "Record Payment" button
- Bottom sheet: amount (pre-filled with amount due), method dropdown, notes
- Confirmation dialog before submit
- Updates invoice status immediately

#### 3.12 Quick Lead Creation
**What it does:** Capture a potential customer's info on the fly.
**Mobile design:**
- Bottom sheet form: name, phone, issue description, service type
- Minimal fields -- full details can be added on desktop later
- Phone field auto-formats
- Submit creates lead with "new" status

#### 3.13 Purchase Order Status (Read-Only)
**What it does:** Check supplier order status.
**Mobile design:**
- Card list: PO number, supplier, status badge, item count, total, date
- Status badges: draft/pending/ordered/partial/received/cancelled
- Tap to expand and see line items

#### 3.14 Estimate Quick-View (Read-Only)
**What it does:** Pull up an estimate to discuss pricing with a customer.
**Mobile design:**
- Search by estimate ID or customer name
- Card view: estimate ID, customer, total, status
- Tap to see line items and pricing
- No edit -- just reference

#### 3.15 Today's Appointments (Read-Only)
**What it does:** See scheduled appointments for the day.
**Mobile design:**
- Vertical timeline view of today's appointments
- Each card: time, customer name, service type, assigned tech
- Status badges (scheduled/confirmed/completed/no-show)
- Tap customer phone to call

#### 3.16 Low Stock Push Notifications
**What it does:** Alert when items drop below reorder level.
**Mobile design:**
- Push notification: "[Item Name] is low -- 2 remaining (reorder at 5)"
- Tap notification goes to inventory detail
- Configurable: which items to watch, notification frequency

#### 3.17 Supplier Catalog Quick Search
**What it does:** Look up a supplier part price.
**Mobile design:**
- Search bar with source filter (Mobilesentrix / PhoneLcdParts)
- Results: part name, supplier price, availability
- Tap to open supplier URL in browser
- No import -- just price reference

#### 3.18 Device Photo Capture
**What it does:** Photograph device condition at check-in.
**Mobile design:**
- Native camera integration (far better than desktop webcam QR code workflow)
- Multi-photo capture with preview grid
- Auto-upload to ticket's device record
- Accessible from ticket detail or via QR code scan
- This would actually be BETTER than the desktop flow

#### 3.19 Reports Summary (Read-Only)
**What it does:** Quick numbers overview.
**Mobile design:**
- Compact version of reports: just key metrics, no charts
- Sales: total revenue, invoice count for selected period
- Tickets: open/closed counts, avg turnaround
- Top-level numbers only -- drill down on desktop

---

## 4. Quick-Access Features for Technicians

A repair technician carrying their phone around the shop needs a **quick-action home screen** with:

1. **Scan Barcode** -- One tap to camera, instant stock check
2. **Search Inventory** -- Type to find a part, see stock/location
3. **Clock In/Out** -- One tap (with PIN)
4. **Today's Open Tickets** -- What am I working on? (read-only list)
5. **Missing Parts** -- What do I need to order/find?
6. **Log Expense** -- Quick capture before forgetting
7. **Daily Summary** -- Revenue, ticket count at a glance

These should be available as large tile buttons on the home screen, not buried in menus.

---

## 5. Read-Only vs Full CRUD on Mobile

### Read-Only is Sufficient
These features need viewing but not editing on mobile:

| Feature | Reason |
|---------|--------|
| Invoice list + detail | Just need to answer customer questions. Payments recorded rarely. |
| Dashboard KPIs | Monitoring, not managing |
| Reports summaries | Quick check, not analysis |
| Purchase order status | Tracking, not creating |
| Estimate detail | Reference for customer conversations |
| Calendar/appointments | Seeing the schedule, not managing it |
| Cash register summary | Monitoring balance |
| Missing parts queue | Checking what's needed |
| Supplier catalog search | Price reference only |

### Needs Write/Action Capability
These require the ability to create or modify data on mobile:

| Feature | Why Write is Needed |
|---------|-------------------|
| Stock adjustment | Technician pulls part from shelf, needs to log it NOW |
| Employee clock in/out | Cannot be read-only by definition |
| Quick expense entry | Capture at time of purchase |
| Quick lead creation | Capture walk-in/call-in customer info immediately |
| Invoice payment recording | Customer pays technician directly |
| Device photo capture | Camera is the input device |
| Quick product checkout | Need to complete a sale |

### Full CRUD Stays Desktop
These are complex enough to remain desktop-only:

| Feature | Why Desktop Only |
|---------|-----------------|
| Inventory create/edit | Too many fields for phone |
| Full POS repair check-in | Multi-step wizard with device details, parts, pricing |
| Invoice creation (auto from tickets) | Not user-initiated |
| Estimate creation/editing | Line-item detail work |
| Lead full management | Pipeline management |
| Employee admin | Permission management |
| Report generation | Analysis with charts |
| Catalog import | Markup configuration |
| Purchase order creation | Multi-item forms |
| Bulk inventory operations | CSV work |

---

## 6. Implementation Priority Recommendation

### Phase 1: Read-Only Foundation (Highest Value, Lowest Risk)
1. Dashboard KPIs (home screen)
2. Inventory search/lookup with barcode scan
3. Invoice list/detail (read-only)
4. Today's open tickets (already partially exists via RepairDesk)

### Phase 2: Essential Write Actions
5. Employee clock in/out
6. Stock adjustment
7. Quick expense logging
8. Missing parts queue view

### Phase 3: Nice-to-Have
9. Quick product checkout (simple POS)
10. Invoice payment recording
11. Quick lead creation
12. Device photo capture (native camera)
13. Low stock push notifications

### Phase 4: Extended Read-Only Views
14. Purchase order status
15. Estimate quick-view
16. Calendar view
17. Supplier catalog search
18. Cash register view
19. Reports summary
