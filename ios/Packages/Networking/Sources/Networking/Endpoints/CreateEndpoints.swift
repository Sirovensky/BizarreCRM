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

// MARK: - Expense create

public struct CreateExpenseRequest: Encodable, Sendable {
    public let category: String
    public let amount: Double
    public let description: String?
    public let date: String?    // YYYY-MM-DD; server defaults to today if nil

    public init(category: String, amount: Double, description: String? = nil, date: String? = nil) {
        self.category = category
        self.amount = amount
        self.description = description
        self.date = date
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

    public init(title: String, startTime: String, endTime: String? = nil,
                customerId: Int64? = nil, leadId: Int64? = nil, notes: String? = nil) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.customerId = customerId
        self.leadId = leadId
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case title, notes
        case startTime = "start_time"
        case endTime = "end_time"
        case customerId = "customer_id"
        case leadId = "lead_id"
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

    public init(firstName: String, lastName: String? = nil, email: String? = nil,
                phone: String? = nil, source: String? = nil, notes: String? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.source = source
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case email, phone, source, notes
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

// MARK: - Ticket update

/// `PUT /api/v1/tickets/:id`. Server route (tickets.routes.ts:1722) accepts
/// a narrow field set: `customer_id`, `assigned_to`, `discount`,
/// `discount_reason`, `source`, `referral_source`, `labels`, `due_on`,
/// `signature`, `is_layaway`, `layaway_expires`. Device-level edits go
/// through a separate `PUT /tickets/devices/:deviceId` endpoint — those
/// are NOT part of this DTO.
public struct UpdateTicketRequest: Encodable, Sendable {
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

public struct CreateTicketRequest: Encodable, Sendable {
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

    public struct NewDevice: Encodable, Sendable {
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

    func createExpense(_ req: CreateExpenseRequest) async throws -> CreatedResource {
        try await post("/api/v1/expenses", body: req, as: CreatedResource.self)
    }

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
}
