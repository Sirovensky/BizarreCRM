import XCTest
@testable import Networking

/// Ground-truth path assertions for every typed endpoint factory.
///
/// Each test cross-checks the generated path string against the confirmed
/// server route (packages/server/src/routes/*.ts) and the mount prefix
/// from packages/server/src/index.ts.
///
/// Convention: `path_<Domain>_<methodName>` → asserts exact path string.
final class EndpointPathsTests: XCTestCase {

    // MARK: - Tickets
    // Mount: app.use('/api/v1/tickets', ...) — index.ts:1536
    // Routes: tickets.routes.ts

    func test_path_Tickets_list() {
        XCTAssertEqual(Endpoints.Tickets.list().path, "/api/v1/tickets")
    }

    func test_path_Tickets_create() {
        XCTAssertEqual(Endpoints.Tickets.create().path, "/api/v1/tickets")
    }

    func test_path_Tickets_detail() {
        XCTAssertEqual(Endpoints.Tickets.detail(id: 7).path, "/api/v1/tickets/7")
    }

    func test_path_Tickets_update() {
        XCTAssertEqual(Endpoints.Tickets.update(id: 7).path, "/api/v1/tickets/7")
    }

    func test_path_Tickets_delete() {
        XCTAssertEqual(Endpoints.Tickets.delete(id: 7).path, "/api/v1/tickets/7")
    }

    func test_path_Tickets_updateStatus() {
        // tickets.routes.ts:2101 — PATCH /:id/status
        XCTAssertEqual(Endpoints.Tickets.updateStatus(id: 5).path, "/api/v1/tickets/5/status")
    }

    func test_path_Tickets_addNote() {
        // tickets.routes.ts:2223 — POST /:id/notes
        XCTAssertEqual(Endpoints.Tickets.addNote(ticketId: 3).path, "/api/v1/tickets/3/notes")
    }

    func test_path_Tickets_updateNote() {
        // tickets.routes.ts:2281 — PUT /notes/:noteId
        XCTAssertEqual(Endpoints.Tickets.updateNote(noteId: 9).path, "/api/v1/tickets/notes/9")
    }

    func test_path_Tickets_deleteNote() {
        // tickets.routes.ts:2328 — DELETE /notes/:noteId
        XCTAssertEqual(Endpoints.Tickets.deleteNote(noteId: 9).path, "/api/v1/tickets/notes/9")
    }

    func test_path_Tickets_addDevice() {
        // tickets.routes.ts:2811 — POST /:id/devices
        XCTAssertEqual(Endpoints.Tickets.addDevice(ticketId: 3).path, "/api/v1/tickets/3/devices")
    }

    func test_path_Tickets_updateDevice() {
        // tickets.routes.ts:2966 — PUT /devices/:deviceId
        XCTAssertEqual(Endpoints.Tickets.updateDevice(deviceId: 11).path, "/api/v1/tickets/devices/11")
    }

    func test_path_Tickets_deleteDevice() {
        // tickets.routes.ts:3030 — DELETE /devices/:deviceId
        XCTAssertEqual(Endpoints.Tickets.deleteDevice(deviceId: 11).path, "/api/v1/tickets/devices/11")
    }

    func test_path_Tickets_addPart() {
        // tickets.routes.ts:3094 — POST /devices/:deviceId/parts
        XCTAssertEqual(Endpoints.Tickets.addPart(deviceId: 11).path, "/api/v1/tickets/devices/11/parts")
    }

    func test_path_Tickets_deletePart() {
        // tickets.routes.ts:3246 — DELETE /devices/parts/:partId
        XCTAssertEqual(Endpoints.Tickets.deletePart(partId: 99).path, "/api/v1/tickets/devices/parts/99")
    }

    func test_path_Tickets_updateChecklist() {
        // tickets.routes.ts:3359 — PUT /devices/:deviceId/checklist
        XCTAssertEqual(Endpoints.Tickets.updateChecklist(deviceId: 11).path, "/api/v1/tickets/devices/11/checklist")
    }

    func test_path_Tickets_convertToInvoice() {
        // tickets.routes.ts:2583 — POST /:id/convert-to-invoice
        XCTAssertEqual(Endpoints.Tickets.convertToInvoice(ticketId: 3).path, "/api/v1/tickets/3/convert-to-invoice")
    }

    func test_path_Tickets_kanban() {
        // tickets.routes.ts:1291 — GET /kanban
        XCTAssertEqual(Endpoints.Tickets.kanban().path, "/api/v1/tickets/kanban")
    }

    func test_path_Tickets_history() {
        // tickets.routes.ts:2734 — GET /:id/history
        XCTAssertEqual(Endpoints.Tickets.history(id: 3).path, "/api/v1/tickets/3/history")
    }

    // MARK: - Customers
    // Mount: app.use('/api/v1/customers', ...) — index.ts:1537
    // Routes: customers.routes.ts

    func test_path_Customers_list() {
        XCTAssertEqual(Endpoints.Customers.list().path, "/api/v1/customers")
    }

    func test_path_Customers_create() {
        XCTAssertEqual(Endpoints.Customers.create().path, "/api/v1/customers")
    }

    func test_path_Customers_detail() {
        XCTAssertEqual(Endpoints.Customers.detail(id: 20).path, "/api/v1/customers/20")
    }

    func test_path_Customers_update() {
        XCTAssertEqual(Endpoints.Customers.update(id: 20).path, "/api/v1/customers/20")
    }

    func test_path_Customers_delete() {
        XCTAssertEqual(Endpoints.Customers.delete(id: 20).path, "/api/v1/customers/20")
    }

    // MARK: - Invoices
    // Mount: app.use('/api/v1/invoices', ...) — index.ts:1544
    // Routes: invoices.routes.ts

    func test_path_Invoices_list() {
        XCTAssertEqual(Endpoints.Invoices.list().path, "/api/v1/invoices")
    }

    func test_path_Invoices_create() {
        XCTAssertEqual(Endpoints.Invoices.create().path, "/api/v1/invoices")
    }

    func test_path_Invoices_detail() {
        // invoices.routes.ts:363 — GET /:id
        XCTAssertEqual(Endpoints.Invoices.detail(id: 15).path, "/api/v1/invoices/15")
    }

    func test_path_Invoices_update() {
        // invoices.routes.ts:553 — PUT /:id
        XCTAssertEqual(Endpoints.Invoices.update(id: 15).path, "/api/v1/invoices/15")
    }

    func test_path_Invoices_stats() {
        // invoices.routes.ts:328 — GET /stats
        XCTAssertEqual(Endpoints.Invoices.stats().path, "/api/v1/invoices/stats")
    }

    func test_path_Invoices_recordPayment() {
        // invoices.routes.ts:660 — POST /:id/payments
        XCTAssertEqual(Endpoints.Invoices.recordPayment(invoiceId: 15).path, "/api/v1/invoices/15/payments")
    }

    func test_path_Invoices_void() {
        // invoices.routes.ts:803 — POST /:id/void
        XCTAssertEqual(Endpoints.Invoices.void(invoiceId: 15).path, "/api/v1/invoices/15/void")
    }

    func test_path_Invoices_bulkAction() {
        // invoices.routes.ts:892 — POST /bulk-action
        XCTAssertEqual(Endpoints.Invoices.bulkAction().path, "/api/v1/invoices/bulk-action")
    }

    // MARK: - Inventory
    // Mount: app.use('/api/v1/inventory', ...) — index.ts:1538
    // Routes: inventory.routes.ts

    func test_path_Inventory_list() {
        XCTAssertEqual(Endpoints.Inventory.list().path, "/api/v1/inventory")
    }

    func test_path_Inventory_create() {
        // inventory.routes.ts:950 — POST /
        XCTAssertEqual(Endpoints.Inventory.create().path, "/api/v1/inventory")
    }

    func test_path_Inventory_detail() {
        // inventory.routes.ts:798 — GET /:id
        XCTAssertEqual(Endpoints.Inventory.detail(id: 100).path, "/api/v1/inventory/100")
    }

    func test_path_Inventory_update() {
        // inventory.routes.ts:1034 — PUT /:id
        XCTAssertEqual(Endpoints.Inventory.update(id: 100).path, "/api/v1/inventory/100")
    }

    func test_path_Inventory_lowStock() {
        // inventory.routes.ts:284 — GET /low-stock
        XCTAssertEqual(Endpoints.Inventory.lowStock().path, "/api/v1/inventory/low-stock")
    }

    func test_path_Inventory_categories() {
        // inventory.routes.ts:313 — GET /categories
        XCTAssertEqual(Endpoints.Inventory.categories().path, "/api/v1/inventory/categories")
    }

    func test_path_Inventory_barcodeDetail() {
        // inventory.routes.ts:551 — GET /barcode/:code
        XCTAssertEqual(Endpoints.Inventory.barcodeDetail(code: "ABC123").path, "/api/v1/inventory/barcode/ABC123")
    }

    func test_path_Inventory_purchaseOrderList() {
        // inventory.routes.ts:1320 — GET /purchase-orders/list
        XCTAssertEqual(Endpoints.Inventory.purchaseOrderList().path, "/api/v1/inventory/purchase-orders/list")
    }

    func test_path_Inventory_createPurchaseOrder() {
        // inventory.routes.ts:1349 — POST /purchase-orders
        XCTAssertEqual(Endpoints.Inventory.createPurchaseOrder().path, "/api/v1/inventory/purchase-orders")
    }

    func test_path_Inventory_purchaseOrderDetail() {
        // inventory.routes.ts:1379 — GET /purchase-orders/:id
        XCTAssertEqual(Endpoints.Inventory.purchaseOrderDetail(id: 8).path, "/api/v1/inventory/purchase-orders/8")
    }

    // MARK: - Estimates
    // Mount: app.use('/api/v1/estimates', ...) — index.ts:1546
    // Routes: estimates.routes.ts

    func test_path_Estimates_list() {
        XCTAssertEqual(Endpoints.Estimates.list().path, "/api/v1/estimates")
    }

    func test_path_Estimates_create() {
        // estimates.routes.ts:143 — POST /
        XCTAssertEqual(Endpoints.Estimates.create().path, "/api/v1/estimates")
    }

    func test_path_Estimates_detail() {
        // estimates.routes.ts:487 — GET /:id
        XCTAssertEqual(Endpoints.Estimates.detail(id: 5).path, "/api/v1/estimates/5")
    }

    func test_path_Estimates_update() {
        // estimates.routes.ts:525 — PUT /:id
        XCTAssertEqual(Endpoints.Estimates.update(id: 5).path, "/api/v1/estimates/5")
    }

    func test_path_Estimates_delete() {
        // estimates.routes.ts:880 — DELETE /:id
        XCTAssertEqual(Endpoints.Estimates.delete(id: 5).path, "/api/v1/estimates/5")
    }

    // MARK: - Leads
    // Mount: app.use('/api/v1/leads', ...) — index.ts:1545
    // Routes: leads.routes.ts

    func test_path_Leads_list() {
        XCTAssertEqual(Endpoints.Leads.list().path, "/api/v1/leads")
    }

    func test_path_Leads_pipeline() {
        // leads.routes.ts:106 — GET /pipeline
        XCTAssertEqual(Endpoints.Leads.pipeline().path, "/api/v1/leads/pipeline")
    }

    func test_path_Leads_create() {
        // leads.routes.ts:295 — POST /
        XCTAssertEqual(Endpoints.Leads.create().path, "/api/v1/leads")
    }

    func test_path_Leads_detail() {
        // leads.routes.ts:405 — GET /:id
        XCTAssertEqual(Endpoints.Leads.detail(id: 2).path, "/api/v1/leads/2")
    }

    func test_path_Leads_update() {
        // leads.routes.ts:634 — PUT /:id
        XCTAssertEqual(Endpoints.Leads.update(id: 2).path, "/api/v1/leads/2")
    }

    func test_path_Leads_delete() {
        // leads.routes.ts:685 — DELETE /:id
        XCTAssertEqual(Endpoints.Leads.delete(id: 2).path, "/api/v1/leads/2")
    }

    // MARK: - Appointments
    // Mount: sub-routes of /api/v1/leads — leads.routes.ts:405,469,634,685

    func test_path_Appointments_list() {
        // leads.routes.ts:405 — GET /appointments
        XCTAssertEqual(Endpoints.Appointments.list().path, "/api/v1/leads/appointments")
    }

    func test_path_Appointments_create() {
        // leads.routes.ts:469 — POST /appointments
        XCTAssertEqual(Endpoints.Appointments.create().path, "/api/v1/leads/appointments")
    }

    func test_path_Appointments_update() {
        // leads.routes.ts:634 — PUT /appointments/:id
        XCTAssertEqual(Endpoints.Appointments.update(id: 4).path, "/api/v1/leads/appointments/4")
    }

    func test_path_Appointments_delete() {
        // leads.routes.ts:685 — DELETE /appointments/:id
        XCTAssertEqual(Endpoints.Appointments.delete(id: 4).path, "/api/v1/leads/appointments/4")
    }

    // MARK: - Expenses
    // Mount: app.use('/api/v1/expenses', ...) — index.ts:1581
    // Routes: expenses.routes.ts

    func test_path_Expenses_list() {
        XCTAssertEqual(Endpoints.Expenses.list().path, "/api/v1/expenses")
    }

    func test_path_Expenses_create() {
        // expenses.routes.ts:121 — POST /
        XCTAssertEqual(Endpoints.Expenses.create().path, "/api/v1/expenses")
    }

    func test_path_Expenses_detail() {
        // expenses.routes.ts:93 — GET /:id
        XCTAssertEqual(Endpoints.Expenses.detail(id: 6).path, "/api/v1/expenses/6")
    }

    func test_path_Expenses_update() {
        // expenses.routes.ts:147 — PUT /:id
        XCTAssertEqual(Endpoints.Expenses.update(id: 6).path, "/api/v1/expenses/6")
    }

    func test_path_Expenses_delete() {
        // expenses.routes.ts:184 — DELETE /:id
        XCTAssertEqual(Endpoints.Expenses.delete(id: 6).path, "/api/v1/expenses/6")
    }

    func test_path_Expenses_approve() {
        // expenses.routes.ts:375 — POST /:id/approve
        XCTAssertEqual(Endpoints.Expenses.approve(id: 6).path, "/api/v1/expenses/6/approve")
    }

    func test_path_Expenses_deny() {
        // expenses.routes.ts:404 — POST /:id/deny
        XCTAssertEqual(Endpoints.Expenses.deny(id: 6).path, "/api/v1/expenses/6/deny")
    }

    // MARK: - Employees
    // Mount: app.use('/api/v1/employees', ...) — index.ts:1555
    // Routes: employees.routes.ts

    func test_path_Employees_list() {
        // employees.routes.ts:173 — GET /
        XCTAssertEqual(Endpoints.Employees.list().path, "/api/v1/employees")
    }

    func test_path_Employees_performanceAll() {
        // employees.routes.ts:194 — GET /performance/all
        XCTAssertEqual(Endpoints.Employees.performanceAll().path, "/api/v1/employees/performance/all")
    }

    func test_path_Employees_detail() {
        // employees.routes.ts:224 — GET /:id
        XCTAssertEqual(Endpoints.Employees.detail(id: 3).path, "/api/v1/employees/3")
    }

    func test_path_Employees_create() {
        // employees.routes.ts:281 — POST /
        XCTAssertEqual(Endpoints.Employees.create().path, "/api/v1/employees")
    }

    func test_path_Employees_clockIn() {
        // employees.routes.ts:281 — POST /:id/clock-in
        XCTAssertEqual(Endpoints.Employees.clockIn(id: 3).path, "/api/v1/employees/3/clock-in")
    }

    func test_path_Employees_clockOut() {
        // employees.routes.ts:374 — POST /:id/clock-out
        XCTAssertEqual(Endpoints.Employees.clockOut(id: 3).path, "/api/v1/employees/3/clock-out")
    }

    func test_path_Employees_hours() {
        // employees.routes.ts:445 — GET /:id/hours
        XCTAssertEqual(Endpoints.Employees.hours(id: 3).path, "/api/v1/employees/3/hours")
    }

    // MARK: - Reports
    // Mount: app.use('/api/v1/reports', ...) — index.ts:1553
    // Routes: reports.routes.ts

    func test_path_Reports_dashboard() {
        // reports.routes.ts:52 — GET /dashboard
        XCTAssertEqual(Endpoints.Reports.dashboard().path, "/api/v1/reports/dashboard")
    }

    func test_path_Reports_dashboardKPIs() {
        // reports.routes.ts:289 — GET /dashboard-kpis
        XCTAssertEqual(Endpoints.Reports.dashboardKPIs().path, "/api/v1/reports/dashboard-kpis")
    }

    func test_path_Reports_sales() {
        // reports.routes.ts:616 — GET /sales
        XCTAssertEqual(Endpoints.Reports.sales().path, "/api/v1/reports/sales")
    }

    func test_path_Reports_tickets() {
        // reports.routes.ts:709 — GET /tickets
        XCTAssertEqual(Endpoints.Reports.tickets().path, "/api/v1/reports/tickets")
    }

    func test_path_Reports_inventory() {
        // reports.routes.ts:838 — GET /inventory
        XCTAssertEqual(Endpoints.Reports.inventory().path, "/api/v1/reports/inventory")
    }

    func test_path_Reports_employees() {
        // reports.routes.ts:782 — GET /employees
        XCTAssertEqual(Endpoints.Reports.employees().path, "/api/v1/reports/employees")
    }

    func test_path_Reports_tax() {
        // reports.routes.ts:895 — GET /tax
        XCTAssertEqual(Endpoints.Reports.tax().path, "/api/v1/reports/tax")
    }

    func test_path_Reports_insights() {
        // reports.routes.ts:547 — GET /insights
        XCTAssertEqual(Endpoints.Reports.insights().path, "/api/v1/reports/insights")
    }

    func test_path_Reports_partsUsage() {
        // reports.routes.ts:1232 — GET /parts-usage
        XCTAssertEqual(Endpoints.Reports.partsUsage().path, "/api/v1/reports/parts-usage")
    }

    // MARK: - Communications (SMS)
    // Mount: app.use('/api/v1/sms', ...) — index.ts:1554
    // Routes: sms.routes.ts

    func test_path_Communications_conversations() {
        // sms.routes.ts:209 — GET /conversations
        XCTAssertEqual(Endpoints.Communications.conversations().path, "/api/v1/sms/conversations")
    }

    func test_path_Communications_conversation() {
        // sms.routes.ts:361 — GET /conversations/:phone
        XCTAssertEqual(Endpoints.Communications.conversation(phone: "+15551234567").path,
                       "/api/v1/sms/conversations/+15551234567")
    }

    func test_path_Communications_send() {
        // sms.routes.ts:490 — POST /send
        XCTAssertEqual(Endpoints.Communications.send().path, "/api/v1/sms/send")
    }

    func test_path_Communications_unreadCount() {
        // sms.routes.ts:176 — GET /unread-count
        XCTAssertEqual(Endpoints.Communications.unreadCount().path, "/api/v1/sms/unread-count")
    }

    func test_path_Communications_markRead() {
        // sms.routes.ts:416 — PATCH /conversations/:phone/read
        XCTAssertEqual(Endpoints.Communications.markRead(phone: "+15551234567").path,
                       "/api/v1/sms/conversations/+15551234567/read")
    }

    func test_path_Communications_archive() {
        // sms.routes.ts:403 — PATCH /conversations/:phone/archive
        XCTAssertEqual(Endpoints.Communications.archive(phone: "+15551234567").path,
                       "/api/v1/sms/conversations/+15551234567/archive")
    }

    func test_path_Communications_templates() {
        // sms.routes.ts:850 — GET /templates
        XCTAssertEqual(Endpoints.Communications.templates().path, "/api/v1/sms/templates")
    }

    func test_path_Communications_createTemplate() {
        // sms.routes.ts:861 — POST /templates
        XCTAssertEqual(Endpoints.Communications.createTemplate().path, "/api/v1/sms/templates")
    }

    func test_path_Communications_updateTemplate() {
        // sms.routes.ts:871 — PUT /templates/:id
        XCTAssertEqual(Endpoints.Communications.updateTemplate(id: 1).path, "/api/v1/sms/templates/1")
    }

    func test_path_Communications_deleteTemplate() {
        // sms.routes.ts:885 — DELETE /templates/:id
        XCTAssertEqual(Endpoints.Communications.deleteTemplate(id: 1).path, "/api/v1/sms/templates/1")
    }

    // MARK: - POS
    // Mount: app.use('/api/v1/pos', ...) — index.ts:1547
    // Routes: pos.routes.ts

    func test_path_Pos_products() {
        // pos.routes.ts:102 — GET /products
        XCTAssertEqual(Endpoints.Pos.products().path, "/api/v1/pos/products")
    }

    func test_path_Pos_register() {
        // pos.routes.ts:172 — GET /register
        XCTAssertEqual(Endpoints.Pos.register().path, "/api/v1/pos/register")
    }

    func test_path_Pos_transaction() {
        // pos.routes.ts:252 — POST /transaction
        XCTAssertEqual(Endpoints.Pos.transaction().path, "/api/v1/pos/transaction")
    }

    func test_path_Pos_transactions() {
        // pos.routes.ts:878 — GET /transactions
        XCTAssertEqual(Endpoints.Pos.transactions().path, "/api/v1/pos/transactions")
    }

    func test_path_Pos_cashIn() {
        // pos.routes.ts:203 — POST /cash-in
        XCTAssertEqual(Endpoints.Pos.cashIn().path, "/api/v1/pos/cash-in")
    }

    func test_path_Pos_cashOut() {
        // pos.routes.ts:219 — POST /cash-out
        XCTAssertEqual(Endpoints.Pos.cashOut().path, "/api/v1/pos/cash-out")
    }

    func test_path_Pos_checkoutWithTicket() {
        // pos.routes.ts:920 — POST /checkout-with-ticket
        XCTAssertEqual(Endpoints.Pos.checkoutWithTicket().path, "/api/v1/pos/checkout-with-ticket")
    }

    func test_path_Pos_processReturn() {
        // pos.routes.ts:2032 — POST /return
        XCTAssertEqual(Endpoints.Pos.processReturn().path, "/api/v1/pos/return")
    }

    func test_path_Pos_openDrawer() {
        // pos.routes.ts:2178 — POST /open-drawer
        XCTAssertEqual(Endpoints.Pos.openDrawer().path, "/api/v1/pos/open-drawer")
    }

    func test_path_Pos_workstations() {
        // pos.routes.ts:2229 — GET /workstations
        XCTAssertEqual(Endpoints.Pos.workstations().path, "/api/v1/pos/workstations")
    }

    // MARK: - Notifications
    // Mount: app.use('/api/v1/notifications', ...) — index.ts:1573
    // Routes: notifications.routes.ts

    func test_path_Notifications_list() {
        // notifications.routes.ts:40 — GET /
        XCTAssertEqual(Endpoints.Notifications.list().path, "/api/v1/notifications")
    }

    func test_path_Notifications_unreadCount() {
        // notifications.routes.ts:77 — GET /unread-count
        XCTAssertEqual(Endpoints.Notifications.unreadCount().path, "/api/v1/notifications/unread-count")
    }

    func test_path_Notifications_markRead() {
        // notifications.routes.ts:95 — PATCH /:id/read
        XCTAssertEqual(Endpoints.Notifications.markRead(id: 10).path, "/api/v1/notifications/10/read")
    }

    func test_path_Notifications_markAllRead() {
        // notifications.routes.ts:120 — POST /mark-all-read
        XCTAssertEqual(Endpoints.Notifications.markAllRead().path, "/api/v1/notifications/mark-all-read")
    }

    func test_path_Notifications_focusPolicies() {
        // notifications.routes.ts:143 — GET /focus-policies
        XCTAssertEqual(Endpoints.Notifications.focusPolicies().path, "/api/v1/notifications/focus-policies")
    }

    func test_path_Notifications_updateFocusPolicies() {
        // notifications.routes.ts:167 — PUT /focus-policies
        XCTAssertEqual(Endpoints.Notifications.updateFocusPolicies().path, "/api/v1/notifications/focus-policies")
    }

    func test_path_Notifications_sendReceipt() {
        // notifications.routes.ts:198 — POST /send-receipt
        XCTAssertEqual(Endpoints.Notifications.sendReceipt().path, "/api/v1/notifications/send-receipt")
    }

    // MARK: - Search
    // Mount: app.use('/api/v1/search', ...) — index.ts:1577
    // Routes: search.routes.ts

    func test_path_Search_global() {
        // search.routes.ts:34 — GET /
        XCTAssertEqual(Endpoints.Search.global(query: "macbook").path, "/api/v1/search")
    }

    func test_path_Search_globalQueryItem() {
        let ep = Endpoints.Search.global(query: "screen")
        XCTAssertEqual(ep.queryItems?.first?.name, "q")
        XCTAssertEqual(ep.queryItems?.first?.value, "screen")
    }

    // MARK: - Roles
    // Mount: app.use('/api/v1/roles', ...) — index.ts:1691
    // Routes: roles.routes.ts

    func test_path_Roles_list() {
        // roles.routes.ts:115 — GET /
        XCTAssertEqual(Endpoints.Roles.list().path, "/api/v1/roles")
    }

    func test_path_Roles_permissionKeys() {
        // roles.routes.ts:129 — GET /permission-keys
        XCTAssertEqual(Endpoints.Roles.permissionKeys().path, "/api/v1/roles/permission-keys")
    }

    func test_path_Roles_create() {
        // roles.routes.ts:136 — POST /
        XCTAssertEqual(Endpoints.Roles.create().path, "/api/v1/roles")
    }

    func test_path_Roles_update() {
        // roles.routes.ts:164 — PUT /:id
        XCTAssertEqual(Endpoints.Roles.update(id: 2).path, "/api/v1/roles/2")
    }

    func test_path_Roles_delete() {
        // roles.routes.ts:198 — DELETE /:id
        XCTAssertEqual(Endpoints.Roles.delete(id: 2).path, "/api/v1/roles/2")
    }

    func test_path_Roles_permissions() {
        // roles.routes.ts:220 — GET /:id/permissions
        XCTAssertEqual(Endpoints.Roles.permissions(id: 2).path, "/api/v1/roles/2/permissions")
    }

    func test_path_Roles_updatePermissions() {
        // roles.routes.ts:241 — PUT /:id/permissions
        XCTAssertEqual(Endpoints.Roles.updatePermissions(id: 2).path, "/api/v1/roles/2/permissions")
    }

    func test_path_Roles_userRole() {
        // roles.routes.ts:329 — GET /users/:userId/role
        XCTAssertEqual(Endpoints.Roles.userRole(userId: 5).path, "/api/v1/roles/users/5/role")
    }

    func test_path_Roles_assignUserRole() {
        // roles.routes.ts:282 — PUT /users/:userId/role
        XCTAssertEqual(Endpoints.Roles.assignUserRole(userId: 5).path, "/api/v1/roles/users/5/role")
    }

    // MARK: - AuditLogs
    // Mount: app.use('/api/v1/activity', ...) — index.ts:1603
    // Routes: activity.routes.ts
    // Confirmed via APIClient+AuditLogs.swift: uses path "/activity"

    func test_path_AuditLogs_list() {
        XCTAssertEqual(Endpoints.AuditLogs.list().path, "/api/v1/activity")
    }

    func test_path_AuditLogs_listWithFilters() {
        let ep = Endpoints.AuditLogs.list(actorUserId: 3, entityKind: "ticket", cursor: 100, limit: 25)
        XCTAssertEqual(ep.path, "/api/v1/activity")
        let items = ep.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["actor_user_id"], "3")
        XCTAssertEqual(dict["entity_kind"], "ticket")
        XCTAssertEqual(dict["cursor"], "100")
        XCTAssertEqual(dict["limit"], "25")
    }

    // MARK: - RepairPricing
    // Mount: app.use('/api/v1/repair-pricing', ...) — index.ts:1580
    // Routes: repairPricing.routes.ts

    func test_path_RepairPricing_services() {
        // repairPricing.routes.ts:72 — GET /services
        XCTAssertEqual(Endpoints.RepairPricing.services().path, "/api/v1/repair-pricing/services")
    }

    func test_path_RepairPricing_createService() {
        // repairPricing.routes.ts:87 — POST /services
        XCTAssertEqual(Endpoints.RepairPricing.createService().path, "/api/v1/repair-pricing/services")
    }

    func test_path_RepairPricing_updateService() {
        // repairPricing.routes.ts:106 — PUT /services/:id
        XCTAssertEqual(Endpoints.RepairPricing.updateService(id: 1).path, "/api/v1/repair-pricing/services/1")
    }

    func test_path_RepairPricing_deleteService() {
        // repairPricing.routes.ts:133 — DELETE /services/:id
        XCTAssertEqual(Endpoints.RepairPricing.deleteService(id: 1).path, "/api/v1/repair-pricing/services/1")
    }

    func test_path_RepairPricing_prices() {
        // repairPricing.routes.ts:146 — GET /prices
        XCTAssertEqual(Endpoints.RepairPricing.prices().path, "/api/v1/repair-pricing/prices")
    }

    func test_path_RepairPricing_createPrice() {
        // repairPricing.routes.ts:182 — POST /prices
        XCTAssertEqual(Endpoints.RepairPricing.createPrice().path, "/api/v1/repair-pricing/prices")
    }

    func test_path_RepairPricing_updatePrice() {
        // repairPricing.routes.ts:235 — PUT /prices/:id
        XCTAssertEqual(Endpoints.RepairPricing.updatePrice(id: 5).path, "/api/v1/repair-pricing/prices/5")
    }

    func test_path_RepairPricing_deletePrice() {
        // repairPricing.routes.ts:256 — DELETE /prices/:id
        XCTAssertEqual(Endpoints.RepairPricing.deletePrice(id: 5).path, "/api/v1/repair-pricing/prices/5")
    }

    func test_path_RepairPricing_lookup() {
        // repairPricing.routes.ts:270 — GET /lookup
        XCTAssertEqual(Endpoints.RepairPricing.lookup().path, "/api/v1/repair-pricing/lookup")
    }

    func test_path_RepairPricing_tiers() {
        XCTAssertEqual(Endpoints.RepairPricing.tiers().path, "/api/v1/repair-pricing/tiers")
    }

    func test_path_RepairPricing_updateTiers() {
        XCTAssertEqual(Endpoints.RepairPricing.updateTiers().path, "/api/v1/repair-pricing/tiers")
    }

    func test_path_RepairPricing_matrixWithFilters() {
        let ep = Endpoints.RepairPricing.matrix(category: "phone", manufacturerId: 1, repairServiceId: 2, query: "iphone", limit: 25)
        XCTAssertEqual(ep.path, "/api/v1/repair-pricing/matrix")
        let items = ep.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["category"], "phone")
        XCTAssertEqual(dict["manufacturer_id"], "1")
        XCTAssertEqual(dict["repair_service_id"], "2")
        XCTAssertEqual(dict["q"], "iphone")
        XCTAssertEqual(dict["limit"], "25")
    }

    func test_path_RepairPricing_seedDefaults() {
        XCTAssertEqual(Endpoints.RepairPricing.seedDefaults().path, "/api/v1/repair-pricing/seed-defaults")
    }

    func test_path_RepairPricing_tierApply() {
        XCTAssertEqual(Endpoints.RepairPricing.tierApply().path, "/api/v1/repair-pricing/tier-apply")
    }

    func test_path_RepairPricing_auditWithFilters() {
        let ep = Endpoints.RepairPricing.audit(repairPriceId: 8, limit: 50)
        XCTAssertEqual(ep.path, "/api/v1/repair-pricing/audit")
        let items = ep.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["repair_price_id"], "8")
        XCTAssertEqual(dict["limit"], "50")
    }

    func test_path_RepairPricing_revert() {
        XCTAssertEqual(Endpoints.RepairPricing.revert(priceId: 8).path, "/api/v1/repair-pricing/revert/8")
    }

    func test_path_RepairPricing_autoMarginSettings() {
        XCTAssertEqual(Endpoints.RepairPricing.autoMarginSettings().path, "/api/v1/repair-pricing/auto-margin-settings")
    }

    func test_path_RepairPricing_updateAutoMarginSettings() {
        XCTAssertEqual(Endpoints.RepairPricing.updateAutoMarginSettings().path, "/api/v1/repair-pricing/auto-margin-settings")
    }

    func test_path_RepairPricing_autoMarginPreview() {
        XCTAssertEqual(Endpoints.RepairPricing.autoMarginPreview().path, "/api/v1/repair-pricing/auto-margin-preview")
    }

    func test_path_RepairPricing_recomputeProfits() {
        XCTAssertEqual(Endpoints.RepairPricing.recomputeProfits().path, "/api/v1/repair-pricing/recompute-profits")
    }

    // MARK: - PurchaseOrders
    // Mount: sub-routes of /api/v1/inventory — inventory.routes.ts

    func test_path_PurchaseOrders_list() {
        // inventory.routes.ts:1320 — GET /purchase-orders/list
        XCTAssertEqual(Endpoints.PurchaseOrders.list().path, "/api/v1/inventory/purchase-orders/list")
    }

    func test_path_PurchaseOrders_create() {
        // inventory.routes.ts:1349 — POST /purchase-orders
        XCTAssertEqual(Endpoints.PurchaseOrders.create().path, "/api/v1/inventory/purchase-orders")
    }

    func test_path_PurchaseOrders_detail() {
        // inventory.routes.ts:1379 — GET /purchase-orders/:id
        XCTAssertEqual(Endpoints.PurchaseOrders.detail(id: 8).path, "/api/v1/inventory/purchase-orders/8")
    }

    func test_path_PurchaseOrders_update() {
        // Per APIClient+PurchaseOrders.swift confirmed: PUT /api/v1/inventory/purchase-orders/:id
        XCTAssertEqual(Endpoints.PurchaseOrders.update(id: 8).path, "/api/v1/inventory/purchase-orders/8")
    }

    // MARK: - GiftCards
    // Mount: app.use('/api/v1/gift-cards', ...) — index.ts:1586
    // Routes: giftCards.routes.ts

    func test_path_GiftCards_list() {
        // giftCards.routes.ts:104 — GET /
        XCTAssertEqual(Endpoints.GiftCards.list().path, "/api/v1/gift-cards")
    }

    func test_path_GiftCards_lookup() {
        // giftCards.routes.ts:172 — GET /lookup/:code
        XCTAssertEqual(Endpoints.GiftCards.lookup(code: "GC-2024").path, "/api/v1/gift-cards/lookup/GC-2024")
    }

    func test_path_GiftCards_issue() {
        // giftCards.routes.ts:253 — POST /
        XCTAssertEqual(Endpoints.GiftCards.issue().path, "/api/v1/gift-cards")
    }

    func test_path_GiftCards_detail() {
        // giftCards.routes.ts:416 — GET /:id
        XCTAssertEqual(Endpoints.GiftCards.detail(id: 3).path, "/api/v1/gift-cards/3")
    }

    func test_path_GiftCards_redeem() {
        // giftCards.routes.ts:303 — POST /:id/redeem
        XCTAssertEqual(Endpoints.GiftCards.redeem(id: 3).path, "/api/v1/gift-cards/3/redeem")
    }

    func test_path_GiftCards_reload() {
        // giftCards.routes.ts:371 — POST /:id/reload
        XCTAssertEqual(Endpoints.GiftCards.reload(id: 3).path, "/api/v1/gift-cards/3/reload")
    }

    // MARK: - PaymentLinks
    // Mount: app.use('/api/v1/payment-links', ...) — index.ts:1670
    // Routes: paymentLinks.routes.ts (authedRouter)

    func test_path_PaymentLinks_list() {
        // paymentLinks.routes.ts:83 — GET /
        XCTAssertEqual(Endpoints.PaymentLinks.list().path, "/api/v1/payment-links")
    }

    func test_path_PaymentLinks_detail() {
        // paymentLinks.routes.ts:106 — GET /:id
        XCTAssertEqual(Endpoints.PaymentLinks.detail(id: 7).path, "/api/v1/payment-links/7")
    }

    func test_path_PaymentLinks_create() {
        // paymentLinks.routes.ts:116 — POST /
        XCTAssertEqual(Endpoints.PaymentLinks.create().path, "/api/v1/payment-links")
    }

    func test_path_PaymentLinks_cancel() {
        XCTAssertEqual(Endpoints.PaymentLinks.cancel(id: 7).path, "/api/v1/payment-links/7/cancel")
    }

    // MARK: - Voice
    // Mount: app.use('/api/v1/voice', ...) — index.ts:1589
    // Routes: voice.routes.ts

    func test_path_Voice_call() {
        // voice.routes.ts:76 — POST /call
        XCTAssertEqual(Endpoints.Voice.call().path, "/api/v1/voice/call")
    }

    func test_path_Voice_calls() {
        // voice.routes.ts:178 — GET /calls
        XCTAssertEqual(Endpoints.Voice.calls().path, "/api/v1/voice/calls")
    }

    func test_path_Voice_callDetail() {
        // voice.routes.ts:228 — GET /calls/:id
        XCTAssertEqual(Endpoints.Voice.callDetail(id: "CXXX").path, "/api/v1/voice/calls/CXXX")
    }

    func test_path_Voice_recording() {
        // voice.routes.ts:251 — GET /calls/:id/recording
        XCTAssertEqual(Endpoints.Voice.recording(callId: "CXXX").path, "/api/v1/voice/calls/CXXX/recording")
    }

    func test_path_Voice_hangup() {
        // voice.routes.ts:299 — POST /call/:id/hangup
        XCTAssertEqual(Endpoints.Voice.hangup(callId: "CXXX").path, "/api/v1/voice/call/CXXX/hangup")
    }

    // MARK: - HTTP Method checks (verify method field, not just path)

    func test_method_Tickets_list_isGet() {
        XCTAssertEqual(Endpoints.Tickets.list().method, .get)
    }

    func test_method_Tickets_create_isPost() {
        XCTAssertEqual(Endpoints.Tickets.create().method, .post)
    }

    func test_method_Tickets_update_isPut() {
        XCTAssertEqual(Endpoints.Tickets.update(id: 1).method, .put)
    }

    func test_method_Tickets_delete_isDelete() {
        XCTAssertEqual(Endpoints.Tickets.delete(id: 1).method, .delete)
    }

    func test_method_Tickets_updateStatus_isPatch() {
        XCTAssertEqual(Endpoints.Tickets.updateStatus(id: 1).method, .patch)
    }

    func test_method_Notifications_markRead_isPatch() {
        XCTAssertEqual(Endpoints.Notifications.markRead(id: 1).method, .patch)
    }

    func test_method_Notifications_updateFocusPolicies_isPut() {
        XCTAssertEqual(Endpoints.Notifications.updateFocusPolicies().method, .put)
    }

    func test_method_Communications_archive_isPatch() {
        XCTAssertEqual(Endpoints.Communications.archive(phone: "+1").method, .patch)
    }

    // MARK: - URLRequest integration

    func test_build_includesQueryItems_inURL() throws {
        let base = URL(string: "https://demo.bizarrecrm.com")!
        let ep = Endpoints.Search.global(query: "repair")
        let request = try ep.build(baseURL: base)
        let urlStr = request.url?.absoluteString ?? ""
        XCTAssertTrue(urlStr.contains("q=repair"), "Expected q=repair in URL: \(urlStr)")
    }

    func test_build_setsHTTPMethod() throws {
        let base = URL(string: "https://demo.bizarrecrm.com")!
        let ep = Endpoints.Invoices.void(invoiceId: 10)
        let request = try ep.build(baseURL: base)
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func test_build_nilQueryItems_noQueryString() throws {
        let base = URL(string: "https://demo.bizarrecrm.com")!
        let ep = Endpoints.Roles.list()
        let request = try ep.build(baseURL: base)
        XCTAssertNil(request.url?.query)
    }
}
