import Foundation

// MARK: - Endpoints namespace

/// Top-level namespace for all typed endpoint factories.
///
/// Each nested enum corresponds to a server route file mounted under `/api/v1/`.
/// Routes are cross-referenced against `packages/server/src/routes/` and the
/// `app.use(...)` mounts in `packages/server/src/index.ts`.
///
/// **Usage** — build a `URLRequest`:
/// ```swift
/// let request = try Endpoints.Tickets.list().build(baseURL: serverURL)
/// ```
///
/// These factories are **additive documentation** — existing `APIClient+*.swift`
/// extensions continue to work unchanged. This namespace lets new features adopt
/// typed paths without a flag-day migration.
public enum Endpoints {

    // MARK: - Tickets
    // Server: /api/v1/tickets  (tickets.routes.ts)

    public enum Tickets {
        /// `GET /api/v1/tickets` — paginated ticket list.
        public static func list(
            statusGroup: String? = nil,
            assignedTo: String? = nil,
            keyword: String? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/tickets",
                method: .get,
                queryItems: compactItems([
                    ("status_group", statusGroup),
                    ("assigned_to", assignedTo),
                    ("keyword", keyword),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/tickets` — create ticket.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets", method: .post)
        }

        /// `GET /api/v1/tickets/:id` — ticket detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(id)", method: .get)
        }

        /// `PUT /api/v1/tickets/:id` — full ticket update.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(id)", method: .put)
        }

        /// `DELETE /api/v1/tickets/:id` — soft-delete ticket.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(id)", method: .delete)
        }

        /// `PATCH /api/v1/tickets/:id/status` — change status.
        public static func updateStatus(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(id)/status", method: .patch)
        }

        /// `POST /api/v1/tickets/:id/notes` — add note.
        public static func addNote(ticketId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(ticketId)/notes", method: .post)
        }

        /// `PUT /api/v1/tickets/notes/:noteId` — edit note.
        public static func updateNote(noteId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/notes/\(noteId)", method: .put)
        }

        /// `DELETE /api/v1/tickets/notes/:noteId` — delete note.
        public static func deleteNote(noteId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/notes/\(noteId)", method: .delete)
        }

        /// `POST /api/v1/tickets/:id/devices` — add device.
        public static func addDevice(ticketId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(ticketId)/devices", method: .post)
        }

        /// `PUT /api/v1/tickets/devices/:deviceId` — update device.
        public static func updateDevice(deviceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/devices/\(deviceId)", method: .put)
        }

        /// `DELETE /api/v1/tickets/devices/:deviceId` — delete device.
        public static func deleteDevice(deviceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/devices/\(deviceId)", method: .delete)
        }

        /// `POST /api/v1/tickets/devices/:deviceId/parts` — add part.
        public static func addPart(deviceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/devices/\(deviceId)/parts", method: .post)
        }

        /// `DELETE /api/v1/tickets/devices/parts/:partId` — delete part.
        public static func deletePart(partId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/devices/parts/\(partId)", method: .delete)
        }

        /// `PUT /api/v1/tickets/devices/:deviceId/checklist` — update checklist.
        public static func updateChecklist(deviceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/devices/\(deviceId)/checklist", method: .put)
        }

        /// `POST /api/v1/tickets/:id/convert-to-invoice`.
        public static func convertToInvoice(ticketId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(ticketId)/convert-to-invoice", method: .post)
        }

        /// `GET /api/v1/tickets/kanban` — kanban board view.
        public static func kanban() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/kanban", method: .get)
        }

        /// `GET /api/v1/tickets/:id/history` — ticket history.
        public static func history(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/tickets/\(id)/history", method: .get)
        }
    }

    // MARK: - Customers
    // Server: /api/v1/customers  (customers.routes.ts)

    public enum Customers {
        /// `GET /api/v1/customers` — paginated customer list.
        public static func list(
            keyword: String? = nil,
            groupId: Int64? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/customers",
                method: .get,
                queryItems: compactItems([
                    ("keyword", keyword),
                    ("group_id", groupId.map(String.init)),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/customers` — create customer.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/customers", method: .post)
        }

        /// `GET /api/v1/customers/:id` — customer detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/customers/\(id)", method: .get)
        }

        /// `PUT /api/v1/customers/:id` — update customer.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/customers/\(id)", method: .put)
        }

        /// `DELETE /api/v1/customers/:id` — soft-delete customer.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/customers/\(id)", method: .delete)
        }
    }

    // MARK: - Invoices
    // Server: /api/v1/invoices  (invoices.routes.ts)

    public enum Invoices {
        /// `GET /api/v1/invoices` — paginated invoice list.
        public static func list(
            keyword: String? = nil,
            status: String? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/invoices",
                method: .get,
                queryItems: compactItems([
                    ("keyword", keyword),
                    ("status", status),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/invoices` — create invoice.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices", method: .post)
        }

        /// `GET /api/v1/invoices/:id` — invoice detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/\(id)", method: .get)
        }

        /// `PUT /api/v1/invoices/:id` — update invoice.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/\(id)", method: .put)
        }

        /// `GET /api/v1/invoices/stats` — invoice statistics.
        public static func stats() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/stats", method: .get)
        }

        /// `POST /api/v1/invoices/:id/payments` — record payment.
        public static func recordPayment(invoiceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/\(invoiceId)/payments", method: .post)
        }

        /// `POST /api/v1/invoices/:id/void` — void invoice.
        public static func void(invoiceId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/\(invoiceId)/void", method: .post)
        }

        /// `POST /api/v1/invoices/bulk-action` — bulk action on invoices.
        public static func bulkAction() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/invoices/bulk-action", method: .post)
        }
    }

    // MARK: - Inventory
    // Server: /api/v1/inventory  (inventory.routes.ts)

    public enum Inventory {
        /// `GET /api/v1/inventory` — paginated inventory list.
        public static func list(
            keyword: String? = nil,
            categoryId: Int64? = nil,
            lowStock: Bool? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/inventory",
                method: .get,
                queryItems: compactItems([
                    ("keyword", keyword),
                    ("category_id", categoryId.map(String.init)),
                    ("low_stock", lowStock.map { $0 ? "1" : "0" }),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/inventory` — create inventory item.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory", method: .post)
        }

        /// `GET /api/v1/inventory/:id` — inventory item detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/\(id)", method: .get)
        }

        /// `PUT /api/v1/inventory/:id` — update inventory item.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/\(id)", method: .put)
        }

        /// `GET /api/v1/inventory/low-stock` — low-stock items.
        public static func lowStock() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/low-stock", method: .get)
        }

        /// `GET /api/v1/inventory/categories` — inventory categories.
        public static func categories() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/categories", method: .get)
        }

        /// `GET /api/v1/inventory/barcode/:code` — lookup by barcode.
        public static func barcodeDetail(code: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/barcode/\(code)", method: .get)
        }

        /// `GET /api/v1/inventory/purchase-orders/list` — list purchase orders.
        public static func purchaseOrderList() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/list", method: .get)
        }

        /// `POST /api/v1/inventory/purchase-orders` — create purchase order.
        public static func createPurchaseOrder() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders", method: .post)
        }

        /// `GET /api/v1/inventory/purchase-orders/:id` — purchase order detail.
        public static func purchaseOrderDetail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/\(id)", method: .get)
        }

        /// `PUT /api/v1/inventory/purchase-orders/:id` — update purchase order.
        public static func updatePurchaseOrder(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/\(id)", method: .put)
        }
    }

    // MARK: - Estimates
    // Server: /api/v1/estimates  (estimates.routes.ts)

    public enum Estimates {
        /// `GET /api/v1/estimates` — paginated estimates list.
        public static func list(
            status: String? = nil,
            keyword: String? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/estimates",
                method: .get,
                queryItems: compactItems([
                    ("status", status),
                    ("keyword", keyword),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/estimates` — create estimate.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/estimates", method: .post)
        }

        /// `GET /api/v1/estimates/:id` — estimate detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/estimates/\(id)", method: .get)
        }

        /// `PUT /api/v1/estimates/:id` — update estimate.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/estimates/\(id)", method: .put)
        }

        /// `DELETE /api/v1/estimates/:id` — delete estimate.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/estimates/\(id)", method: .delete)
        }

        /// `POST /api/v1/estimates/:id/convert` — convert to invoice/ticket.
        public static func convert(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/estimates/\(id)/convert", method: .post)
        }
    }

    // MARK: - Leads
    // Server: /api/v1/leads  (leads.routes.ts)

    public enum Leads {
        /// `GET /api/v1/leads` — paginated leads list.
        public static func list(
            status: String? = nil,
            keyword: String? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/leads",
                method: .get,
                queryItems: compactItems([
                    ("status", status),
                    ("keyword", keyword),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `GET /api/v1/leads/pipeline` — kanban pipeline view.
        public static func pipeline() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/pipeline", method: .get)
        }

        /// `POST /api/v1/leads` — create lead.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads", method: .post)
        }

        /// `GET /api/v1/leads/:id` — lead detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/\(id)", method: .get)
        }

        /// `PUT /api/v1/leads/:id` — update lead.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/\(id)", method: .put)
        }

        /// `DELETE /api/v1/leads/:id` — delete lead.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/\(id)", method: .delete)
        }
    }

    // MARK: - Appointments
    // Server: /api/v1/leads/appointments  (leads.routes.ts, sub-routes)

    public enum Appointments {
        /// `GET /api/v1/leads/appointments` — list appointments.
        public static func list(
            fromDate: String? = nil,
            toDate: String? = nil,
            assignedTo: Int64? = nil,
            status: String? = nil,
            pageSize: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/leads/appointments",
                method: .get,
                queryItems: compactItems([
                    ("from_date", fromDate),
                    ("to_date", toDate),
                    ("assigned_to", assignedTo.map(String.init)),
                    ("status", status),
                    ("pagesize", pageSize.map(String.init))
                ])
            )
        }

        /// `POST /api/v1/leads/appointments` — create appointment.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/appointments", method: .post)
        }

        /// `PUT /api/v1/leads/appointments/:id` — update appointment.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/appointments/\(id)", method: .put)
        }

        /// `DELETE /api/v1/leads/appointments/:id` — delete appointment.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/leads/appointments/\(id)", method: .delete)
        }
    }

    // MARK: - Expenses
    // Server: /api/v1/expenses  (expenses.routes.ts)

    public enum Expenses {
        /// `GET /api/v1/expenses` — list expenses.
        public static func list(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/expenses",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `POST /api/v1/expenses` — create expense.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses", method: .post)
        }

        /// `GET /api/v1/expenses/:id` — expense detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses/\(id)", method: .get)
        }

        /// `PUT /api/v1/expenses/:id` — update expense.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses/\(id)", method: .put)
        }

        /// `DELETE /api/v1/expenses/:id` — delete expense.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses/\(id)", method: .delete)
        }

        /// `POST /api/v1/expenses/:id/approve` — approve expense.
        public static func approve(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses/\(id)/approve", method: .post)
        }

        /// `POST /api/v1/expenses/:id/deny` — deny expense.
        public static func deny(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/expenses/\(id)/deny", method: .post)
        }
    }

    // MARK: - Employees
    // Server: /api/v1/employees  (employees.routes.ts)

    public enum Employees {
        /// `GET /api/v1/employees` — list active employees.
        public static func list() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees", method: .get)
        }

        /// `GET /api/v1/employees/performance/all` — all employee performance.
        public static func performanceAll() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees/performance/all", method: .get)
        }

        /// `GET /api/v1/employees/:id` — employee detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees/\(id)", method: .get)
        }

        /// `POST /api/v1/employees` — create employee.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees", method: .post)
        }

        /// `POST /api/v1/employees/:id/clock-in` — clock employee in.
        public static func clockIn(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees/\(id)/clock-in", method: .post)
        }

        /// `POST /api/v1/employees/:id/clock-out` — clock employee out.
        public static func clockOut(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees/\(id)/clock-out", method: .post)
        }

        /// `GET /api/v1/employees/:id/hours` — employee clock hours log.
        public static func hours(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/employees/\(id)/hours", method: .get)
        }
    }

    // MARK: - Reports
    // Server: /api/v1/reports  (reports.routes.ts)

    public enum Reports {
        /// `GET /api/v1/reports/dashboard` — dashboard summary.
        public static func dashboard() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/dashboard", method: .get)
        }

        /// `GET /api/v1/reports/dashboard-kpis` — KPI metrics.
        public static func dashboardKPIs() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/dashboard-kpis", method: .get)
        }

        /// `GET /api/v1/reports/sales` — sales report.
        public static func sales() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/sales", method: .get)
        }

        /// `GET /api/v1/reports/tickets` — tickets report.
        public static func tickets() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/tickets", method: .get)
        }

        /// `GET /api/v1/reports/inventory` — inventory report.
        public static func inventory() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/inventory", method: .get)
        }

        /// `GET /api/v1/reports/employees` — employee performance report.
        public static func employees() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/employees", method: .get)
        }

        /// `GET /api/v1/reports/tax` — tax report.
        public static func tax() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/tax", method: .get)
        }

        /// `GET /api/v1/reports/insights` — AI/trend insights.
        public static func insights() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/insights", method: .get)
        }

        /// `GET /api/v1/reports/parts-usage` — parts usage report.
        public static func partsUsage() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/reports/parts-usage", method: .get)
        }
    }

    // MARK: - Communications (SMS)
    // Server: /api/v1/sms  (sms.routes.ts)

    public enum Communications {
        /// `GET /api/v1/sms/conversations` — list SMS conversations.
        public static func conversations(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/sms/conversations",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `GET /api/v1/sms/conversations/:phone` — conversation thread.
        public static func conversation(phone: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/conversations/\(phone)", method: .get)
        }

        /// `POST /api/v1/sms/send` — send SMS message.
        public static func send() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/send", method: .post)
        }

        /// `GET /api/v1/sms/unread-count` — unread count.
        public static func unreadCount() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/unread-count", method: .get)
        }

        /// `PATCH /api/v1/sms/conversations/:phone/read` — mark conversation read.
        public static func markRead(phone: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/conversations/\(phone)/read", method: .patch)
        }

        /// `PATCH /api/v1/sms/conversations/:phone/archive` — archive conversation.
        public static func archive(phone: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/conversations/\(phone)/archive", method: .patch)
        }

        /// `PATCH /api/v1/sms/conversations/:phone/flag` — flag conversation.
        public static func flag(phone: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/conversations/\(phone)/flag", method: .patch)
        }

        /// `PATCH /api/v1/sms/conversations/:phone/pin` — pin conversation.
        public static func pin(phone: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/conversations/\(phone)/pin", method: .patch)
        }

        /// `GET /api/v1/sms/templates` — list message templates.
        public static func templates() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/templates", method: .get)
        }

        /// `POST /api/v1/sms/templates` — create message template.
        public static func createTemplate() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/templates", method: .post)
        }

        /// `PUT /api/v1/sms/templates/:id` — update message template.
        public static func updateTemplate(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/templates/\(id)", method: .put)
        }

        /// `DELETE /api/v1/sms/templates/:id` — delete message template.
        public static func deleteTemplate(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/templates/\(id)", method: .delete)
        }

        /// `POST /api/v1/sms/upload-media` — upload MMS media.
        public static func uploadMedia() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/sms/upload-media", method: .post)
        }
    }

    // MARK: - POS
    // Server: /api/v1/pos  (pos.routes.ts)

    public enum Pos {
        /// `GET /api/v1/pos/products` — list POS products.
        public static func products(keyword: String? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/pos/products",
                method: .get,
                queryItems: compactItems([("keyword", keyword)])
            )
        }

        /// `GET /api/v1/pos/register` — register state.
        public static func register() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/register", method: .get)
        }

        /// `POST /api/v1/pos/transaction` — complete POS transaction.
        public static func transaction() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/transaction", method: .post)
        }

        /// `GET /api/v1/pos/transactions` — transaction history.
        public static func transactions(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/pos/transactions",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `POST /api/v1/pos/cash-in` — cash in.
        public static func cashIn() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/cash-in", method: .post)
        }

        /// `POST /api/v1/pos/cash-out` — cash out.
        public static func cashOut() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/cash-out", method: .post)
        }

        /// `POST /api/v1/pos/checkout-with-ticket` — checkout linked to a ticket.
        public static func checkoutWithTicket() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/checkout-with-ticket", method: .post)
        }

        /// `POST /api/v1/pos/return` — process return.
        public static func processReturn() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/return", method: .post)
        }

        /// `POST /api/v1/pos/open-drawer` — open cash drawer.
        public static func openDrawer() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/open-drawer", method: .post)
        }

        /// `GET /api/v1/pos/workstations` — list workstations.
        public static func workstations() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/workstations", method: .get)
        }

        /// `POST /api/v1/pos/workstations` — create workstation.
        public static func createWorkstation() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/pos/workstations", method: .post)
        }
    }

    // MARK: - Notifications
    // Server: /api/v1/notifications  (notifications.routes.ts)

    public enum Notifications {
        /// `GET /api/v1/notifications` — list notifications.
        public static func list(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/notifications",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `GET /api/v1/notifications/unread-count` — unread notification count.
        public static func unreadCount() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/unread-count", method: .get)
        }

        /// `PATCH /api/v1/notifications/:id/read` — mark single notification read.
        public static func markRead(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/\(id)/read", method: .patch)
        }

        /// `POST /api/v1/notifications/mark-all-read` — mark all read.
        public static func markAllRead() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/mark-all-read", method: .post)
        }

        /// `GET /api/v1/notifications/focus-policies` — focus filter policies.
        public static func focusPolicies() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/focus-policies", method: .get)
        }

        /// `PUT /api/v1/notifications/focus-policies` — update focus filter policies.
        public static func updateFocusPolicies() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/focus-policies", method: .put)
        }

        /// `POST /api/v1/notifications/send-receipt` — email a receipt.
        public static func sendReceipt() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/notifications/send-receipt", method: .post)
        }
    }

    // MARK: - Search
    // Server: /api/v1/search  (search.routes.ts)

    public enum Search {
        /// `GET /api/v1/search` — global search.
        public static func global(query: String) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/search",
                method: .get,
                queryItems: [URLQueryItem(name: "q", value: query)]
            )
        }
    }

    // MARK: - Roles
    // Server: /api/v1/roles  (roles.routes.ts)

    public enum Roles {
        /// `GET /api/v1/roles` — list roles.
        public static func list() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles", method: .get)
        }

        /// `GET /api/v1/roles/permission-keys` — all available permission keys.
        public static func permissionKeys() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/permission-keys", method: .get)
        }

        /// `POST /api/v1/roles` — create role.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles", method: .post)
        }

        /// `PUT /api/v1/roles/:id` — update role metadata.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/\(id)", method: .put)
        }

        /// `DELETE /api/v1/roles/:id` — delete role.
        public static func delete(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/\(id)", method: .delete)
        }

        /// `GET /api/v1/roles/:id/permissions` — get permissions matrix for role.
        public static func permissions(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/\(id)/permissions", method: .get)
        }

        /// `PUT /api/v1/roles/:id/permissions` — set role permissions.
        public static func updatePermissions(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/\(id)/permissions", method: .put)
        }

        /// `GET /api/v1/roles/users/:userId/role` — get user's custom role.
        public static func userRole(userId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/users/\(userId)/role", method: .get)
        }

        /// `PUT /api/v1/roles/users/:userId/role` — assign custom role to user.
        public static func assignUserRole(userId: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/roles/users/\(userId)/role", method: .put)
        }
    }

    // MARK: - AuditLogs
    // Server: /api/v1/activity  (activity.routes.ts)

    public enum AuditLogs {
        /// `GET /api/v1/activity` — paginated activity/audit log.
        public static func list(
            actorUserId: Int? = nil,
            entityKind: String? = nil,
            cursor: Int? = nil,
            limit: Int? = nil
        ) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/activity",
                method: .get,
                queryItems: compactItems([
                    ("actor_user_id", actorUserId.map(String.init)),
                    ("entity_kind", entityKind),
                    ("cursor", cursor.map(String.init)),
                    ("limit", limit.map(String.init))
                ])
            )
        }
    }

    // MARK: - RepairPricing
    // Server: /api/v1/repair-pricing  (repairPricing.routes.ts)

    public enum RepairPricing {
        /// `GET /api/v1/repair-pricing/services` — list repair services.
        public static func services() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/services", method: .get)
        }

        /// `POST /api/v1/repair-pricing/services` — create service.
        public static func createService() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/services", method: .post)
        }

        /// `PUT /api/v1/repair-pricing/services/:id` — update service.
        public static func updateService(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/services/\(id)", method: .put)
        }

        /// `DELETE /api/v1/repair-pricing/services/:id` — delete service.
        public static func deleteService(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/services/\(id)", method: .delete)
        }

        /// `GET /api/v1/repair-pricing/prices` — list pricing records.
        public static func prices(deviceModelId: Int64? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/repair-pricing/prices",
                method: .get,
                queryItems: compactItems([("device_model_id", deviceModelId.map(String.init))])
            )
        }

        /// `POST /api/v1/repair-pricing/prices` — create price.
        public static func createPrice() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/prices", method: .post)
        }

        /// `PUT /api/v1/repair-pricing/prices/:id` — update price.
        public static func updatePrice(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/prices/\(id)", method: .put)
        }

        /// `DELETE /api/v1/repair-pricing/prices/:id` — delete price.
        public static func deletePrice(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/prices/\(id)", method: .delete)
        }

        /// `GET /api/v1/repair-pricing/lookup` — price lookup by device/service.
        public static func lookup() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/repair-pricing/lookup", method: .get)
        }
    }

    // MARK: - PurchaseOrders (alias via Inventory sub-routes)
    // Server: /api/v1/inventory/purchase-orders  (inventory.routes.ts)

    public enum PurchaseOrders {
        /// `GET /api/v1/inventory/purchase-orders/list` — list purchase orders.
        public static func list() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/list", method: .get)
        }

        /// `POST /api/v1/inventory/purchase-orders` — create purchase order.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders", method: .post)
        }

        /// `GET /api/v1/inventory/purchase-orders/:id` — purchase order detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/\(id)", method: .get)
        }

        /// `PUT /api/v1/inventory/purchase-orders/:id` — update purchase order.
        public static func update(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/inventory/purchase-orders/\(id)", method: .put)
        }
    }

    // MARK: - GiftCards
    // Server: /api/v1/gift-cards  (giftCards.routes.ts)

    public enum GiftCards {
        /// `GET /api/v1/gift-cards` — list gift cards.
        public static func list(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/gift-cards",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `GET /api/v1/gift-cards/lookup/:code` — lookup by code.
        public static func lookup(code: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/gift-cards/lookup/\(code)", method: .get)
        }

        /// `POST /api/v1/gift-cards` — issue gift card.
        public static func issue() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/gift-cards", method: .post)
        }

        /// `GET /api/v1/gift-cards/:id` — gift card detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/gift-cards/\(id)", method: .get)
        }

        /// `POST /api/v1/gift-cards/:id/redeem` — redeem gift card.
        public static func redeem(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/gift-cards/\(id)/redeem", method: .post)
        }

        /// `POST /api/v1/gift-cards/:id/reload` — reload gift card balance.
        public static func reload(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/gift-cards/\(id)/reload", method: .post)
        }
    }

    // MARK: - PaymentLinks
    // Server: /api/v1/payment-links  (paymentLinks.routes.ts)

    public enum PaymentLinks {
        /// `GET /api/v1/payment-links` — list payment links.
        public static func list(status: String? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/payment-links",
                method: .get,
                queryItems: compactItems([("status", status)])
            )
        }

        /// `GET /api/v1/payment-links/:id` — payment link detail.
        public static func detail(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/payment-links/\(id)", method: .get)
        }

        /// `POST /api/v1/payment-links` — create payment link.
        public static func create() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/payment-links", method: .post)
        }

        /// `POST /api/v1/payment-links/:id/cancel` — cancel payment link.
        public static func cancel(id: Int64) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/payment-links/\(id)/cancel", method: .post)
        }
    }

    // MARK: - Voice
    // Server: /api/v1/voice  (voice.routes.ts)

    public enum Voice {
        /// `POST /api/v1/voice/call` — initiate outbound call.
        public static func call() -> some Endpoint {
            TypedEndpoint(path: "/api/v1/voice/call", method: .post)
        }

        /// `GET /api/v1/voice/calls` — list calls.
        public static func calls(pageSize: Int? = nil) -> some Endpoint {
            TypedEndpoint(
                path: "/api/v1/voice/calls",
                method: .get,
                queryItems: compactItems([("pagesize", pageSize.map(String.init))])
            )
        }

        /// `GET /api/v1/voice/calls/:id` — call detail.
        public static func callDetail(id: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/voice/calls/\(id)", method: .get)
        }

        /// `GET /api/v1/voice/calls/:id/recording` — call recording URL.
        public static func recording(callId: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/voice/calls/\(callId)/recording", method: .get)
        }

        /// `POST /api/v1/voice/call/:id/hangup` — hang up in-progress call.
        public static func hangup(callId: String) -> some Endpoint {
            TypedEndpoint(path: "/api/v1/voice/call/\(callId)/hangup", method: .post)
        }
    }
}

// MARK: - Internal helpers

/// Builds a ``[URLQueryItem]`` from pairs, dropping any where the value is nil.
private func compactItems(_ pairs: [(String, String?)]) -> [URLQueryItem]? {
    let items = pairs.compactMap { name, value -> URLQueryItem? in
        guard let value else { return nil }
        return URLQueryItem(name: name, value: value)
    }
    return items.isEmpty ? nil : items
}

// MARK: - TypedEndpoint (concrete backing type)

/// Concrete value type backing the opaque `some Endpoint` return type of all factories.
/// Internal — callers use the protocol type.
struct TypedEndpoint: Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?

    init(path: String, method: HTTPMethod, queryItems: [URLQueryItem]? = nil) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
    }
}
