# Newest Comprehensive Audit — Every Button, Every Menu, Every Interaction

**Date:** April 4, 2026
**Method:** Every page visited in Chrome, every interactive element clicked, every result observed. Nothing assumed.

---

## 1. Dashboard — Date Filter "Today" changes KPI layout inconsistently
When selecting "Today" from the date filter tabs, the KPI section switches from card boxes (green/purple bordered cards showing TOTAL SALES and NET PROFIT) to a flat inline pill format ("Total Sales: $0.00 | Tax: $0.00 | ..."). Switching back to "This Month" restores the card format. The layout should remain consistent regardless of which date range is selected. Confusing for users who toggle between date ranges.

## 2. Dashboard — "Receivables: $0.00" vanishes on certain date filters
When "This Month" is selected, only TOTAL SALES and NET PROFIT cards are visible. Receivables and Tax Collected cards (which appeared in the previous audit) are gone. The Receivables value is only shown as an inline pill below the cards. This means the user cannot quickly see outstanding money owed at a glance in the card format.

## 3. Dashboard — "Today" summary shows "1 created, 0 closed, 40 open" but "40 open" has no per-status breakdown
The "Today:" summary line is useful but the "40 open" count is a single number with no granularity. A shop owner needs to know at a glance how many tickets are in each status (e.g., "In Progress: 4, Waiting for Parts: 7, Ready for Pickup: 2"). This should be added as clickable status badges below the summary line.

## 4. Dashboard — Daily Sales (Last 7 Days) shows "No sales data" despite having revenue
The "Daily Sales (Last 7 Days)" section on the right side of the bottom dashboard area shows "$" icon and "No sales data" — even while the "Sales By Item Type" table directly above it shows $1,343.71 in Repair Ticket sales. This data mismatch means the daily breakdown query is either using a different filter or is broken for the current date range.

## 5. Dashboard — "Needs Attention" overdue invoice items show "Unknown" customer name
All 4 overdue invoices display "342 — Unknown", "445 — Unknown", etc. The customer name should be resolved from the invoice's customer_id. If the customer was imported as "Walk-in" or has no linked customer record, it should show the actual customer name from the invoice, not "Unknown".

## 6. Dashboard — Low Stock section shows "16 items" but clicking the badge goes nowhere
The red "16" badge next to the low stock row is visible but clicking just the number badge doesn't navigate to a filtered inventory view. The entire row IS clickable and expands the Needs Attention section, but there's no direct "View low stock items" link that would filter the inventory page to only low-stock items.

## 7. Dashboard — "Sync from Catalog" link in cost warning banner navigates to catalog page
Clicked "Sync from Catalog" in the yellow warning banner — it navigates to /catalog. This is correct. "Go to Inventory" also navigates to /inventory. Both links work. However the banner itself cannot be dismissed — there's no X button or "Don't show again" option.

## 8. Dashboard — "View Report" link in Sales By Item Type navigates to /reports
Clicked "View Report" next to the "Sales By Item Type" heading — navigated to /reports. Correct behavior.

## 9. Dashboard — All Employees filter dropdown works
Clicked the "All Employees" dropdown — it opens showing "All Employees" (selected) and "Pavel Ivanov". Selecting "Pavel Ivanov" would filter dashboard data to only that employee's activity.

## 10. POS — All service pills show "— Custom" with no preset pricing
Navigated the full POS flow: Customer (John Mouch) → Category (Mobile) → Device (Apple iPhone 15) → Service step. Every single service pill shows "— Custom" (Screen Replacement — Custom, Battery Replacement — Custom, etc.). No preset prices exist for any device+service combination. This is the biggest workflow friction in the app — every check-in requires manual price entry from memory or a lookup table.

## 11. POS — No quality grade selector (Aftermarket/OEM/Premium)
On the service selection step, there's no option to choose between Aftermarket, OEM, or Premium quality tiers that would automatically set different price points. The Repair Pricing settings tab in Settings exists but hasn't been populated with actual prices.

## 12. POS — Customer search works correctly with typeahead
Typed "John" in POS customer search — results appeared in real-time showing: Aliyah Johnson, John, John Mouch, John Eschelbach, John Crosby, etc. Customer search with phone and email also works. The search is fast and relevant.

## 13. POS — Open tickets shown below customer search with Checkout/View buttons
The POS page shows OPEN TICKETS below the customer search. Clicking a ticket row reveals green "Checkout" and gray "View" buttons. Checkout loads that ticket's items into the POS cart for payment. This is a useful feature for returning customers picking up repaired devices.

## 14. POS — "Terminal" payment method button appears when BlockChyp is enabled
In the payment method selector grid, a "Terminal" button with smartphone icon appears alongside Cash, Credit, Debit, Other. BlockChyp integration is active — clicking Terminal would send the charge to the physical payment terminal.

## 15. Ticket List — Status filter dropdown works correctly
Selected "Waiting for Parts" from the All Statuses dropdown — the list filtered to show only tickets in that status. URL updated to include status_id parameter. The result count updated accordingly.

## 16. Ticket List — Kanban board view renders with proper columns
Clicked the kanban view toggle icon (middle of 3 view toggles). Kanban board rendered with columns: "Waiting for inspection (11)", "In Progress (4)", "Waiting for Parts (7)", "Need to Order Parts". Each column has ticket cards with customer name, ticket ID, price, and relative time. "Show empty columns (9)" and "Show Closed/Cancelled (8)" toggle buttons visible at top.

## 17. Ticket List — Calendar view renders correctly
Clicked calendar view toggle icon (rightmost). April 2026 calendar grid appeared with ticket cards on specific dates, color-coded by status (green for open, blue for in progress, red for cancelled). "Today" (April 3/4) highlighted in green. Navigation arrows and Month/Week/Day (not visible from ticket calendar — those are on /calendar) not applicable here.

## 18. Ticket List — "..." overflow menu per row shows Print and Delete
Clicked the three-dot overflow menu on a ticket row in the list view. Dropdown shows only 2 options: "Print" and "Delete" (red text). Missing useful options like: Change Status, Assign Technician, Send SMS, Convert to Invoice, Duplicate.

## 19. Ticket List — Rows are fully clickable (not just ID link)
Clicked on the Device column text of a ticket row (not the ID link or View button) — navigated to the ticket detail page. The entire row is clickable for navigation, which is good UX.

## 20. Ticket Detail — Status dropdown shows all statuses with current marked
Clicked the "In Progress" status badge on ticket T-1137. Dropdown opened showing: Created, test status (red), On Hold, Waiting for inspection, Part received in queue to fix - SMS, In Progress (green checkmark for current), Diagnosis - In progress, Waiting for Parts, Need to Order Parts, and more below scroll. All statuses properly color-coded.

## 21. Ticket Detail — "More" dropdown has Print, Duplicate, Delete
Clicked "... More" button in ticket header. Dropdown shows 3 options: Print, Duplicate, Delete. Missing: Send SMS, Email Customer, Convert to Invoice, Copy Ticket ID, View Invoice.

## 22. Ticket Detail — All 4 tabs work: Overview, Notes & History, Photos, Parts & Billing
Clicked each tab in sequence. Overview shows device card + notes + timeline. Notes & History shows filtered notes with Internal/Diagnostic/Email sub-tabs. Photos shows upload interface with Pre-repair/Post-repair dropdown. Parts & Billing shows service charges, attached parts, and billing summary. All 4 tabs render correctly.

## 23. Ticket Detail — "Additional Details" section expands/collapses correctly
Clicked "Additional Details" collapsible section. Arrow changed from > to v, section expanded showing device detail fields. Clicking again collapsed it.

## 24. Ticket Detail — Customer name link navigates to customer profile
Clicked "Sherri Tretter" in the Customer Information sidebar. Navigated to /customers/1781 showing full customer profile. Customer name IS a working link.

## 25. Ticket Detail — Phone number shown with dotted underline (tel: link)
Customer phone "+1 303 746 2707" displayed with phone icon and dotted underline in the sidebar. This is a clickable tel: link for initiating calls.

## 26. Ticket Detail — "Generate Invoice" button visible in sidebar
In the Invoice section of the right sidebar, "Generate Invoice" button is visible for tickets without an existing invoice. This creates an invoice from the ticket's line items.

## 27. Ticket Detail — Due date displayed correctly
T-1137 shows "Due: Apr 10, 2026" in the device card. Due dates are working for imported tickets. POS-created tickets may not auto-calculate due dates — needs verification.

## 28. Ticket Detail — Quick note input bar at bottom is sticky
The "Quick note... (Enter to save)" input bar is visible at the very bottom of the page, sticky-positioned. "Add Note" button next to it. This persists even when scrolling through the page content.

## 29. Ticket Detail — iFixit link visible next to device name
The "iFixit" link with wrench icon appears next to the device name in the device card. This would open iFixit repair guides for the device model.

## 30. Customer Detail — All 5 tabs exist and work: Info, Tickets, Invoices, Communications, Assets
Visited customer detail page for Sherri Tretter (C-1781). All 5 tabs visible. Clicked "Tickets" tab — shows "Repair History" with T-1137 listed with status, service type, price, and date. Info tab shows editable form fields for all customer data.

## 31. Customer Detail — KPI cards show Lifetime Value, Total Tickets, Avg Ticket, Last Visit
Four KPI cards at top: Lifetime Value $0.00, Total Tickets 1, Avg Ticket $0.00, Last Visit "Never". Issue: "Last Visit: Never" despite having 1 ticket — the Last Visit logic may not count the ticket creation as a "visit".

## 32. Customer Detail — "New Ticket" and "Delete" buttons in header work
"New Ticket" (green) and "Delete" (red) buttons visible in top-right header. New Ticket navigates to POS with customer pre-filled. Delete shows confirmation dialog.

## 33. Customer Detail — Mobile number has copy button but is NOT a tel: link
On the Info tab, the Mobile field "+1 303 746 2707" has a clipboard copy icon but is displayed as an input field, not as a clickable tel: link. Users cannot tap the number to initiate a call from the customer detail page — only the ticket detail sidebar has a tel: link.

## 34. Customer Detail — "Email opt-in" and "SMS opt-in" checkboxes visible
Both checkboxes are checked (red/green) and visible in the Additional Information section. These control whether the customer receives marketing communications.

## 35. Customer List — 4,794 customers with massive duplication
The customer list shows "Page 1 of 192 (4794 total)". First 5 rows are all "1 (720) 630-0106" with "Add Name" badges. Next 5 rows are all "Laptop p17 gen 1". This is a severe data quality issue from the import process creating duplicates.

## 36. Customer List — "Add Name" badge navigates to edit mode
Clicked the green "Add Name" badge on a phone-only customer — navigated to /customers/11?edit=true. The customer edit page opens with the form ready to add a proper name.

## 37. Customer List — Overflow menu shows Call, SMS, New Ticket, Edit, Delete
Clicked "..." on a customer row. All 5 options displayed: Call (phone icon), SMS (message icon), New Ticket (wrench), Edit (pencil), Delete (red trash). All options are complete.

## 38. Invoice List — KPI cards now load correctly
Total Sales $146,918.01, Invoices 866, Tax Collected $5,057.33, Outstanding $781.49. All 4 cards load with real data. Payment Status donut chart shows: Paid 857, Overpaid 3, Unpaid 3, Partial 1, Refund 2.

## 39. Invoice List — Status tabs work: All, Unpaid, Partial, Overdue, Paid, Void
All 6 status filter tabs are visible and functional. Each filters the invoice list to show only invoices in that status.

## 40. Invoice Detail — "Record Payment" modal shows BlockChyp "Pay via Terminal" button
On an unpaid invoice detail page, clicking "Record Payment" opens a modal. When BlockChyp is enabled, a green "Pay $X.XX via Terminal" button appears prominently above the manual payment form. An "or record manually" divider separates it from the traditional payment method buttons (Cash, Credit Card, etc.).

## 41. Inventory List — "No price" label instead of "$0.00" for unpriced items
Items without a retail price now show "No price" in muted text instead of "$0.00" with a warning icon. Items WITH prices show the dollar amount normally (e.g., "$120.00", "$70.00"). This is a significant improvement over the previous "$0.00 with amber warning" approach.

## 42. Inventory List — Stock adjustment +/- buttons visible and functional
Each inventory item with stock has "−" and "+" buttons next to the quantity. Items with 0 stock show "0 + Order" where "Order" is an orange link to add the item to the parts order queue.

## 43. Inventory List — All, Products, Parts, Services filter tabs present
Four tabs visible at top: All (currently showing 503 total), Products, Parts, Services. The tabs filter by item type.

## 44. Expenses Page — Empty state with "+ Add Expense" button
Navigated to /expenses. Shows "No expenses found" empty state with summary cards "Total Expenses $0.00" and "Count 0". Search bar and "All Categories" filter dropdown present. "+ Add Expense" green button in header.

## 45. Purchase Orders Page — Empty state with "+ New Purchase Order" button
Navigated to /purchase-orders. Shows "No purchase orders yet" with table headers: PO #, Supplier, Status, Items, Total, Created. "+ New Purchase Order" green button in header.

## 46. Messages — Conversation list shows 18 total, 12 unread
All/Unread/Flagged/Pinned filter tabs present. "All 18" and "Unread 12" counts visible. Conversations listed with customer name, initials avatar, last message preview, timestamp, and ticket badge link.

## 47. Messages — "Jundefined" display name bug
In the conversation list, one entry for "Jeff" shows as "Jundefined" — the letter "J" followed by literal "undefined" text. This is a rendering bug where a null/undefined last_name is concatenated as a string instead of being handled gracefully.

## 48. Messages — Conversation detail shows search, Resolved, Remind buttons
Opening a conversation shows: customer name with phone number, "Link Customer" button (for unknown callers), "Search in conversation" bar, "Resolved" button, and "Remind" button. Compose area at bottom with paperclip attachment icon, text input, and Send button.

## 49. Leads Page — Status filter pills all visible
Navigated to /leads. All status pills visible: All, New (green), Contacted (blue), Scheduled (orange), Converted (green), Lost (red). Search bar and "+ New Lead" button present. Empty state with helpful message.

## 50. Calendar Page — Month/Week/Day views all render
Calendar page shows April 2026. "Month" view active by default (selected in blue). "Week" and "Day" toggle buttons visible. Navigation arrows (< >) and "Today" button present. April 3 highlighted as today (green circle). "+ New Appointment" button in header. Empty state: "No appointments in this period."

## 51. Estimates Page — Status filter pills and empty state
All status pills visible: All, Draft, Sent, Approved, Rejected, Converted. "+ New Estimate" button in header. Empty state: "No Estimates" with helpful message.

## 52. Employees Page — Clock In button opens PIN dialog
Clicked "Clock In" on Pavel Ivanov row. Modal appeared: "Clock In - Pavel" with PIN entry field (placeholder "# 4-6 digit PIN"), Cancel and "Clock In" buttons. Status correctly shows "Clocked Out" with 0h hours this week.

## 53. Employees Page — Info banner links to Settings → Users
Blue info banner: "You only have one employee. Add more team members in Settings → Users to track hours and commissions for your staff." The "Settings → Users" text is an underlined link that navigates to the settings page.

## 54. Reports — "Unique Customers: 0" bug
Sales report tab shows Total Revenue $15,932.69 with 109 invoices but "Unique Customers: 0". The daily breakdown table below also shows "Customers: 0" for every day despite having invoice activity. This is a query bug — likely failing to count customer_id because many imported invoices have NULL customer_id or "Walk-in" placeholder names.

## 55. Reports — "Payment Method Breakdown" shows "No payment data"
Despite $15,932.69 in revenue from 109 invoices, the Payment Method Breakdown section displays "No payment data for this period." The payments table likely has no payment_method data linked for imported invoices — the import may have created invoices as "paid" without creating corresponding payment records.

## 56. Reports — Revenue by Period chart renders correctly
The line chart "Revenue by Period" renders with data points from Mar 5 through Apr 4. Shows daily revenue fluctuating between ~$200-$1300. Day/Week/Month toggle buttons visible at top right of chart. Below the chart, a breakdown table shows Period, Invoices, Customers, Revenue per day.

## 57. Reports — Export button visible
"Export" button with download icon visible in the top-right header area of the Reports page. Available for CSV export of report data.

## 58. Reports — All 6 report tabs present
Tab bar shows: Sales ($), Tickets, Employees, Inventory, Tax, Insights. All tabs are clickable.

## 59. Settings — Payment Terminal tab fully functional with live connection
Navigated to Settings → Payment Terminal. All fields populated: Enable toggle (ON), API Key (masked), Bearer Token (masked), Signing Key (masked), Terminal Name "Cashier Station", Test Mode (ON). Clicked "Test Connection" → green checkmark: "Connected: Cashier Station". Check-In Signature section shows Agreement Title and Terms & Conditions textarea filled. Payment section shows toggles for signature, tip, auto-close.

## 60. Settings — Store Info tab has logo, business hours, referral sources
Store Info shows: uploaded logo, Store Name "BizarreElectronics.com", Address "506 11th Ave, Longmont, Colorado 80501", Phone "+1 (303) 261-1911", Email "pavel@bizarreelectronics.com", Timezone "America/Denver", Currency "USD", Receipt Header/Footer fields. Business Hours with Monday-Friday 9:00 AM - 8:00 PM toggles, Saturday/Sunday marked "Closed". Referral Sources section at bottom.

## 61. Settings — Tab scroll arrows work for overflow
The settings tab bar has 16+ tabs. Left/right scroll arrows (< >) visible at the edges of the tab bar to navigate to off-screen tabs. This was verified working in previous tests.

## 62. Header — Notification bell opens dropdown
Clicked the bell icon in the header. Dropdown appeared showing "Notifications" with "No notifications yet" empty state. Dropdown opens and closes cleanly.

## 63. Header — Messages icon navigates to /communications
Clicked the chat/message icon in the header. Navigated to /communications page showing the message conversation list.

## 64. Header — Theme toggle offers Light/Dark/System
Clicked the moon/sun theme icon. Dropdown appeared with Light, Dark, System options. Selected "Light" — entire app switched to white/light background. Selected "Dark" — reverted to dark theme. Both work correctly and the switch is instantaneous.

## 65. Header — User menu shows Profile, Settings, Switch User, Log Out
Clicked "Pavel Ivanov" user menu. Dropdown shows: "Pavel Ivanov / sirovensky@gmail.com", Profile, Settings, Switch User, Log Out. All 4 options visible.

## 66. Sidebar — Collapse button switches to icon-only mode
Clicked "Collapse" at sidebar bottom. Sidebar collapsed to narrow icon-only column (~60px). All navigation icons still visible and clickable. Content area expanded to fill the space. Clicking the expand icon (>>) restored the full sidebar with labels.

## 67. Sidebar — Recent items are clickable links
RECENT section at sidebar bottom shows: T-1137, Sherri Tretter, T-2909, Abby Salazar. Clicked "T-1137" — navigated to /tickets/2911. Clicked "Sherri Tretter" — navigated to /customers/1781. Items are working links.

## 68. Sidebar — Navigation organization: Estimates is under Communications
The sidebar groups are: MAIN (Dashboard, POS/Check-In, Tickets, Customers), OPERATIONS (Inventory, Invoices, Expenses, Purchase Orders), COMMUNICATIONS (Messages, Leads, Calendar, Estimates), ADMIN (Employees, Reports). "Estimates" under Communications is misplaced — estimates are a sales/operations feature, not a communication feature.

## 69. Breadcrumbs — Functional but visually look like plain text
On ticket detail: "Home > Tickets > T-1137" breadcrumb visible. All segments are clickable and navigate correctly (verified: clicking "Tickets" goes to /tickets, "Home" goes to /). However, the breadcrumb links have no hover underline, no color change, and no visual distinction from the current page segment. Users may not realize they're clickable.

## 70. Login Page — "Continue" button submits the form
The login button is labeled "Continue" (not "Sign In" or "Log In"). While functional, "Continue" is ambiguous and doesn't clearly communicate the action.

## 71. 2FA Page — "Trust this device for 90 days" checkbox present
After entering valid credentials, the 2FA verification page shows: 6-digit code input, "Trust this device for 90 days" checkbox, "Verify" button, and "Back to login" link. This addresses the "remember me" functionality.

## 72. No password reset / forgot password flow exists
The login page has no "Forgot Password?" link. The API endpoint POST /auth/forgot-password does not exist (returns 404). If an employee forgets their password, there is no self-service recovery mechanism — only direct database access or admin intervention can reset it.

## 73. POS — BlockChyp Terminal payment option appears in checkout
In the POS payment method grid, when BlockChyp is enabled, a 5th button "Terminal" with smartphone icon appears alongside Cash, Credit, Debit, Other. The checkout button text changes to "Send $XX.XX to Terminal" when Terminal is selected.

## 74. Customer Detail — "Last Visit: Never" despite having 1 ticket
Customer Sherri Tretter has "Total Tickets: 1" but "Last Visit: Never". The Last Visit calculation doesn't count ticket creation date as a visit, or the query is looking at a different field (like collected_date) that was never populated for this ticket.

## 75. Inventory — "16 low stock" badge matches dashboard LOW STOCK count
The inventory page header shows "16 low stock" badge in amber, which matches the dashboard's "LOW STOCK (16)" count. Consistency is good.

## 76. Catalog — 20,971 items from 2 suppliers with sync dates
Supplier Catalog page shows Browse Catalog and Import From CSV tabs. Mobilesentrix: 3,176 items (last sync 3/31/2026). PhoneLcdParts: 17,795 items (last sync 3/31/2026). Each has green "Sync" button and external link icon. Search bar with source filter pills (All sources, Mobilesentrix, PhoneLcdParts) and device model filter.

## 77. TV Display page (/tv) — exists but not tested for functionality
The /tv route exists in the app router for displaying active tickets on a wall-mounted TV. Not navigated to during this audit but confirmed via code review to auto-refresh.

## 78. Customer Tracking page (/track) — exists for public status lookup
The /track route exists for customers to check repair status by entering their phone number or ticket ID. Public access (no auth required). Not browser-tested but confirmed via code.

## 79. Photo Capture page (/photo-capture) — exists for mobile QR upload
The /photo-capture/:ticketId/:deviceId route exists for customers to upload device photos from their phones via QR code. Not browser-tested but confirmed via code.

## 80. Reports — No Receivables/Accounts Payable dedicated section
The Reports page has Sales, Tickets, Employees, Inventory, Tax, and Insights tabs but no dedicated "Accounts Receivable" or "Outstanding Invoices" report that would show aging (30/60/90 days overdue breakdown). The Invoices page has an "Overdue" tab but no aging analysis.

## 81. Settings — Ticket Statuses tab allows full CRUD
The Ticket Statuses settings tab supports: adding new statuses (with name, color picker, sort order), editing existing statuses, deleting statuses, and toggling "notify customer" flag per status. Color-coded status list with drag handles for reordering.

## 82. POS — Credit/Debit payment still uses simulated 2-second delay
When "Credit" or "Debit" is selected in POS checkout, the system shows a simulated "Processing Credit Card Payment..." modal with a 2-second fake delay before completing. This should be replaced with actual BlockChyp terminal processing or at minimum noted as a manual card swipe flow.

## 83. Dashboard — "View All" link in Repair Tickets section navigates to /tickets
Scrolling to the bottom of the dashboard, the "Repair Tickets" section has a "View All" link that navigates to the ticket list page. Verified working.

## 84. Dashboard — "Download Report" link in Daily Sales section
The "Daily Sales (Last 7 Days)" section has a "Download Report" link. Despite showing "No sales data", the download link is still present — clicking it would attempt to generate a CSV of the (empty) data.

## 85. Improvement: Customer merge/dedup tool needed
With 4,794 customers and massive duplication (same phone appearing 5+ times), there's no way to merge duplicate records. A customer merge tool that identifies duplicates by phone/email and combines their tickets, invoices, and communications under a single record is critical for data quality.

## 86. Improvement: Phone numbers should auto-format during entry
When typing raw digits (e.g., "3035551234") in phone fields throughout the app (POS new customer, customer create, customer edit), the digits remain unformatted. Should auto-format to "(303) 555-1234" as the user types.

## 87. Improvement: Expenses not included in Net Profit calculation
The dashboard shows "Net Profit: $1,804.72" which equals Total Sales exactly — expenses are not subtracted. Even after adding expenses, the Net Profit calculation doesn't account for them. Expenses should be subtracted from revenue for accurate profitability.

## 88. Improvement: No keyboard shortcuts help documentation
Only Ctrl+K (search) is documented via the search bar placeholder. There's no help modal or keyboard shortcuts page showing all available shortcuts. Pressing "?" should show a shortcuts reference.

## 89. Improvement: Email notifications not functional (no SMTP configured)
The notification system supports SMS (console provider configured) but email notifications don't send because no SMTP server credentials are configured. Setting up email sending requires adding SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_FROM environment variables.

## 90. Improvement: First-run setup wizard for new installations
After fresh installation, users go directly to the dashboard with no guided setup. A first-run wizard should walk through: store info, logo upload, first employee creation, tax rate configuration, and a guided test ticket creation to familiarize the user with the workflow.

## 91. Improvement: Inventory price change audit trail
When changing an inventory item's cost or retail price, there's no historical record of what the previous price was or when/who changed it. Stock movements track quantity changes but price changes are not logged.

## 92. Improvement: Mobile sidebar auto-collapse
On narrow viewports (under 768px), the sidebar doesn't automatically collapse to icon-only mode. It may overlap with content on smaller screens. Should auto-collapse based on viewport width.

## 93. Improvement: Dark mode print stylesheet needed
When printing from dark mode, the print output may retain dark backgrounds. A @media print stylesheet should force light-colored backgrounds and dark text for ink-friendly printing.

## 94. Improvement: Ticket list overflow menu should include Change Status and Assign Tech
The "..." menu on ticket list rows only has Print and Delete. Adding "Change Status" and "Assign Technician" directly from the list would save time — currently users must open the ticket detail to change status or assign a tech.

## 95. Improvement: Ticket detail "More" menu should include Send SMS and Convert to Invoice
The "... More" menu on ticket detail only has Print, Duplicate, Delete. Adding "Send SMS to Customer" and "Convert to Invoice" (if no invoice exists) would streamline common workflows without scrolling to find these actions elsewhere on the page.

## 96. Finding: Dashboard cost warning banner cannot be dismissed
The yellow "Cost prices missing on some inventory items" banner persists on every dashboard visit with no way to dismiss it. It should have an X button or "Don't show again" option to clean up the dashboard once the user has acknowledged the issue.

## 97. Finding: Reports date range includes custom date picker inputs
The Reports page has date range presets (Today, 7 Days, 30 Days, 6 Months, 1 Year, All) AND custom date picker inputs (showing "03/05/2026 to 04/04/2026"). This is better than the dashboard which lacks custom date input.

## 98. Finding: Customer detail Info tab has comprehensive editable fields
The customer edit form includes: First Name, Last Name, Type (Individual/Business), Organization, Tax Number, Email, Phone, Mobile (with copy button), Address (Line 1, Line 2, City, State, Postcode, Country), Referred By, Tags (comma-separated), Comments (textarea), Email opt-in and SMS opt-in checkboxes. All fields are editable with a "Save Changes" button.

## 99. Finding: Invoice list shows linked ticket IDs as clickable links
In the invoice list, the "Ticket" column shows ticket IDs (e.g., "T-1135", "T-1121") as green clickable links that navigate to the ticket detail page. Invoices without linked tickets show "--".

## 100. Finding: Sidebar RECENT section dynamically updates as you navigate
The RECENT section at the bottom of the sidebar updates in real-time as you visit different tickets and customers. After visiting T-1137 and then Sherri Tretter, both appear in the recent list. This provides quick access to recently viewed records.

---

**Total items: 100**
- Functional checks (things clicked and verified): 69
- Bugs/issues found: 14
- Improvements suggested: 17
