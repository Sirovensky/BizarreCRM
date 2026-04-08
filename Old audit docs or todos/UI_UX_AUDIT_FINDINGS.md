# UI/UX Audit Findings — April 2026

Full audit performed by walking through every screen and running end-to-end scenarios.
Organized by severity and screen area.

---

## BUGS (Broken functionality found during testing)

### BUG-A1: POS Checkout quick-fill amount buttons unreliable
**Screen:** POS → Checkout Modal
**Severity:** Major
**What happens:** The quick-fill buttons ($89.99, $90.00, $100.00) below the "Amount Given" input didn't respond during testing — clicking them didn't fill the amount field. The code looks correct (`onClick={() => setCashGiven(amt.toFixed(2))}`), but the click may be swallowed or the state update may not propagate to the input. This needs manual re-testing and debugging. If the buttons work inconsistently, it may be a focus/blur issue with the autoFocus input field.
**Expected:** Clicking $89.99 should fill the amount field with 89.99 and show the "Change" calculation.
**Fix:** Test the quick-fill buttons manually in Chrome DevTools. Possible fix: ensure the input isn't swallowing clicks due to autoFocus, or add a ref-based value setter instead of state-only.

### BUG-A2: POS customer creation fails silently on duplicate phone
**Screen:** POS → Customer Step → New Customer form
**Severity:** Critical
**What happens:** When creating a customer with a phone number that already exists in the system, the POST /customers API returns 409 Conflict. But the UI shows NO error message — the form just stays there, the button does nothing. The user has no idea why the customer isn't being created.
**Expected:** Show a clear error message like "A customer with this phone number already exists. Did you mean [Customer Name]?" with a button to select the existing customer instead. This is especially important because the customer search is right above the form — the user should be nudged to use it.
**Fix:** In the POS customer creation handler, catch 409 responses and display a toast or inline error. Ideally, show the existing customer's name and a "Use this customer" button.

### BUG-A3: POS success screen Print buttons use window.open (popup-blocked)
**Screen:** POS → Ticket Created success screen
**Severity:** Major
**What happens:** "Print Label" and "Print Receipt" buttons use `window.open('/print/ticket/:id?size=...', '_blank')` which gets blocked by Chrome's popup blocker. The buttons silently fail — no error, no print, no feedback. "View Ticket" uses `resetAll()` followed by `setTimeout(() => navigate(), 0)` which may have a race condition — `resetAll()` clears `ticketId` from state, then `navigate` runs, but `ticketId` was captured in closure so it usually works, but the double-click needed during testing suggests timing sensitivity.
**Expected:** Print buttons should either: (a) navigate in the same tab (like /print/ticket/:id) since the success screen is done, or (b) detect popup blocking and show a fallback link. View Ticket should not need a setTimeout workaround.
**Fix:**
1. Change Print Receipt/Label to navigate in same tab: `navigate('/print/ticket/${ticketId}?size=receipt80')` — since the user is done with the success screen anyway.
2. Or detect popup block: `const w = window.open(...); if (!w) toast.error('Popup blocked. Click here to print.', { onClick: () => navigate(...) })`.
3. For View Ticket: capture ticketId before resetAll, or navigate first then reset.

### BUG-A4: Invoice summary KPI cards show "..." indefinitely
**Screen:** Invoices List Page
**Severity:** Minor
**What happens:** The four KPI cards at the top of the Invoices page (Total Sales, Invoices, Tax Collected, Outstanding) show "..." loading indicators. They may be loading slowly or the endpoint may have an issue.
**Expected:** Cards should load within 1 second and show actual numbers. If the endpoint is slow, show skeleton loaders, not "...".
**Fix:** Check the invoice summary API endpoint performance. Add a loading skeleton or ensure the "..." resolves to actual data.

---

## POS / CHECK-IN FLOW

### POS-1: No preset prices for device + service combinations
**Screen:** POS → Service Step
**Severity:** Critical (audit doc: "total cost should auto-populate for a device and a part")
**What happens:** Every service shows "Custom" pricing. When selecting "Screen Replacement" for an Apple iPhone 15, the system says "No preset price for this device + service. Enter price manually:" with a $0.00 field. This means every single repair requires the tech to look up the price from memory or another source.
**Expected:** The system should have configurable preset prices per device+service combination. For example, "iPhone 15 Screen Replacement" → $89.99 (Aftermarket) / $129.99 (OEM) / $179.99 (Premium). The service pills should show the price: "Screen Replacement — $89.99". When clicked, the price auto-populates, and the user is asked to select quality grade (aftermarket/OEM/premium) before the price is set.
**Fix:**
1. Create a `repair_pricing` table: (device_model_id, service_type, grade, price)
2. Settings → Repair Pricing already exists as a tab — wire it to this table
3. On the Service step, look up prices from this table based on selected device
4. Show quality grade pills (Aftermarket/OEM/Premium) with prices when preset exists
5. Fall back to manual entry only when no preset price is configured

### POS-2: No parts auto-added based on service type
**Screen:** POS → Details Step
**Severity:** Major (audit doc: "a part (screen or battery) auto adds to all phone repairs")
**What happens:** When "Screen Replacement" is selected as the service, no parts are automatically added to the ticket. The tech must manually add the screen part separately.
**Expected:** Selecting "Screen Replacement" for iPhone 15 should auto-search inventory for matching screen parts (based on device compatibility) and either auto-add the part or show a prompt: "Add screen part? [OLED Assembly for iPhone 15 — $45.00 in stock] [Skip]".
**Fix:** After service selection, query `inventory_device_compatibility` + `inventory_items` for the selected device_model + service_type. If matches found, auto-suggest in the Details step.

### POS-3: No due date / estimated completion shown during check-in
**Screen:** POS → Details Step
**Severity:** Major
**What happens:** There is no estimated completion date or due date field in the check-in flow. The ticket is created with no due_on date. The customer doesn't know when to come back.
**Expected:** Show an auto-calculated due date (e.g., "Estimated ready: Tomorrow 3:30 PM" based on the `repair_default_due_value` setting). Allow the tech to adjust it. This date should be printed on the intake receipt.
**Fix:** Add a "Due Date" field to the POS Details step, pre-filled from settings. Pass it through to ticket creation.

### POS-4: Cart panel takes up left 30-40% even when empty
**Screen:** POS → All steps
**Severity:** Minor
**What happens:** The left cart panel shows "Cart is empty — Scan a barcode, search a product, or add a repair" but still takes up ~35% of the screen width. On the device/category selection steps, this wastes significant screen real estate.
**Expected:** The cart should be dynamic, related to the full screen size.
**Fix:** Add a collapsed state for the cart for smaller screens. Think of a mobile device.
### POS-5: No barcode scan indicator or prompt
**Screen:** POS → All steps
**Severity:** Minor
**What happens:** The cart says "Scan a barcode" but there's no visual barcode icon, scanning indicator, or keyboard focus to indicate the scanner is active/ready.
**Expected:** Show a barcode icon in the search area with a subtle pulsing animation or "Ready to scan" indicator. When a barcode scan is detected, show a brief flash/highlight to confirm.
**Fix:** Add barcode scan listener and visual indicator to the POS page.

---

## TICKET LIST



### TKT-2: Status text truncated — "Waiting for inspect..." is unreadable
**Screen:** Tickets List
**Severity:** Major
**What happens:** Long status names like "Waiting for Inspection", "Payment Received" are truncated with "..." in the status badge column. Users can't distinguish between "Waiting for Parts" and "Waiting for Inspection" and "Waiting on Customer" at a glance.
**Expected:** Status badges should either: (a) wrap to 2 lines, (b) use abbreviated labels (e.g., "W. Parts", "W. Inspection"), or (c) the column should be wider. On hover, show the full status name.
**Fix:** Increase the status column min-width, or use shorter display labels for long statuses (configurable in Settings → Ticket Statuses with a `short_label` field).

### TKT-3: No "Due Date" or "Overdue" indicator visible in ticket list
**Screen:** Tickets List
**Severity:** Major
**What happens:** There is no due date column or overdue indicator in the default ticket list view. The stale ticket highlighting (amber >3d, red >7d) partially addresses this, but it's based on last update, not the promised due date.
**Expected:** Show a "Due" column with relative time ("Due tomorrow", "Overdue 2d"). Color-code: green (on track), amber (due today), red (overdue). This is critical for the front desk to know which repairs to prioritize.
**Fix:** Add a due_on display column. Show it as a relative time with color coding.

### TKT-4: No customer phone number visible in ticket list
**Screen:** Tickets List
**Severity:** Minor
**What happens:** The ticket list shows customer name but not phone number. When a customer calls asking about their repair, the front desk person needs to search by name, which can be ambiguous.
**Expected:** Show phone number either inline with customer name ("John Doe — 303-555-1234") or in the expanded row preview. The phone number should be a clickable tel: link.
**Fix:** Add phone number to the ticket list customer column or to the expandable row preview.

---

## TICKET DETAIL

### TKD-1: No call button — only SMS visible in customer sidebar
**Screen:** Ticket Detail → Customer Information sidebar
**Severity:** Major (audit doc: "customer contact actions are one-click: call, SMS, email")
**What happens:** The customer sidebar shows an "SMS" button but no "Call" button. To call the customer, you need to click "More" and find the phone number, or click the phone number text (which may open a tel: link on some devices but isn't obvious).
**Expected:** Show three contact buttons side-by-side: Phone (tel: link), SMS (opens SMS compose), Email (opens email compose). Each should be a clearly labeled icon button.
**Fix:** Add a Call button (phone icon) next to the SMS button in the Customer Information sidebar. Wire it to `tel:` link. Add Email button if email is on file.

### TKD-2: "Unassigned" technician should prompt assignment
**Screen:** Ticket Detail → Ticket Summary sidebar
**Severity:** Minor
**What happens:** The Ticket Summary shows "Assignee: Unassigned" as plain text. The user must click the edit button to assign someone.
**Expected:** "Unassigned" should be a clickable link/dropdown that opens the tech assignment picker directly. Alternatively, show a subtle "Assign" button next to it.
**Fix:** Make "Unassigned" a clickable element that opens the assignment dropdown inline.

### TKD-4: No "Print Receipt" from ticket detail without going through checkout
**Screen:** Ticket Detail
**Severity:** Major (audit doc: "any ticket can be printed without closing the ticket")
**What happens:** The ticket detail has a "Print" button in the header, which opens print format options. But the print layout is a work order / intake receipt — not a customer-facing receipt with payment details. To print a receipt with payment, you have to go to the invoice detail.
**Expected:** The Print dropdown should offer both "Print Work Order" and "Print Receipt" (with payment info). The receipt should be printable directly from the ticket without navigating to the invoice.
**Fix:** Add "Print Receipt" option to the ticket detail Print dropdown that generates a receipt layout including payment info from the linked invoice.

---

## CUSTOMER LIST

### CUS-1: Missing "Last Visit" column
**Screen:** Customer List
**Severity:** Major (audit doc specifically requires this)
**What happens:** The customer list shows: Name, Organization, Phone, Email, Tickets, Total Spent, Outstanding. There is no "Last Visit" or "Last Activity" date column.
**Expected:** Add a "Last Visit" column showing the date of their most recent ticket. Format as relative time ("2 days ago", "3 months ago"). This helps identify active vs. inactive customers at a glance.
**Fix:** The backend already has this data (customer analytics endpoint returns last_visit). Add it as a column to the customer list query and display it in the table.

### CUS-2: Too many action icons per row (6 icons)
**Screen:** Customer List
**Severity:** Minor
**What happens:** Each customer row has 6 small icon buttons: Call, SMS, Ticket, Link?, Edit, Delete. On smaller screens these are tiny and hard to click. The icon-only buttons are also not accessible.
**Expected:** Reduce to 3 visible actions max: View (primary), Edit, and a "..." overflow menu for less-common actions (Call, SMS, Create Ticket, Delete). Or, make the entire row clickable to open the customer detail (already works for name click).
**Fix:** Consolidate action icons into a primary "View" button + "..." overflow menu with the rest.

### CUS-3: Some customers show as phone numbers only (no name)
**Screen:** Customer List
**Severity:** Minor (data quality)
**What happens:** Some entries in the customer list show a phone number as the name (e.g., "1 (720) 630-0106") instead of a real name. These are likely imported from RepairDesk where the customer name wasn't recorded.
**Expected:** For nameless customers, show the phone number but add a visual indicator (e.g., italicized, with a "no name" badge) and a one-click "Add Name" action so staff can fill it in when the customer calls back.
**Fix:** Add an inline "Add Name" action for customers where first_name is empty or looks like a phone number.

### CUS-4: No duplicate detection on customer creation
**Screen:** POS → New Customer form, Customer → New Customer page
**Severity:** Major (audit doc: "duplicate detection — warn or merge")
**What happens:** You can create multiple customers with similar names or the same email without any warning. The only protection is the 409 on duplicate phone (which itself doesn't show a user-facing error — see BUG-A2).
**Expected:** When typing a name or phone in the new customer form, show "Possible matches" below the field if similar customers exist. Let the user choose to use the existing customer or proceed with creating a new one.
**Fix:** Add a fuzzy match search that fires on blur of the name/phone/email fields. Show matching customers in a dropdown.

---

## INVOICE

### INV-1: No "Record Payment" button on unpaid invoice detail
**Screen:** Invoice Detail (for unpaid invoices)
**Severity:** Major
**What happens:** Looking at the invoice detail page for an unpaid invoice, only "Print" and "Void" buttons are visible. There's no obvious "Record Payment" or "Pay Now" button. The user has to go through the ticket's Checkout flow or use a different path.
**Expected:** Unpaid and partial invoices should show a prominent "Record Payment" button on the invoice detail page itself. This is a common workflow — customer comes back and pays for a previously created invoice.
**Fix:** Add a "Record Payment" button to the invoice detail page header when status is unpaid or partial. Wire it to the existing payment recording modal.

### INV-2: No "Overdue" invoice status or visual flag
**Screen:** Invoices List
**Severity:** Minor
**What happens:** Invoices have status tabs: All, Unpaid, Partial, Paid, Void. There's no "Overdue" concept — you can't easily see which unpaid invoices are past their due date.
**Expected:** Add an "Overdue" tab or badge on the "Unpaid" tab showing how many are past due_on date. Overdue invoices should have a red icon or border.
**Fix:** Filter unpaid invoices where due_on < today, show count badge on "Unpaid" tab or add separate "Overdue" tab.

---

## COMMUNICATIONS / MESSAGES

### COM-1: "Unknown Caller" entries have no way to link to a customer
**Screen:** Communications → Message List
**Severity:** Major
**What happens:** Some SMS conversations show "Unknown Caller (425) 386-7748" — these are messages from numbers not in the customer database. There's no way to associate this number with an existing customer or create a new customer from this view.
**Expected:** Show a "Link to Customer" or "Create Customer" when such  conversation is open
**Fix:** Add a "Link Customer" action on Unknown Caller conversations that opens a search-or-create flow with the phone pre-filled.

### COM-2: No search within a conversation thread
**Screen:** Communications → Active Conversation
**Severity:** MAJOR!
**What happens:** You can search conversations (thread list) by customer name, but once inside a conversation, there's no way to search for a specific message within the thread.
**Expected:** Add a search bar within the active conversation view to find specific messages.
**Fix:** Add an in-thread search with highlight/scroll-to matching messages.

---

## DASHBOARD

### DASH-2: No appointments/schedule section
**Screen:** Dashboard
**Severity:** Minor
**What happens:** Dashboard has no "Today's Schedule" or upcoming appointments section. The Calendar exists as a separate page, but the dashboard doesn't surface today's appointments.
**Expected:** Show "Today's Appointments" section on dashboard with time + customer + service. This is important for shops that take appointments.
**Fix:** Add a "Today's Schedule" card that queries leads/appointments for today and displays them.

### DASH-3: Net Profit equals Total Sales — COGS not tracked
**Screen:** Dashboard → KPI Cards
**Severity:** Minor (data quality, not UI)
**What happens:** Dashboard shows Total Sales = $68,010.80 and Net Profit = $68,010.80 (identical). COGS shows $0.00. This means cost_price is not being tracked on inventory items or parts.
**Expected:** This is a data entry issue, not a UI bug. But the UI should show a warning when COGS is $0 for a shop that clearly uses parts: "Cost data missing — update inventory cost prices for accurate profit tracking".
**Fix:** Add a subtle info banner on dashboard when COGS is $0 but the shop has inventory items: "Set cost prices on your parts for accurate profit reporting."

---

## SETTINGS

### SET-1: No business hours configuration
**Screen:** Settings → Store Info
**Severity:** Minor
**What happens:** Store Info shows name, address, phone, email, timezone, currency, receipt header/footer, and referral sources. But there's no business hours configuration (e.g., Mon-Fri 9AM-6PM, Sat 10AM-4PM).
**Expected:** Business hours should be configurable and appear on printed receipts and the customer tracking page. The hours mentioned in SMS ("9-3:30, 5-8 Monday-Friday, Weekends by appointment") should come from settings.
**Fix:** Add a business hours section to Store Info with day-of-week toggles and time pickers.

### SET-2: No logo upload on Store Info page
**Screen:** Settings → Store Info
**Severity:** Minor
**What happens:** Store Info has no logo upload field. The logo settings are split into separate Invoice and Receipt settings tabs.
**Expected:** The Store Info tab should have a primary logo upload that's used as the default for invoices, receipts, and the login screen. Invoice/Receipt tabs can override if needed.
**Fix:** Add a logo upload field to the Store Info tab.

---

## MICRO-INTERACTIONS & POLISH

### POL-1: Phone numbers don't auto-format as user types
**Screen:** POS → New Customer, Customer Create page
**Severity:** Minor (audit doc: "phone number fields auto-format as the user types")
**What happens:** When typing a phone number (e.g., "3035551999"), it stays as raw digits. It doesn't format to "(303) 555-1999" as you type.
**Expected:** Auto-format phone numbers into a readable format as the user types. This prevents formatting inconsistencies and makes it easier to verify the number is correct.
**Fix:** Add an input mask or formatting function that converts digits to (XXX) XXX-XXXX as they're entered.

### POL-2: No copy-to-clipboard on ticket IDs and phone numbers
**Screen:** Ticket List, Ticket Detail, Customer Detail
**Severity:** Minor (audit doc: "copy-to-clipboard on ticket numbers, phone numbers")
**What happens:** Ticket IDs (T-2908) and phone numbers are not easily copyable — you have to manually select and copy the text.
**Expected:** Add a small copy icon next to ticket IDs and phone numbers. Clicking it copies the value and shows a brief "Copied!" toast.
**Fix:** Add a CopyButton component (clipboard icon → checkmark on copy) next to ticket IDs and phone numbers.

### POL-3: No undo for accidental status changes
**Screen:** Ticket List (inline status dropdown), Ticket Detail
**Severity:** Minor (audit doc: "undo available for recent status changes")
**What happens:** Changing a ticket status is immediate and irreversible (except by manually changing it back). Accidental status changes — especially on the ticket list inline dropdown — can trigger customer notifications.
**Expected:** After a status change, show a toast: "Status changed to 'In Progress' — Undo (5s)" with a countdown. If not undone, the change persists. This is especially important because status changes can trigger auto-SMS notifications.
**Fix:** Add an undo toast mechanism: delay the actual API call by 5 seconds, show an undo toast, cancel if clicked. This should be server side so if the client uses connection, it would still go through. Click = it will happen.

### POL-4: Enter key doesn't submit forms consistently
**Screen:** Various forms (customer create, notes, search)
**Severity:** Minor (audit doc: "hitting Enter submits or advances to next field")
**What happens:** In some forms, pressing Enter does nothing. In others, it works. Inconsistent behavior.
**Expected:** Enter should submit single-field forms (search, quick note). In multi-field forms, Enter should advance to the next field, and the last field's Enter should submit.
**Fix:** Audit all forms for onSubmit/onKeyDown handlers. Ensure Enter behavior is consistent.

### POL-5: No "Remember Me" / persistent login on shop computers
**Screen:** Login Page
**Severity:** Minor (audit doc: "remember me or auto-login option important for shop computers that stay logged in")
**What happens:** The login page requires username + password + 2FA code every time. For a shop computer that stays on all day, this is annoying friction at the start of every shift.
**Expected:** Add a "Remember this device" checkbox on 2FA step that extends the refresh token to 90 days on that browser. PIN-based switch-user is already built for multi-user scenarios.
**Fix:** Add a "Trust this device" option on 2FA verification that sets a longer-lived refresh token.

---

## WORKFLOW SCENARIO FINDINGS

### Scenario 1 Timing: New Walk-In Customer
**Flow:** POS → New Customer (4 fields) → Category → Device → Service → Price → Details → Add to Cart → Create Ticket
**Click count:** ~10 clicks + typing
**Time:** ~90 seconds (with manual price entry)
**Could be:** ~45 seconds with preset pricing and auto-parts
**Friction points:** Manual price entry (POS-1), no parts auto-add (POS-2), no due date (POS-3)

### Scenario 5 Timing: Repair Complete → Pickup → Payment
**Flow:** Open ticket → Click Checkout → POS loads with cart → Click Checkout → Enter amount → Complete Checkout
**Click count:** ~5 clicks + typing (typing shouldn't be needed if quick-fill worked)
**Time:** ~30 seconds (with working quick-fill) or ~45 seconds (manual typing)
**Friction points:** Quick-fill buttons broken (BUG-A1), ticket status doesn't auto-change to "Closed" after payment

---

## PRIORITY MATRIX

### High Impact, Low Effort (Do First)
- BUG-A1: Fix checkout quick-fill buttons
- BUG-A2: Show error on duplicate customer phone
- TKT-2: Fix status text truncation
- CUS-1: Add "Last Visit" column
- DASH-1: Add ticket status breakdown counts
- TKD-1: Add Call button in ticket sidebar

### High Impact, Medium Effort
- POS-1: Preset pricing per device+service
- POS-2: Auto-suggest parts based on service
- POS-3: Due date in check-in flow
- TKT-1: Priority-based default sort
- INV-1: Record Payment button on invoice detail
- CUS-4: Duplicate detection on customer creation
- COM-1: Link Unknown Caller to customer

### High Impact, High Effort
- POL-3: Undo mechanism for status changes

### Previously Marked Done But Issues Found
- BUG-A3: Print Receipt uses window.open (gets popup-blocked) — UX6.3 "Send receipt after payment" is marked done but print from success screen silently fails
- V8 "Form validation" — marked done, but POS customer creation shows NO error on 409 duplicate phone (BUG-A2)
- POS-1: Repair Pricing tab exists in Settings but NO preset prices are populated — the feature exists structurally but yields "Custom" for every service, meaning it provides no value until prices are entered. Should be flagged as "needs setup" not "done"

### Low Impact, Low Effort (Polish When Time Allows)
- TKD-2: Make "Unassigned" clickable
- TKD-3: iFixit link tooltip
- POL-1: Phone auto-format
- POL-2: Copy-to-clipboard
- POL-4: Enter key consistency
- SET-1: Business hours config
- SET-2: Logo on Store Info page
- BUG-A4: Invoice KPI loading state
