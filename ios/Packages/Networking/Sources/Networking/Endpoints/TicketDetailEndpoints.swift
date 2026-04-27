import Foundation

/// `GET /api/v1/tickets/:id` response (unwrapped envelope).
/// Server: packages/server/src/routes/tickets.routes.ts — getFullTicketAsync.
///
/// All notes, history, and photos are embedded in this single payload —
/// Android does not hit separate endpoints for those sections.
public struct TicketDetail: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String
    public let customerId: Int64?
    public let statusId: Int64?
    public let assignedTo: Int64?
    public let subtotal: Double?
    public let discount: Double?
    public let discountReason: String?
    public let totalTax: Double?
    public let total: Double?
    public let signature: String?
    public let invoiceId: Int64?
    public let createdBy: Int64?
    public let createdAt: String?
    public let updatedAt: String?
    public let howDidUFindUs: String?
    public let isPinned: Bool?
    public let isStarred: Bool?

    public let customer: Customer?
    public let status: Status?
    public let assignedUser: UserRef?
    public let createdByUser: UserRef?
    public let devices: [TicketDevice]
    public let notes: [TicketNote]
    public let history: [TicketHistory]
    public let photos: [TicketPhoto]
    /// §4.2 — Payments from the linked invoice. Empty when no invoice attached.
    public let payments: [TicketPayment]

    public struct Customer: Decodable, Sendable, Hashable {
        public let id: Int64?
        public let firstName: String?
        public let lastName: String?
        public let phone: String?
        public let mobile: String?
        public let email: String?
        public let organization: String?

        public var displayName: String {
            let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !parts.isEmpty { return parts.joined(separator: " ") }
            if let org = organization, !org.isEmpty { return org }
            return "Unknown customer"
        }

        public var callablePhone: String? {
            if let p = phone, !p.isEmpty { return p }
            if let m = mobile, !m.isEmpty { return m }
            return nil
        }

        enum CodingKeys: String, CodingKey {
            case id, phone, mobile, email, organization
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct Status: Decodable, Sendable, Hashable {
        public let id: Int64
        public let name: String
        public let color: String?
        public let isClosed: Bool?
        public let isCancelled: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, color
            case isClosed = "is_closed"
            case isCancelled = "is_cancelled"
        }
    }

    public struct UserRef: Decodable, Sendable, Hashable {
        public let id: Int64
        public let firstName: String?
        public let lastName: String?

        public var fullName: String {
            [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: " ")
        }

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct TicketDevice: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let name: String?
        public let deviceName: String?
        public let manufacturerName: String?
        public let imei: String?
        public let serial: String?
        public let securityCode: String?
        public let color: String?
        public let network: String?
        public let price: Double?
        public let total: Double?
        public let additionalNotes: String?
        public let customerComments: String?
        public let staffComments: String?
        public let status: Status?
        public let assignedUser: UserRef?
        public let service: Service?
        public let parts: [Part]?

        public var displayName: String {
            if let n = name, !n.isEmpty { return n }
            if let d = deviceName, !d.isEmpty { return d }
            return "Device"
        }

        public struct Service: Decodable, Sendable, Hashable {
            public let id: Int64?
            public let name: String?
        }

        public struct Part: Decodable, Sendable, Identifiable, Hashable {
            public let id: Int64
            public let name: String?
            public let sku: String?
            public let quantity: Int?
            public let price: Double?
            public let total: Double?
            public let status: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, imei, serial, color, network, price, total, status, service, parts
            case deviceName = "device_name"
            case manufacturerName = "manufacturer_name"
            case securityCode = "security_code"
            case additionalNotes = "additional_notes"
            case customerComments = "customer_comments"
            case staffComments = "staff_comments"
            case assignedUser = "assigned_user"
        }
    }

    public struct TicketNote: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let type: String?
        public let content: String?
        public let image: String?
        public let isFlagged: Bool?
        public let deviceName: String?
        public let createdAt: String?
        public let user: UserRef?

        public var userName: String { user?.fullName ?? "Staff" }
        public var stripped: String { Self.stripHTML(content ?? "") }

        private static func stripHTML(_ s: String) -> String {
            s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        enum CodingKeys: String, CodingKey {
            case id, type, content, image, user
            case isFlagged = "is_flagged"
            case deviceName = "device_name"
            case createdAt = "created_at"
        }
    }

    public struct TicketHistory: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let description: String?
        public let userId: Int64?
        public let userName: String?
        public let createdAt: String?

        public var stripped: String {
            (description ?? "")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        enum CodingKeys: String, CodingKey {
            case id, description
            case userId = "user_id"
            case userName = "user_name"
            case createdAt = "created_at"
        }
    }

    // MARK: - §4.2 Payments (from linked invoice)

    public struct TicketPayment: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let amount: Double
        public let method: String?
        public let methodDetail: String?
        public let transactionId: String?
        public let notes: String?
        public let createdAt: String?

        public var methodDisplay: String {
            let base = method?.capitalized ?? "Payment"
            if let detail = methodDetail, !detail.isEmpty { return "\(base) — \(detail)" }
            return base
        }

        enum CodingKeys: String, CodingKey {
            case id, amount, method, notes
            case methodDetail = "method_detail"
            case transactionId = "transaction_id"
            case createdAt = "created_at"
        }
    }

    public struct TicketPhoto: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let url: String?
        public let type: String?
        public let fileName: String?
        public let createdAt: String?
        public let deviceId: Int64?

        enum CodingKeys: String, CodingKey {
            case id, url, type
            case fileName = "file_name"
            case createdAt = "created_at"
            case deviceId = "device_id"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case customerId = "customer_id"
        case statusId = "status_id"
        case assignedTo = "assigned_to"
        case subtotal, discount
        case discountReason = "discount_reason"
        case totalTax = "total_tax"
        case total
        case signature
        case invoiceId = "invoice_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case howDidUFindUs = "how_did_u_find_us"
        case isPinned = "is_pinned"
        case isStarred = "is_starred"
        case customer, status
        case assignedUser = "assigned_user"
        case createdByUser = "created_by_user"
        case devices, notes, history, photos, payments
    }

    // MARK: - Safe decoding for missing arrays
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        orderId = try c.decodeIfPresent(String.self, forKey: .orderId) ?? "T-?"
        customerId = try c.decodeIfPresent(Int64.self, forKey: .customerId)
        statusId = try c.decodeIfPresent(Int64.self, forKey: .statusId)
        assignedTo = try c.decodeIfPresent(Int64.self, forKey: .assignedTo)
        subtotal = try c.decodeIfPresent(Double.self, forKey: .subtotal)
        discount = try c.decodeIfPresent(Double.self, forKey: .discount)
        discountReason = try c.decodeIfPresent(String.self, forKey: .discountReason)
        totalTax = try c.decodeIfPresent(Double.self, forKey: .totalTax)
        total = try c.decodeIfPresent(Double.self, forKey: .total)
        signature = try c.decodeIfPresent(String.self, forKey: .signature)
        invoiceId = try c.decodeIfPresent(Int64.self, forKey: .invoiceId)
        createdBy = try c.decodeIfPresent(Int64.self, forKey: .createdBy)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        howDidUFindUs = try c.decodeIfPresent(String.self, forKey: .howDidUFindUs)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred)
        customer = try c.decodeIfPresent(Customer.self, forKey: .customer)
        status = try c.decodeIfPresent(Status.self, forKey: .status)
        assignedUser = try c.decodeIfPresent(UserRef.self, forKey: .assignedUser)
        createdByUser = try c.decodeIfPresent(UserRef.self, forKey: .createdByUser)
        devices = (try? c.decode([TicketDevice].self, forKey: .devices)) ?? []
        notes = (try? c.decode([TicketNote].self, forKey: .notes)) ?? []
        history = (try? c.decode([TicketHistory].self, forKey: .history)) ?? []
        photos = (try? c.decode([TicketPhoto].self, forKey: .photos)) ?? []
        payments = (try? c.decode([TicketPayment].self, forKey: .payments)) ?? []
    }
}

public extension APIClient {
    func ticket(id: Int64) async throws -> TicketDetail {
        try await get("/api/v1/tickets/\(id)", as: TicketDetail.self)
    }
}
