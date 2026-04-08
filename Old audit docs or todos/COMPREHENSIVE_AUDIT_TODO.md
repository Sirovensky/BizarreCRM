# Comprehensive CRM Audit — Full TODO List

**Date:** April 4, 2026
**Scope:** Every screen, button, menu, sub-menu, toggle, and interaction audited in Chrome.
**Method:** Navigated to every page, clicked every interactive element, recorded every finding.

---

## DASHBOARD (/)

### 1. Dashboard KPI cards are not clickable
The Total Sales, Net Profit, and Receivables KPI cards display values correctly but clicking them does nothing. They should navigate to Reports (sales), Reports (profit), or Invoices (filtered to unpaid) respectively, so users can drill down from the summary into the detail.

### 2. Dashboard "Needs Attention" stale ticket items should be clickable
When clicking on a stale ticket row like "T-1104 — Omar Rios", nothing happens. The entire row should be a link to `/tickets/1104` so the user can immediately take action on the stale ticket without having to manually navigate to the ticket list and search for it.

### 3. Dashboard "Today" stats line lacks ticket status breakdown
Shows "1 created, 0 closed, 40 open" but "40 open" is a single number. Should break this down into individual status counts like "In Progress: 4, Waiting for Parts: 7, Waiting for Inspection: 11" so the shop owner can see at a glance what work is pending and what's blocked.

### 4. Dashboard "Daily Sales (Last 7 Days)" shows "No sales data" even when tickets exist
The table on the right side of the dashboard bottom section shows "No sales data" despite the Sales By Item Type table above it showing $1,343.71 in Repair Ticket sales. The daily breakdown table may be using a different data source or date filter that doesn't match the main KPI cards.

### 5. Dashboard date filter should show a "Custom Range" option
The date tabs (Today, Yesterday, Last 7 Days, This Month, Last Month, This Year, All) are good but there's no way to pick a custom date range (e.g., "March 15 to April 1"). Add a custom date picker option for ad-hoc reporting directly from the dashboard.

### 6. Dashboard "Products" row shows $0.00 sales with Qty 2
In the "Sales By Item Type" table, the "Products" row shows Qty: 2 but Sales: $0.00. This means 2 products were sold at $0 — either a data issue or these were $0 misc items. Should investigate whether $0 product sales should be filtered out or flagged.

### 7. Dashboard cost price warning banner should be dismissable
The yellow "Cost prices missing on some inventory items" banner is helpful but there's no way to dismiss it once acknowledged. Add an X button to hide it for the session, or a "Don't show again" option.

### 8. Dashboard "Parts to Order" quick action button — verify it navigates correctly
Clicking "Parts to Order" should navigate to the parts order queue page. Need to verify this button goes to the right destination and the order queue page actually exists and shows pending parts.

---

## POS / CHECK-IN (/pos)

### 9. POS service pills all show "Custom" — no preset pricing
When selecting a device + service combination (e.g., Apple iPhone 15 + Screen Replacement), all service pills display "— Custom" instead of a preset price. Every check-in requires manual price entry, which is the biggest workflow friction in the entire app. Need to populate the repair_pricing table with real prices for common device/service combos.

### 10. POS quality grade selector missing
When a service is selected, there should be an Aftermarket / OEM / Premium grade selector that shows different price tiers (e.g., Aftermarket Screen $69, OEM Screen $129, Premium Screen $159). Currently no grade selection exists — just a blank price field.

### 11. POS due date not auto-calculated
When a ticket is created through POS, no due date is set. The `repair_default_due_value` and `repair_default_due_unit` settings exist in the database but are never read during ticket creation. Customers don't know when to come back for pickup.

### 12. POS cart panel should auto-collapse when empty on smaller screens
The left cart panel takes ~30% of the screen even when empty. On laptops under 1440px, this wastes significant space during the category/device selection steps. Should auto-collapse when empty and expand when items are added.

### 13. POS "Checkout" button behavior for credit/debit — currently simulates processing
When "Credit" or "Debit" payment method is selected, the checkout button triggers a fake 2-second "processing" animation then completes the transaction. This should be replaced with actual BlockChyp terminal processing now that the integration is built. The simulated processing modal should only appear as a fallback when BlockChyp is not enabled.

### 14. POS barcode scanner input — verify it actually scans and adds items
The POS has a barcode input field at the top but it's unclear if scanning a UPC/SKU actually looks up the inventory item and adds it to the cart. Need to verify with a physical barcode scanner.

### 15. POS "Create Ticket" button should show loading state during submission
When clicking "Create Ticket" after adding repair items, there's no visual loading indicator while the ticket is being created. If the API is slow, the user might click multiple times creating duplicate tickets. Add a spinner and disable the button during submission.

### 16. POS success screen Print buttons may use window.open (popup-blocked)
The "Print Receipt" and "Print Label" buttons on the success screen after ticket creation use `window.open()` which Chrome silently blocks as a popup. Change to same-tab navigation or add popup-block detection with a fallback link.

### 17. POS customer search should show recent customers
When opening POS, the customer search should show recently checked-in customers (last 5-10) for quick selection, since many customers are repeat visitors. Currently only shows open tickets below the search.

---

## TICKETS (/tickets)

### 18. Ticket list "View" links have small click targets
The "View" text link next to each ticket row is small and easy to miss. The entire row should be clickable to navigate to the ticket detail (currently only the ticket ID link and "View" text work, but not the row itself).

### 19. Ticket list SMS icon button per row — verify it opens SMS compose
Each ticket row has a small message icon button. Need to verify it actually opens an SMS compose dialog pre-filled with the customer's phone number, rather than navigating away to the communications page.

### 20. Ticket list "..." overflow menu only shows Print and Delete
The three-dot overflow menu per ticket row only offers "Print" and "Delete". Should also include: "Change Status", "Assign Technician", "Send SMS", "Copy Ticket ID", "Convert to Invoice", and "Duplicate Ticket" for faster workflow without opening the detail page.

### 21. Ticket list bulk actions — verify select-all and bulk status change work
Check the "select all" checkbox in the header. Does it select all 25 visible items or all 1085? After selecting multiple tickets, verify a bulk action bar appears with options like "Change Status", "Assign To", "Delete", "Export".

### 22. Ticket list column sorting — verify all columns sort correctly
Click each column header (ID, Device, Customer, Issue, Created, Status, Due, Total) and verify ascending/descending sort works for each. Especially verify that sorting by "Total" sorts numerically (not alphabetically — $89.99 before $149.99, not $149.99 before $89.99).

### 23. Ticket list "Columns" button — verify column visibility toggle works
Click the "Columns" button in the toolbar to verify it opens a column picker that lets you show/hide columns. Verify changes persist after page navigation.

### 24. Ticket list Kanban view — verify drag-and-drop status change
In the Kanban board view, try dragging a ticket card from "Waiting for inspection" column to "In Progress" column. Verify the status actually changes (not just visually moves) by checking the ticket detail afterward.

### 25. Ticket list Kanban view — "Show empty columns" and "Show Closed/Cancelled" toggles
Verify these two toggle buttons actually show/hide the columns. Currently "Show empty columns (9)" would add 9 more columns, and "Show Closed/Cancelled (8)" would show completed tickets.

### 26. Ticket detail — "Checkout" button behavior on already-paid tickets
On a ticket that already has a paid invoice, the "Checkout" button in the header should either be hidden or show "Already Paid" instead of taking the user through the checkout flow again.

### 27. Ticket detail — "More" dropdown menu options
Click the "... More" button in the ticket detail header to see what options are available. Should include: Delete, Duplicate, Convert to Invoice, Print, Send SMS, Email Customer, View Invoice.

### 28. Ticket detail — Notes section: verify Internal vs Diagnostic vs Email tabs filter correctly
On the ticket detail's notes section, verify that clicking "Internal" only shows internal notes, "Diagnostic" only shows diagnostic notes, and "Email" only shows email notes. Verify the "All" tab shows everything.

### 29. Ticket detail — "Add Part" button on Parts & Billing tab
Click "+ Add Part" to verify the part search modal opens, searches inventory, and allows adding parts to the ticket. Verify the parts added actually deduct from inventory stock.

### 30. Ticket detail — Quick note input at bottom of page
Verify the sticky "Quick note... (Enter to save)" input bar at the bottom of the page works. Type a note, press Enter, verify it appears in the notes timeline immediately without page reload.

### 31. Ticket detail — Customer name link navigates to customer profile
Click the customer name in the sidebar (e.g., "Andrew Me") and verify it navigates to `/customers/{id}` showing the customer's full profile.

### 32. Ticket detail — SMS button sends a real message
Click the "SMS" button in the Customer Information sidebar. Verify it opens a compose dialog, lets you type a message, and sends it (or shows it in the SMS console log if provider is set to "console").

### 33. Ticket detail — Copy ticket ID button works
Click the clipboard icon next to the ticket ID (e.g., "T-2908") and verify it copies the ticket ID to the clipboard. Show a toast notification confirming the copy.

### 34. Ticket detail — iFixit link works
Verify the "iFixit" link next to the device name opens the correct iFixit repair guide in a new tab.

### 35. Ticket detail — "Additional Details" section expand/collapse
Click the "Additional Details" collapsible section to verify it expands to show IMEI, serial number, passcode, color, device location, and other device-specific fields.

### 36. Ticket detail — Pre/Post Repair Images section
Verify the "Pre/Post Repair Images" section allows uploading photos, switching between pre-repair and post-repair views, and deleting uploaded photos.

### 37. Ticket detail — Activity Timeline shows all history
Scroll to the Activity Timeline section and verify it shows: ticket creation, status changes (with old and new status), notes added, parts added/removed, and payment events. Each entry should have a timestamp and the user who performed the action.

### 38. Ticket detail — Billing sidebar accuracy
Verify the Billing sidebar shows correct Subtotal, Tax, Total, Paid, and Due amounts. Verify the "Due" amount in red matches Total minus Paid.

---

## CUSTOMERS (/customers)

### 39. Customer list has massive duplicate entries
The customer list shows 4794 total records with many obvious duplicates — "1 (720) 630-0106" appears 5 times, "Laptop p17 gen 1" appears 5 times, "Aaron" appears 3 times. Need to implement a customer merge/dedup tool or clean up the import data.

### 40. Customer list "Add Name" badge — verify clicking it works
Customers with phone numbers as names (e.g., "1 (720) 630-0106") show a green "Add Name" badge. Verify clicking this badge opens an inline editor or navigates to the customer edit form to add a proper name.

### 41. Customer list "..." overflow menu — verify all options work
Click the three-dot menu on a customer row and verify all options (View, Edit, SMS, New Ticket, Delete) are functional.

### 42. Customer list Filters button — verify filter options
Click the "Filters" button and verify it offers useful filter options: by tag, by customer group, by date range (created/last visit), by outstanding balance, by ticket count.

### 43. Customer list Export button — verify CSV download
Click "Export" and verify a CSV file downloads with all customer data. Verify the CSV contains all columns visible in the list (name, org, phone, email, tickets, total spent, outstanding, last visit).

### 44. Customer list Import button — verify import flow
Click "Import" and verify it opens an import dialog for CSV upload. Should support RepairDesk format and generic CSV with column mapping.

### 45. Customer detail — Tickets tab shows customer's tickets
On a customer profile, click the "Tickets" tab and verify it shows all tickets belonging to that customer with correct data.

### 46. Customer detail — Invoices tab shows customer's invoices
Click the "Invoices" tab and verify it shows all invoices for this customer, with totals, status, and links to invoice detail.

### 47. Customer detail — Communications tab shows SMS/email history
Click the "Communications" tab and verify it shows the full message thread with this customer.

### 48. Customer detail — Assets tab
Click the "Assets" tab and verify it shows devices previously repaired for this customer, building a repair history.

### 49. Customer detail — "New Ticket" button creates ticket pre-filled with customer
Click "New Ticket" on a customer profile and verify it navigates to POS/ticket creation with this customer already selected.

### 50. Customer detail — phone number should be clickable (tel: link)
Verify clicking the phone number on a customer profile initiates a phone call (or shows the tel: protocol handler on desktop).

---

## INVENTORY (/inventory)

### 51. Inventory "PLP / MS" toggle — verify it filters by supplier source
The toggle labeled "PLP / MS" next to the Filters button should filter between PhoneLcdParts and Mobilesentrix sourced items. Verify toggling it actually changes the visible items.

### 52. Inventory stock adjustment +/- buttons — verify they work and log movements
Click the "+" button next to a stock count and verify it increments the quantity and creates a stock_movement record with reason, user, and timestamp.

### 53. Inventory "Order" link for zero-stock items — verify it navigates to supplier
Items with 0 stock show an orange "Order" link. Verify clicking it either opens the supplier website for that item or adds it to the parts order queue.

### 54. Inventory item detail page — verify all fields are editable
Navigate to an inventory item detail and verify you can edit: name, SKU, UPC, cost price, retail price, tax class, reorder level, supplier, description. Verify changes persist after save.

### 55. Inventory "New Item" form — verify validation
Click "+ New Item" and try submitting with empty required fields. Verify validation errors appear for required fields (name at minimum).

### 56. Inventory bulk actions — verify select-all and bulk delete/export
Select multiple items using checkboxes and verify a bulk action bar appears with options.

### 57. Inventory low stock badge — verify count matches filtered results
The "16 low stock" badge in the header should match the number of items shown when filtering to low-stock items only.

### 58. Inventory "Services" tab — verify service catalog items display
Click the "Services" tab and verify it shows repair service catalog items (labor charges, diagnostic fees, etc.) separately from physical products.

---

## INVOICES (/invoices)

### 59. Invoice KPI cards — verify numbers match filtered data
Total Sales shows $146,918.01. Change the date filter to "Today" and verify the KPI cards update to show only today's sales. Verify the numbers match the sum of invoices visible in the filtered list.

### 60. Invoice Payment Status donut chart — verify it's interactive
Click on a segment of the donut chart (e.g., "Paid 857") and verify it filters the invoice list to show only paid invoices.

### 61. Invoice "Overdue" tab — verify correct filtering
Click the "Overdue" tab and verify it shows only invoices that are unpaid AND past their due date. Verify the count matches.

### 62. Invoice detail — "Record Payment" modal amount validation
Open an unpaid invoice, click "Record Payment", try entering $0 or a negative amount. Verify validation prevents submission. Try entering an amount greater than the balance due and verify behavior (should warn about overpayment).

### 63. Invoice detail — "Pay via Terminal" BlockChyp button
On an unpaid invoice's Record Payment modal, verify the green "Pay via Terminal" button appears (when BlockChyp is enabled) and clicking it shows "Waiting for terminal..." state.

### 64. Invoice detail — Print button generates correct output
Click "Print" on an invoice detail page and verify the print preview shows a professional invoice with: store logo, store info, customer info, line items, tax, totals, invoice number, date.

### 65. Invoice detail — Void button and confirmation
Click "Void" on an invoice, verify a confirmation dialog appears, confirm, and verify the invoice status changes to "Void" and (if configured) stock is restored for the line items.

### 66. Invoice list — search by invoice number
Type an invoice number (e.g., "INV-881") in the search box and verify the correct invoice appears.

---

## CATALOG (/catalog)

### 67. Catalog sync progress — verify live sync status
Click the green "Sync" button on either Mobilesentrix or PhoneLcdParts and verify a progress indicator appears showing items being synced.

### 68. Catalog "Import" button per item — verify it creates inventory item
Click the orange "Import" button on a catalog item and verify it creates a new inventory item with the catalog item's data (name, SKU, price, image). Verify the import modal shows markup percentage and calculated retail price.

### 69. Catalog search debounce — verify it searches as you type
Type a part name in the search box and verify results filter in real-time with a slight debounce (300ms). Verify "No results" state shows if no matches found.

### 70. Catalog "Import From CSV" tab — verify file upload works
Switch to the "Import From CSV" tab and verify you can upload a CSV file or paste CSV data. Verify the import processes and creates inventory items.

### 71. Catalog external link icons — verify they open supplier website
Each catalog item has a small external link icon. Verify clicking it opens the supplier product page in a new tab.

---

## EXPENSES (/expenses)

### 72. Expenses "Add Expense" form — verify creation flow
Click "+ Add Expense" and verify the form opens with fields for: date, category, amount, description, payment method. Submit a test expense and verify it appears in the list.

### 73. Expenses category filter — verify filtering
After adding expenses, use the "All Categories" dropdown to filter by category and verify only matching expenses appear.

### 74. Expenses KPI cards should update when expenses are added
After adding expenses, verify the "Total Expenses" and "Count" KPI cards update to reflect the new totals.

---

## PURCHASE ORDERS (/purchase-orders)

### 75. Purchase Orders "New Purchase Order" form — verify creation flow
Click "+ New Purchase Order" and verify the form opens with fields for: supplier selection, items, quantities, unit costs. Submit a PO and verify it appears in the list.

### 76. Purchase Orders — receive items flow
After creating a PO, verify you can "Receive" items which should increment inventory stock for each received item.

---

## MESSAGES / COMMUNICATIONS (/communications)

### 77. Messages "New" button — verify new conversation creation
Click the "+ New" button and verify it opens a compose dialog where you can enter a phone number and message.

### 78. Messages conversation list — verify unread count badge matches
The "Unread 12" tab should show exactly 12 unread conversations. Click "Unread" and count the conversations.

### 79. Messages conversation — verify sending a message works
Open a conversation, type a message in the compose box, click Send. Since SMS_PROVIDER=console, verify the message appears in the thread as "sent" and logs to the server console.

### 80. Messages "Resolved" button — verify it marks conversation resolved
Click the "Resolved" button on a conversation and verify it moves the conversation out of the unread/active list.

### 81. Messages "Remind" button — verify reminder scheduling
Click the "Remind" button and verify it shows a reminder time picker. Set a reminder and verify it triggers at the scheduled time.

### 82. Messages "Link Customer" on Unknown Caller — verify linking flow
On an Unknown Caller conversation, click "Link Customer" and verify it opens a customer search/create dialog to associate the phone number with a customer record.

### 83. Messages "Flagged" and "Pinned" filter tabs — verify filtering
Click "Flagged" and verify only flagged conversations appear. Click "Pinned" and verify only pinned conversations appear.

---

## LEADS (/leads)

### 84. Leads "New Lead" form — verify creation flow
Click "+ New Lead" and verify the form opens with fields for: name, phone, email, source, service type, device, assigned to. Submit and verify the lead appears in the list.

### 85. Leads status filter pills — verify each filter works
Click each status pill (All, New, Contacted, Scheduled, Converted, Lost) and verify the list filters correctly.

### 86. Leads — convert to ticket
Open a lead detail and verify there's a "Convert to Ticket" button that creates a ticket pre-filled with the lead's data.

---

## CALENDAR (/calendar)

### 87. Calendar Month/Week/Day view toggles — verify each view renders
Currently on Month view. Click "Week" and verify a week view with time slots appears. Click "Day" and verify a single-day view with hourly slots appears.

### 88. Calendar "New Appointment" form — verify creation
Click "+ New Appointment" and verify a form opens with: customer, service type, date, time slot, assigned technician, notes. Submit and verify the appointment appears on the calendar.

### 89. Calendar navigation arrows — verify month/week/day advance
Click the right arrow to advance to May 2026 and verify it shows the correct month. Click left arrow to go back.

### 90. Calendar "Today" button — verify it returns to current date
After navigating to a different month, click "Today" and verify it returns to April 2026 with today (April 3) highlighted.

### 91. Calendar click on a date — verify appointment creation
Click on an empty date cell in the calendar and verify it opens the new appointment form pre-filled with that date.

---

## ESTIMATES (/estimates)

### 92. Estimates "New Estimate" form — verify creation flow
Click "+ New Estimate" and verify the form opens with: customer selection, line items (parts + labor), validity period, notes. Submit and verify it appears in the list.

### 93. Estimates status filter pills — verify each works
Click each pill (All, Draft, Sent, Approved, Rejected, Converted) and verify filtering.

### 94. Estimates — convert to ticket
Open an estimate detail and verify there's a "Convert to Ticket" button that creates a ticket from the estimate's line items.

### 95. Estimates — send to customer
Open an estimate and verify you can send it to the customer via SMS or email for approval.

---

## EMPLOYEES (/employees)

### 96. Employees "Clock In" button — verify it records clock entry
Click "Clock In" next to Pavel Ivanov and verify the status changes from "Clocked Out" to "Clocked In" with a timer. Verify a clock_entries record is created in the database.

### 97. Employees "Clock Out" flow — verify hours are recorded
After clocking in, click "Clock Out" and verify the hours worked are calculated and the "Hours This Week" column updates.

### 98. Employees expand row (arrow) — verify employee detail
Click the expand arrow (">") next to an employee and verify it shows additional details: recent clock entries, commission info, assigned tickets.

### 99. Employees "Add Employee" button — verify user creation
Click "+ Add Employee" and verify a form opens to create a new user with: name, email, role, PIN, password setup. Note: this should link to Settings → Users or create users directly.

### 100. Employees "Settings → Users" link in info banner — verify navigation
Click the "Settings → Users" link in the blue info banner and verify it navigates to the Settings page with the Users tab active.

---

## REPORTS (/reports)

### 101. Reports "Unique Customers: 0" on Sales tab — appears to be a bug
With 109 invoices in the 30-day period, the "Unique Customers" KPI shows 0. This is likely a query bug — the SQL may be counting customer_id but most imported invoices have customer_name "Walk-in" or NULL customer_id. Need to fix the unique customer count logic.

### 102. Reports "Payment Method Breakdown" shows "No payment data"
Despite having paid invoices, the Payment Method Breakdown section shows "No payment data for this period." The payments table may not have properly linked payment_method data for imported invoices. Need to investigate.

### 103. Reports Tickets tab — verify ticket metrics are correct
Click the "Tickets" tab and verify: ticket counts by status, average repair time, tickets by technician, tickets by device type. Cross-reference with the actual ticket list data.

### 104. Reports Employees tab — verify employee performance metrics
Click the "Employees" tab and verify: hours worked, tickets completed, commission earned, average repair time per tech.

### 105. Reports Inventory tab — verify inventory value calculation
Click the "Inventory" tab and verify: total inventory value (sum of quantity * cost_price for all items), items below reorder level, top selling parts, stock movement history.

### 106. Reports Tax tab — verify tax collection report
Click the "Tax" tab and verify: total tax collected, breakdown by tax class (Colorado 8.865% vs Tax Exempt 0%), tax by date range.

### 107. Reports Insights tab — verify charts render
Click the "Insights" tab and verify all charts and visualizations render correctly with data.

### 108. Reports CSV Export — verify all report tabs can export
Click the "Export" button on each report tab and verify a CSV downloads with the correct data for that report type.

### 109. Reports date range presets — verify "Today", "7 Days", "30 Days", "All" filter data
Click each date range preset and verify the KPI numbers and charts update accordingly.

---

## SETTINGS (/settings)

### 110. Settings "Search settings" bar — verify it filters tabs
Type "blockchyp" or "terminal" in the search settings bar and verify it highlights or filters to the "Payment Terminal" tab.

### 111. Settings "Payment Terminal" tab — verify all 14 config fields save
Navigate to Settings → Payment Terminal, fill in all fields (API Key, Bearer Token, Signing Key, Terminal Name, test mode, T&C text, etc.), click Save Changes, refresh the page, and verify all values persisted.

### 112. Settings "Payment Terminal" — Test Connection button
After entering BlockChyp credentials, click "Test Connection" and verify it either shows a green "Connected: Front Counter (firmware X.X.X)" or a red error message.

### 113. Settings Ticket Statuses — verify add/edit/delete/reorder
Add a new custom status, edit its name and color, drag to reorder, delete it. Verify each action works and persists.

### 114. Settings Tax Classes — verify rate changes apply to new invoices
Change a tax rate, create a new ticket/invoice, and verify the new rate is applied. Verify old invoices are not retroactively changed.

### 115. Settings Payment Methods — verify add/edit/deactivate
Add a new payment method (e.g., "Apple Pay"), verify it appears in the POS payment method selector. Deactivate an existing method and verify it disappears from POS.

### 116. Settings Customer Groups — verify group pricing
Create a customer group with a discount (e.g., "VIP 10% off"), assign a customer to the group, check in the customer at POS, and verify the discount is auto-applied.

### 117. Settings Users tab — verify user CRUD
Add a new user with technician role, set a PIN, verify the user appears in employee lists and can be assigned to tickets.

### 118. Settings Repair Pricing tab — verify price matrix
Set prices for specific device+service+grade combinations. Then go to POS, select that device and service, and verify the preset price appears instead of "Custom".

### 119. Settings Tickets & Repairs tab — verify toggles have effect
Toggle each setting (e.g., "Require pre-condition check", "Auto-assign technician", "Default due date") and verify the corresponding behavior changes in the ticket creation flow.

### 120. Settings POS tab — verify POS behavior toggles
Toggle "Require PIN for sales", "Show products in POS", etc. and verify the POS page behavior changes accordingly.

### 121. Settings Invoices tab — verify invoice template fields
Change the invoice title, payment terms, footer text. Create a new invoice and verify the custom text appears on the printed invoice.

### 122. Settings Receipts tab — verify receipt configuration
Toggle receipt sections (show/hide pre-conditions, show/hide parts, show/hide signature line, etc.) and verify the printed receipt reflects the changes.

### 123. Settings Conditions tab — verify pre/post condition checklists
Add/edit/remove condition check items. Verify they appear in the POS check-in flow under "Pre-existing Conditions."

### 124. Settings Notifications tab — verify SMS/email template editing
Edit a notification template (e.g., "Ready for Pickup" SMS). Verify template variables like {{ticket_id}} and {{customer_name}} are listed and supported.

### 125. Settings Data Import tab — verify RepairDesk import flow
If RepairDesk API key is configured, verify the import flow can be started, shows progress, and imports tickets/customers/invoices.

---

## HEADER / GLOBAL

### 126. Global search (Ctrl+K) — verify cross-entity search
Press Ctrl+K (or click the header search bar) and verify the command palette opens. Search for a ticket number, customer name, invoice number, and inventory item. Verify each result navigates to the correct detail page.

### 127. Notifications bell — verify unread count and dropdown
Click the notification bell icon in the header. Verify it shows a dropdown with recent notifications. Verify clicking a notification navigates to the relevant record. Verify "Mark all as read" works.

### 128. Messages icon in header — verify it navigates to communications
Click the chat/messages icon in the header bar and verify it navigates to the communications page.

### 129. Theme toggle — verify dark/light mode switch
Click the theme toggle button (sun/moon icon) and verify the entire app switches between dark and light mode. Verify it persists after page reload.

### 130. User menu → Profile — verify profile page
Click the user avatar/name → "Profile" and verify it opens a profile page where you can change name, email, avatar.

### 131. User menu → Switch User — verify PIN-based user switching
Click "Switch User" and verify it prompts for a PIN code. Enter a valid PIN and verify it switches to that user's session.

### 132. User menu → Log Out — verify clean logout
Click "Log Out" and verify it navigates to the login page, clears the session, and prevents back-button access to protected pages.

### 133. Sidebar "Collapse" button — verify sidebar collapses to icons
Click "Collapse" at the bottom of the sidebar and verify it collapses to icon-only mode. Verify all navigation still works in collapsed mode. Verify the collapse state persists.

### 134. Sidebar "Recent" section — verify recent items are clickable
The sidebar bottom shows "RECENT: T-1137, T-2909, Abby Salazar, T-2908". Verify clicking each recent item navigates to the correct ticket or customer page.

### 135. Breadcrumbs on all detail pages — verify they look clickable
On every detail page (ticket, customer, invoice), verify breadcrumbs have visible hover styles (underline, color change) so users know they're clickable. Currently they look like plain text.

---

## DATA INTEGRITY

### 136. Customer duplicates from import — need dedup tool
4794 customers exist with massive duplication (same phone/name appearing 3-5 times). Build a customer merge/dedup tool that identifies duplicates by phone number and allows merging records.

### 137. Invoices with "Walk-in" customer — no linked customer record
Many invoices show "Walk-in" as the customer name with no linked customer_id. These should either be linked to an actual customer record or displayed differently so they don't pollute customer counts.

### 138. Tickets with $0.00 total — many tickets have no pricing
A significant number of tickets show $0.00 total, meaning no price was set during check-in. These either need prices added retroactively or should be flagged for review.

### 139. Ticket device field showing "--" for issue/problem
Many tickets show "--" in the Issue column, meaning no problem description was entered. The check-in flow should encourage (or require) entering a problem description.

---

## MISSING FEATURES / IMPROVEMENTS

### 140. No password reset / forgot password flow
The login page has no "Forgot Password?" link and the backend has no password reset endpoint. If an employee forgets their password, the only recovery is direct database access.

### 141. Login form — no show/hide password toggle
The password field on the login page has no eye icon to toggle password visibility, which is a standard UX pattern.

### 142. Login form — empty submission shows no error
Clicking "Continue" with empty username and password fields produces no visible error message, leaving the user confused.

### 143. 2FA invalid code — no error feedback
Entering a wrong 2FA code clears the fields but shows no error message like "Invalid code" or "Code expired."

### 144. No second user account for role testing
Only one user exists (admin). Need to create at least one technician account to test role-based access controls and verify restricted permissions.

### 145. Phone numbers don't auto-format during entry
When typing "3035551234" in a phone field, it stays as raw digits. Should auto-format to "(303) 555-1234" as you type.

### 146. No customer merge functionality
With thousands of duplicate customers, there's no way to merge two customer records. Need a merge tool that combines tickets, invoices, and communications under one record.

### 147. No first-run setup wizard
After fresh installation, there's no guided setup to configure store info, create first employee, set tax rates, and walk through a test ticket.

### 148. Ticket detail "Est. Revenue" always shows "N/A (no cost data)"
Every ticket's billing sidebar shows this because no cost prices are set on parts. Should either hide this line when cost data is unavailable or show it in a muted style.

### 149. Print page should use dynamic store info from settings
The receipt/label print page should read store name, address, phone, and logo from the settings instead of hardcoded values.

### 150. Email sending — SMTP not configured
The email notification service (nodemailer) exists in code but no SMTP credentials are configured. Notifications that should send email (like "Ready for Pickup") only work for SMS.

### 151. Automations system — rules never execute
The automations CRUD exists but the trigger engine doesn't. Automation rules can be created in settings but they never fire. Need to build the execution engine or remove the UI.

### 152. TV Display page (/tv) — verify it loads and auto-refreshes
Navigate to `/tv` and verify it shows active tickets in a display format suitable for a wall-mounted TV. Verify it auto-refreshes without manual interaction.

### 153. Customer tracking page (/track) — verify public access
Navigate to the tracking URL (no auth required) and verify customers can check their repair status by entering a phone number or ticket number.

### 154. Photo capture page (/photo-capture) — verify mobile QR flow
Verify the QR code generated during check-in opens a mobile-friendly photo upload page where customers can take device photos from their phone.

### 155. Expenses not included in dashboard or reports
Even if expenses are added, they don't appear in the dashboard KPI cards or the reports calculations. Net Profit should subtract expenses from revenue.

### 156. Inventory item edit — no price history or audit trail
When changing an inventory item's price, there's no record of what the previous price was or when it changed. Add a price history log.

### 157. No keyboard shortcuts documentation
The app has Ctrl+K for search but there may be other keyboard shortcuts that aren't documented anywhere. Add a keyboard shortcuts help modal (press "?" to see all shortcuts).

### 158. Sidebar navigation — "Estimates" is under "Communications" section
Estimates are not a communication feature — they should be under "Operations" alongside Invoices, or have their own "Sales" section.

### 159. No dark mode print stylesheet
When printing from dark mode, the print output may have dark backgrounds that waste ink. Need a `@media print` stylesheet that forces light theme.

### 160. Mobile responsiveness — sidebar doesn't collapse automatically
On narrow viewports (under 768px), the sidebar doesn't auto-collapse, potentially overlapping with content. Need responsive breakpoint handling.

---

*Total items: 160. Each item includes detailed context about what to check, where it is, and what the expected behavior should be.*
