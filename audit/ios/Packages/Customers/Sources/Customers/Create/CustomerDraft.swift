import Foundation

// §63 ext — Customer create draft model (Phase 2)

/// Persisted snapshot of in-progress customer create form fields.
public struct CustomerDraft: Codable, Sendable, Equatable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var phone: String
    public var mobile: String
    public var organization: String
    public var address1: String
    public var city: String
    public var state: String
    public var postcode: String
    public var notes: String
    public var updatedAt: Date

    public init(
        firstName: String = "",
        lastName: String = "",
        email: String = "",
        phone: String = "",
        mobile: String = "",
        organization: String = "",
        address1: String = "",
        city: String = "",
        state: String = "",
        postcode: String = "",
        notes: String = "",
        updatedAt: Date = Date()
    ) {
        self.firstName    = firstName
        self.lastName     = lastName
        self.email        = email
        self.phone        = phone
        self.mobile       = mobile
        self.organization = organization
        self.address1     = address1
        self.city         = city
        self.state        = state
        self.postcode     = postcode
        self.notes        = notes
        self.updatedAt    = updatedAt
    }
}
