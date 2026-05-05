import Foundation

// MARK: - Supplier

/// §58 – Supplier/vendor master record.
public struct Supplier: Codable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let contactName: String?
    public let email: String
    public let phone: String
    public let address: String
    public let paymentTerms: String
    public let leadTimeDays: Int

    public init(
        id: Int64,
        name: String,
        contactName: String? = nil,
        email: String,
        phone: String,
        address: String,
        paymentTerms: String,
        leadTimeDays: Int
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.paymentTerms = paymentTerms
        self.leadTimeDays = leadTimeDays
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case contactName  = "contact_name"
        case email
        case phone
        case address
        case paymentTerms = "payment_terms"
        case leadTimeDays = "lead_time_days"
    }
}
