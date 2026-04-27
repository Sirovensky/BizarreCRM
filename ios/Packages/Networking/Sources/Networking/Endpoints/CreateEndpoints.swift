import Foundation

// MARK: - Customer create

public struct CreateCustomerRequest: Codable, Sendable {
    public let firstName: String
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let organization: String?
    public let address1: String?
    public let city: String?
    public let state: String?
    public let postcode: String?
    public let notes: String?

    public init(firstName: String, lastName: String? = nil, email: String? = nil,
                phone: String? = nil, mobile: String? = nil, organization: String? = nil,
                address1: String? = nil, city: String? = nil, state: String? = nil,
                postcode: String? = nil, notes: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.mobile = mobile
        self.organization = organization
        self.address1 = address1
        self.city = city
        self.state = state
        self.postcode = postcode
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, mobile, organization, address1, city, state, postcode
        case firstName = "first_name"
        case lastName = "last_name"
        case notes = "comments"
    }
}

/// Server returns the full row; we only consume `id` for navigation.
public struct CreatedResource: Decodable, Sendable {
    public let id: Int64

    public init(id: Int64) { self.id = id }
}

// MARK: - Customer update

/// `PUT /api/v1/customers/:id`. Server accepts the same fields as create —
/// missing keys are left untouched (dynamic SET clause). Match CreateCustomer
/// shape so one `CustomerFormView` can drive both flows.
public struct UpdateCustomerRequest: Codable, Sendable {
    public let firstName: String
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let organization: String?
    public let address1: String?
    public let city: String?
    public let state: String?
    public let postcode: String?
    public let notes: String?

    public init(firstName: String, lastName: String? = nil, email: String? = nil,
                phone: String? = nil, mobile: String? = nil, organization: String? = nil,
                address1: String? = nil, city: String? = nil, state: String? = nil,
                postcode: String? = nil, notes: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.mobile = mobile
        self.organization = organization
        self.address1 = address1
        self.city = city
        self.state = state
        self.postcode = postcode
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, mobile, organization, address1, city, state, postcode
        case firstName = "first_name"
        case lastName = "last_name"
        case notes = "comments"
    }
}

// MARK: - Appointment create

public struct CreateAppointmentRequest: Encodable, Sendable {
    public let title: String
    public let startTime: String       // ISO 8601 or "YYYY-MM-DD HH:MM:SS"
    public let endTime: String?
    public let customerId: Int64?
    public let leadId: Int64?
    public let notes: String?
    /// §10.3 idempotency key — server ignores duplicate submissions within 24h.
    public let idempotencyKey: String?
    /// §10.2 Reminder offsets in minutes before the appointment start.
    /// e.g. [15, 60, 1440] = 15 min, 1 hour, 1 day before.
    public let reminderOffsets: [Int]?

    public init(title: String, startTime: String, endTime: String? = nil,
                customerId: Int64? = nil, leadId: Int64? = nil, notes: String? = nil,
                idempotencyKey: String? = nil,
                reminderOffsets: [Int]? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.customerId = customerId
        self.leadId = leadId
        self.notes = notes
        self.idempotencyKey = idempotencyKey
        self.reminderOffsets = reminderOffsets
    }

    enum CodingKeys: String, CodingKey {
        case title, notes
        case startTime      = "start_time"
        case endTime        = "end_time"
        case customerId     = "customer_id"
        case leadId         = "lead_id"
        case idempotencyKey = "idempotency_key"
        case reminderOffsets = "reminder_offsets"
    }
}

// MARK: - Lead create

public struct CreateLeadRequest: Encodable, Sendable {
    public let firstName: String
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let source: String?
    public let notes: String?
    // §9.4 Extended fields
    public let company: String?
    public let title: String?
    public let estimatedValueCents: Int?
    public let stage: String?
    public let followUpAt: String?

    public init(
        firstName: String,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        source: String? = nil,
        notes: String? = nil,
        company: String? = nil,
        title: String? = nil,
        estimatedValueCents: Int? = nil,
        stage: String? = nil,
        followUpAt: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.source = source
        self.notes = notes
        self.company = company
        self.title = title
        self.estimatedValueCents = estimatedValueCents
        self.stage = stage
        self.followUpAt = followUpAt
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, source, notes, company, title, stage
        case firstName            = "first_name"
        case lastName             = "last_name"
        case estimatedValueCents  = "estimated_value_cents"
        case followUpAt           = "follow_up_at"
    }
}

// MARK: - Ticket update

/// `PUT /api/v1/tickets/:id`. Server route (tickets.routes.ts:1722) accepts
/// a narrow field set: `customer_id`, `assigned_to`, `discount`,
/// `discount_reason`, `source`, `referral_source`, `labels`, `due_on`,
/// `signature`, `is_layaway`, `layaway_expires`. Device-level edits go
/// through a separate `PUT /tickets/devices/:deviceId` endpoint — those
/// are NOT part of this DTO.
public struct UpdateTicketRequest: Codable, Sendable {
    public let customerId: Int64?
    public let assignedTo: Int64?
    public let discount: Double?
    public let discountReason: String?
    public let source: String?
    public let referralSource: String?
    public let dueOn: String?

    public init(
        customerId: Int64? = nil,
        assignedTo: Int64? = nil,
        discount: Double? = nil,
        discountReason: String? = nil,
        source: String? = nil,
        referralSource: String? = nil,
        dueOn: String? = nil
    ) {
        self.customerId = customerId
        self.assignedTo = assignedTo
        self.discount = discount
        self.discountReason = discountReason
        self.source = source
        self.referralSource = referralSource
        self.dueOn = dueOn
    }

    enum CodingKeys: String, CodingKey {
        case discount, source
        case customerId = "customer_id"
        case assignedTo = "assigned_to"
        case discountReason = "discount_reason"
        case referralSource = "referral_source"
        case dueOn = "due_on"
    }
}

// MARK: - Ticket create (simplified — single device, minimum required fields)

public struct CreateTicketRequest: Codable, Sendable {
    public let customerId: Int64
    public let devices: [NewDevice]
    public let statusId: Int64?
    public let assignedTo: Int64?

    public init(customerId: Int64, devices: [NewDevice],
                statusId: Int64? = nil, assignedTo: Int64? = nil) {
        self.customerId = customerId
        self.devices = devices
        self.statusId = statusId
        self.assignedTo = assignedTo
    }

    public struct NewDevice: Codable, Sendable {
        public let deviceName: String
        public let imei: String?
        public let serial: String?
        public let additionalNotes: String?
        public let price: Double

        public init(deviceName: String, imei: String? = nil, serial: String? = nil,
                    additionalNotes: String? = nil, price: Double = 0) {
            self.deviceName = deviceName
            self.imei = imei
            self.serial = serial
            self.additionalNotes = additionalNotes
            self.price = price
        }

        enum CodingKeys: String, CodingKey {
            case imei, serial, price
            case deviceName = "device_name"
            case additionalNotes = "additional_notes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case devices
        case customerId = "customer_id"
        case statusId = "status_id"
        case assignedTo = "assigned_to"
    }
}

public extension APIClient {
    func createCustomer(_ req: CreateCustomerRequest) async throws -> CreatedResource {
        try await post("/api/v1/customers", body: req, as: CreatedResource.self)
    }

    func updateCustomer(id: Int64, _ req: UpdateCustomerRequest) async throws -> CreatedResource {
        try await put("/api/v1/customers/\(id)", body: req, as: CreatedResource.self)
    }

    // Expense create wrapper lives in ExpensesEndpoints.swift
    // (canonical version supports vendor/tax/paymentMethod/notes/isReimbursable)

    func createAppointment(_ req: CreateAppointmentRequest) async throws -> CreatedResource {
        try await post("/api/v1/leads/appointments", body: req, as: CreatedResource.self)
    }

    func createLead(_ req: CreateLeadRequest) async throws -> CreatedResource {
        try await post("/api/v1/leads", body: req, as: CreatedResource.self)
    }

    func createTicket(_ req: CreateTicketRequest) async throws -> CreatedResource {
        try await post("/api/v1/tickets", body: req, as: CreatedResource.self)
    }

    /// PUT `/api/v1/tickets/:id`. Server returns the full updated ticket
    /// row; we only consume `id` for consistency with the other mutation
    /// wrappers — the view-model immediately refreshes its detail snapshot.
    func updateTicket(id: Int64, _ req: UpdateTicketRequest) async throws -> CreatedResource {
        try await put("/api/v1/tickets/\(id)", body: req, as: CreatedResource.self)
    }

    // §63 ext — Invoice + Estimate create (Phase 2)

    func createInvoice(_ req: CreateInvoiceRequest) async throws -> CreatedResource {
        try await post("/api/v1/invoices", body: req, as: CreatedResource.self)
    }

    func createEstimate(_ req: CreateEstimateRequest) async throws -> CreatedResource {
        try await post("/api/v1/estimates", body: req, as: CreatedResource.self)
    }
}

// MARK: — Invoice create

/// A single line item for `POST /api/v1/invoices`.
/// Server: invoices.routes.ts:445 — validates quantity > 0, unit_price >= 0.
public struct InvoiceLineItemRequest: Encodable, Sendable, Hashable {
    public let inventoryItemId: Int64?
    public let description: String
    public let quantity: Int
    public let unitPrice: Double
    public let taxAmount: Double
    public let lineDiscount: Double

    public init(
        inventoryItemId: Int64? = nil,
        description: String,
        quantity: Int = 1,
        unitPrice: Double,
        taxAmount: Double = 0,
        lineDiscount: Double = 0
    ) {
        self.inventoryItemId = inventoryItemId
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.taxAmount = taxAmount
        self.lineDiscount = lineDiscount
    }

    enum CodingKeys: String, CodingKey {
        case description, quantity
        case inventoryItemId = "inventory_item_id"
        case unitPrice       = "unit_price"
        case taxAmount       = "tax_amount"
        case lineDiscount    = "line_discount"
    }
}

/// `POST /api/v1/invoices` — full create including line items.
/// Server: packages/server/src/routes/invoices.routes.ts:378.
public struct CreateInvoiceRequest: Encodable, Sendable {
    public let customerId: Int64
    public let ticketId: Int64?
    public let notes: String?
    public let dueOn: String?    // YYYY-MM-DD
    public let discount: Double?
    public let discountReason: String?
    public let lineItems: [InvoiceLineItemRequest]
    /// §7.3 — idempotency key prevents duplicate creation on retry.
    public let idempotencyKey: String?

    public init(customerId: Int64, ticketId: Int64? = nil,
                notes: String? = nil, dueOn: String? = nil,
                discount: Double? = nil, discountReason: String? = nil,
                lineItems: [InvoiceLineItemRequest] = [],
                idempotencyKey: String? = nil) {
        self.customerId = customerId
        self.ticketId = ticketId
        self.notes = notes
        self.dueOn = dueOn
        self.discount = discount
        self.discountReason = discountReason
        self.lineItems = lineItems
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case notes, discount
        case customerId     = "customer_id"
        case ticketId       = "ticket_id"
        case dueOn          = "due_on"
        case discountReason = "discount_reason"
        case idempotencyKey = "idempotency_key"
        case lineItems     = "line_items"
    }
}

// MARK: — Estimate create

/// A single line item in a `CreateEstimateRequest`.
/// Maps to the `line_items` array accepted by `POST /api/v1/estimates`.
public struct EstimateLineItemRequest: Encodable, Sendable, Hashable {
    /// Optional link to an existing inventory item.
    public let inventoryItemId: Int64?
    /// Free-form description shown on the estimate PDF.
    public let description: String
    /// Must be a positive integer (server validates `integerQuantity`).
    public let quantity: Int
    /// Per-unit price before tax (validated ≥ 0, ≤ 999 999.99).
    public let unitPrice: Double
    /// Tax per-row (validated ≥ 0). Defaults to 0 when not supplied.
    public let taxAmount: Double

    public init(
        inventoryItemId: Int64? = nil,
        description: String,
        quantity: Int = 1,
        unitPrice: Double,
        taxAmount: Double = 0
    ) {
        self.inventoryItemId = inventoryItemId
        self.description = description
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.taxAmount = taxAmount
    }

    enum CodingKeys: String, CodingKey {
        case description, quantity
        case inventoryItemId = "inventory_item_id"
        case unitPrice = "unit_price"
        case taxAmount = "tax_amount"
    }
}

/// `POST /api/v1/estimates` — full set of fields accepted by the server.
/// Server: packages/server/src/routes/estimates.routes.ts.
public struct CreateEstimateRequest: Encodable, Sendable {
    public let customerId: Int64
    /// `subject` is not a server field — kept for local UI use (maps to `notes` if no
    /// `notes` is supplied, otherwise ignored; the server ignores unknown keys).
    public let subject: String?
    public let notes: String?
    public let validUntil: String?   // YYYY-MM-DD
    public let discount: Double?
    /// Line items to attach.  Server caps at 500 (`MAX_ESTIMATE_LINE_ITEMS`).
    public let lineItems: [EstimateLineItemRequest]?

    public init(
        customerId: Int64,
        subject: String? = nil,
        notes: String? = nil,
        validUntil: String? = nil,
        discount: Double? = nil,
        lineItems: [EstimateLineItemRequest]? = nil
    ) {
        self.customerId = customerId
        self.subject = subject
        self.notes = notes
        self.validUntil = validUntil
        self.discount = discount
        self.lineItems = lineItems
    }

    enum CodingKeys: String, CodingKey {
        case subject, notes, discount
        case customerId = "customer_id"
        case validUntil = "valid_until"
        case lineItems  = "line_items"
    }
}
