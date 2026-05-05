import Foundation

/// §24 / §38 / §40 — Apple Wallet pass endpoints.
///
/// Three pass types:
///   - **Loyalty** (`pass.com.bizarrecrm.loyalty`) — points / tier card.
///   - **Gift card** (`pass.com.bizarrecrm.giftcard`) — store-value card.
///
/// Server routes (all under `/api/v1/`):
///   - `GET  /customers/:id/wallet/loyalty.pkpass`        — raw signed .pkpass
///   - `POST /wallet/loyalty/passes/:passId/refresh`      — trigger re-sign + push
///   - `GET  /gift-cards/:id/wallet/giftcard.pkpass`      — raw signed .pkpass
///   - `POST /wallet/gift-cards/passes/:passId/refresh`   — trigger re-sign + push
///   - `POST /settings/wallet-pass-template`              — update template fields
///
/// None of these are implemented server-side at time of writing. All wrappers
/// throw `APITransportError.httpStatus(501, …)` so callers can show
/// "Coming soon" rather than an error. Swap the stubs when the server ships.

// MARK: - DTOs

/// Pass refresh server response.
public struct WalletPassRefreshResponse: Decodable, Sendable {
    /// Relative or absolute URL to the newly signed `.pkpass`.
    public let passUrl: String

    public init(passUrl: String) {
        self.passUrl = passUrl
    }

    enum CodingKeys: String, CodingKey {
        case passUrl = "pass_url"
    }
}

/// Template save body (mirrors `WalletPassTemplateRequest` in Loyalty; kept
/// here so the Networking layer remains the single serialization source).
public struct WalletPassTemplateBody: Encodable, Sendable {
    public let enabled: Bool
    public let headerLine: String?
    public let backDescription: String?
    public let backWebURL: String?
    public let backPhone: String?
    public let backTerms: String?

    public init(
        enabled: Bool,
        headerLine: String? = nil,
        backDescription: String? = nil,
        backWebURL: String? = nil,
        backPhone: String? = nil,
        backTerms: String? = nil
    ) {
        self.enabled = enabled
        self.headerLine = headerLine
        self.backDescription = backDescription
        self.backWebURL = backWebURL
        self.backPhone = backPhone
        self.backTerms = backTerms
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case headerLine      = "header_line"
        case backDescription = "back_description"
        case backWebURL      = "back_web_url"
        case backPhone       = "back_phone"
        case backTerms       = "back_terms"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Loyalty

    /// Trigger the server to re-sign the loyalty pass and push the update.
    ///
    /// 501 stub: server endpoint not yet implemented.
    func refreshLoyaltyPass(passId: String) async throws -> WalletPassRefreshResponse {
        // Server endpoint not yet implemented — stub to 501.
        throw APITransportError.httpStatus(501, message: "Loyalty pass refresh coming soon")
        // Uncomment when server ships:
        // return try await post(
        //     "/wallet/loyalty/passes/\(passId)/refresh",
        //     body: EmptyWalletBody(),
        //     as: WalletPassRefreshResponse.self
        // )
    }

    // MARK: Gift card

    /// Trigger the server to re-sign the gift-card pass and push the update.
    ///
    /// 501 stub: server endpoint not yet implemented.
    func refreshGiftCardPass(passId: String) async throws -> WalletPassRefreshResponse {
        // Server endpoint not yet implemented — stub to 501.
        throw APITransportError.httpStatus(501, message: "Gift card pass refresh coming soon")
        // Uncomment when server ships:
        // return try await post(
        //     "/wallet/gift-cards/passes/\(passId)/refresh",
        //     body: EmptyWalletBody(),
        //     as: WalletPassRefreshResponse.self
        // )
    }

    // MARK: Settings

    /// Save the wallet pass template settings.
    ///
    /// 501 stub: server endpoint not yet implemented.
    func saveWalletPassTemplate(_ body: WalletPassTemplateBody) async throws {
        // Server endpoint not yet implemented — stub to 501.
        throw APITransportError.httpStatus(501, message: "Wallet pass template coming soon")
        // Uncomment when server ships:
        // _ = try await post(
        //     "/settings/wallet-pass-template",
        //     body: body,
        //     as: EmptyWalletResponse.self
        // )
    }
}

// MARK: - Private helpers

private struct EmptyWalletBody: Encodable, Sendable {}
private struct EmptyWalletResponse: Decodable, Sendable {}
