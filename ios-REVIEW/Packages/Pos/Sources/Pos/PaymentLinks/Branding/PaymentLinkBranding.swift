import Foundation

// MARK: - §41.2 Payment Link Branding model

/// Tenant-level branding applied to every public pay page.
/// Money: not applicable (URLs / hex strings). All values are Optional so
/// the server can omit any field and the app falls back to defaults.
public struct PaymentLinkBranding: Codable, Sendable, Equatable {
    public let logoUrl: String?
    public let primaryColor: String?     // hex, e.g. "#FF6B00"
    public let secondaryColor: String?   // hex
    public let footerText: String?
    public let terms: String?

    public init(
        logoUrl: String? = nil,
        primaryColor: String? = nil,
        secondaryColor: String? = nil,
        footerText: String? = nil,
        terms: String? = nil
    ) {
        self.logoUrl = logoUrl
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.footerText = footerText
        self.terms = terms
    }

    enum CodingKeys: String, CodingKey {
        case logoUrl       = "logo_url"
        case primaryColor  = "primary_color"
        case secondaryColor = "secondary_color"
        case footerText    = "footer_text"
        case terms
    }
}

// MARK: - Patch request

/// PATCH body sent to `PATCH /settings/payment-link-branding`.
/// Mirrors `PaymentLinkBranding` but uses `Encodable` only — the response
/// round-trips back as `PaymentLinkBranding` via the `GET` endpoint.
public struct PaymentLinkBrandingPatch: Encodable, Sendable {
    public let logoUrl: String?
    public let primaryColor: String?
    public let secondaryColor: String?
    public let footerText: String?
    public let terms: String?

    public init(from branding: PaymentLinkBranding) {
        self.logoUrl = branding.logoUrl
        self.primaryColor = branding.primaryColor
        self.secondaryColor = branding.secondaryColor
        self.footerText = branding.footerText
        self.terms = branding.terms
    }

    enum CodingKeys: String, CodingKey {
        case logoUrl       = "logo_url"
        case primaryColor  = "primary_color"
        case secondaryColor = "secondary_color"
        case footerText    = "footer_text"
        case terms
    }
}

// MARK: - APIClient extension

import Networking

public extension APIClient {
    /// `GET /settings/payment-link-branding`
    func getPaymentLinkBranding() async throws -> PaymentLinkBranding {
        try await get("/api/v1/settings/payment-link-branding", as: PaymentLinkBranding.self)
    }

    /// `PATCH /settings/payment-link-branding`
    func updatePaymentLinkBranding(_ patchBody: PaymentLinkBrandingPatch) async throws -> PaymentLinkBranding {
        try await patch(
            "/api/v1/settings/payment-link-branding",
            body: patchBody,
            as: PaymentLinkBranding.self
        )
    }
}
