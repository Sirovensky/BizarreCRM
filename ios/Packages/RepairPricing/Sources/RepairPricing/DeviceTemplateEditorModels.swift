import Foundation

// MARK: - §43.5 Template Editor Supporting Models

/// The four device conditions supported in the editor.
public struct DeviceCondition: Identifiable, Codable, Sendable, Hashable {
    public let id: String  // "new" / "used" / "refurb" / "damaged"
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    public static let allCases: [DeviceCondition] = [
        DeviceCondition(id: "new",     label: "New"),
        DeviceCondition(id: "used",    label: "Used"),
        DeviceCondition(id: "refurb",  label: "Refurbished"),
        DeviceCondition(id: "damaged", label: "Damaged")
    ]
}

/// A service row entered inline while creating/editing a template.
public struct InlineService: Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String = ""
    public var rawPrice: String = ""
    public var description: String = ""

    public init(name: String = "", rawPrice: String = "", description: String = "") {
        self.name = name
        self.rawPrice = rawPrice
        self.description = description
    }

    /// Returns price in cents or nil if raw string is invalid.
    public var priceCents: Int? {
        guard let d = Double(rawPrice.trimmingCharacters(in: .whitespacesAndNewlines)), d > 0 else { return nil }
        return Int((d * 100).rounded())
    }
}

// MARK: - API request bodies

/// POST /device-templates body.
public struct CreateDeviceTemplateRequest: Encodable, Sendable {
    let name: String
    let deviceCategory: String
    let deviceModel: String?
    let year: Int?
    let conditions: [String]
    let services: [InlineServiceRequest]

    enum CodingKeys: String, CodingKey {
        case name, year, conditions, services
        case deviceCategory = "device_category"
        case deviceModel    = "device_model"
    }
}

/// PATCH /device-templates/:id body (all fields optional).
public struct UpdateDeviceTemplateRequest: Encodable, Sendable {
    let name: String?
    let deviceCategory: String?
    let deviceModel: String?
    let year: Int?
    let conditions: [String]?
    let services: [InlineServiceRequest]?

    enum CodingKeys: String, CodingKey {
        case name, year, conditions, services
        case deviceCategory = "device_category"
        case deviceModel    = "device_model"
    }
}

/// Service entry inside a template create/update request.
public struct InlineServiceRequest: Encodable, Sendable {
    let serviceName: String
    let defaultPriceCents: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case serviceName      = "service_name"
        case defaultPriceCents = "default_price_cents"
        case description
    }
}
