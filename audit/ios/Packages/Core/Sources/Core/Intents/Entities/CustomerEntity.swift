import AppIntents
import Foundation
#if os(iOS)

/// AppEntity wrapping the `Customer` model, exposed to Shortcuts + Siri.
@available(iOS 16, *)
public struct CustomerEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Customer")
    public static let defaultQuery = CustomerEntityQuery()

    public let id: String
    /// Numeric database id, preserved separately for API calls.
    public let numericId: Int64
    public let displayName: String
    public let phone: String?
    public let email: String?

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: displayName),
            subtitle: phone.map { LocalizedStringResource(stringLiteral: $0) }
        )
    }

    public init(from customer: Customer) {
        self.id = String(customer.id)
        self.numericId = customer.id
        self.displayName = customer.displayName
        self.phone = customer.phone
        self.email = customer.email
    }

    public init(
        id: Int64,
        displayName: String,
        phone: String? = nil,
        email: String? = nil
    ) {
        self.id = String(id)
        self.numericId = id
        self.displayName = displayName
        self.phone = phone
        self.email = email
    }
}
#endif // os(iOS)
