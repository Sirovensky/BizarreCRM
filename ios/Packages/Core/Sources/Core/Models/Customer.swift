import Foundation

/// A BizarreCRM customer record scoped to a single tenant.
///
/// `Customer` is the canonical read model used throughout the iOS app whenever
/// a customer is displayed or passed between features.  It is returned by the
/// server's `GET /customers` and `GET /customers/:id` endpoints and decoded
/// from the standard JSON envelope.
///
/// ## Tenant isolation
/// Every customer belongs to exactly one tenant.  The server enforces row-level
/// isolation via `tenant_id`; the iOS client never needs to filter by tenant
/// explicitly — the active session token carries the scope.
///
/// ## Codable
/// Property names map 1-to-1 to the JSON keys returned by the server
/// (`first_name`, `last_name`, etc.) via a custom `CodingKeys` enum if needed.
/// Dates are ISO 8601 strings decoded with `JSONDecoder.dateDecodingStrategy = .iso8601`.
///
/// ## See Also
/// - ``PaginatedLoader`` for fetching paginated customer lists.
/// - `CustomerRepository` (in the Customers package) for CRUD operations.
public struct Customer: Identifiable, Hashable, Codable, Sendable {
    /// Server-assigned primary key.  Stable for the lifetime of the record.
    public let id: Int64
    /// Customer's given name.
    public let firstName: String
    /// Customer's family name.
    public let lastName: String
    /// Primary phone number in any format the user entered.
    /// Normalize with ``PhoneFormatter/normalize(_:)`` before display or search.
    public let phone: String?
    /// Primary email address.  Validated on the server; use ``EmailValidator``
    /// client-side before submitting edits.
    public let email: String?
    /// Free-form internal notes visible only to staff.  Never shown on
    /// customer-facing pages or receipts.
    public let notes: String?
    /// When the record was first created on the server (UTC).
    public let createdAt: Date
    /// When any field was last modified on the server (UTC).
    /// Used for optimistic-concurrency checks during edits.
    public let updatedAt: Date

    public init(
        id: Int64,
        firstName: String,
        lastName: String,
        phone: String? = nil,
        email: String? = nil,
        notes: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.email = email
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Full name formatted as "<first> <last>", with leading/trailing whitespace
    /// removed.  Falls back gracefully when either component is empty.
    public var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}
