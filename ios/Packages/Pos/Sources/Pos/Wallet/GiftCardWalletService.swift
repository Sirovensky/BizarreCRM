#if canImport(PassKit) && canImport(UIKit)
import Foundation
import PassKit
import UIKit
import Networking

/// §40 — Gift card Apple Wallet pass service.
///
/// Follows the same pattern as `LoyaltyWalletService` (§38).
///
/// **Entitlements required (add in Xcode Signing & Capabilities):**
/// - `com.apple.developer.pass-type-identifiers` — must include the
///   gift-card pass type (e.g. `pass.com.bizarrecrm.giftcard`).
///
/// **Server contract:**
/// `GET /gift-cards/:id/wallet/giftcard.pkpass` — returns a signed
/// `.pkpass` archive (application/vnd.apple.pkpass).
public actor GiftCardWalletService {

    // MARK: - Dependencies

    private let api: APIClient
    private let passLibrary: GiftCardPassLibraryProtocol

    // MARK: - Init

    public init(api: APIClient, passLibrary: GiftCardPassLibraryProtocol = LiveGiftCardPassLibrary()) {
        self.api = api
        self.passLibrary = passLibrary
    }

    // MARK: - Public API

    /// Download the signed `.pkpass` for `giftCardId`, write to a temp
    /// file, and return its `URL`.
    ///
    /// - Returns: A `file://` URL pointing to the downloaded `.pkpass`.
    /// - Throws: `GiftCardWalletError` on failure.
    public func fetchPass(giftCardId: String) async throws -> URL {
        guard let base = await api.currentBaseURL() else {
            throw GiftCardWalletError.noBaseURL
        }
        let url = base.appendingPathComponent("/gift-cards/\(giftCardId)/wallet/giftcard.pkpass")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GiftCardWalletError.network(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GiftCardWalletError.httpStatus(http.statusCode)
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("giftcard_\(giftCardId)_\(UUID().uuidString).pkpass")
        try data.write(to: tmpURL)
        return tmpURL
    }

    /// Present `PKAddPassesViewController` for the gift-card pass at `url`.
    ///
    /// - Throws: `GiftCardWalletError.invalidPass` if the pass cannot be parsed.
    /// - Throws: `GiftCardWalletError.noRootViewController` if no window found.
    public func addToWallet(from url: URL) async throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GiftCardWalletError.invalidPass
        }

        let pass: PKPass
        do {
            pass = try PKPass(data: data)
        } catch {
            throw GiftCardWalletError.invalidPass
        }

        guard let controller = PKAddPassesViewController(pass: pass) else {
            throw GiftCardWalletError.invalidPass
        }

        guard let root = await rootViewController() else {
            throw GiftCardWalletError.noRootViewController
        }

        await MainActor.run {
            root.present(controller, animated: true)
        }
    }

    /// Ask the server to re-sign and re-push the gift card pass.
    ///
    /// - Returns: Updated pass `URL`.
    public func refreshPass(passId: String) async throws -> URL {
        let response = try await api.post(
            "/wallet/gift-cards/passes/\(passId)/refresh",
            body: GiftCardRefreshBody(),
            as: GiftCardPassRefreshResponse.self
        )
        guard let base = await api.currentBaseURL() else {
            throw GiftCardWalletError.noBaseURL
        }
        let passURL = base.appendingPathComponent(response.passUrl)
        var request = URLRequest(url: passURL)
        request.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("giftcard_refresh_\(passId)_\(UUID().uuidString).pkpass")
        try data.write(to: tmpURL)
        return tmpURL
    }

    // MARK: - Private

    @MainActor
    private func rootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        guard let window = scene?.windows.first(where: { $0.isKeyWindow })
                ?? scene?.windows.first else { return nil }

        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - GiftCardPassLibraryProtocol

/// Abstracts `PKPassLibrary` for gift-card pass testing.
public protocol GiftCardPassLibraryProtocol: Sendable {
    func containsPass(_ pass: PKPass) -> Bool
    func replacePass(with pass: PKPass) -> Bool
}

public struct LiveGiftCardPassLibrary: GiftCardPassLibraryProtocol {
    public init() {}

    public func containsPass(_ pass: PKPass) -> Bool {
        PKPassLibrary.default().containsPass(pass)
    }

    public func replacePass(with pass: PKPass) -> Bool {
        PKPassLibrary.default().replacePass(with: pass)
    }
}

// MARK: - DTOs

struct GiftCardRefreshBody: Encodable, Sendable {}

struct GiftCardPassRefreshResponse: Decodable, Sendable {
    let passUrl: String
    enum CodingKeys: String, CodingKey {
        case passUrl = "pass_url"
    }
}

// MARK: - GiftCardWalletError

public enum GiftCardWalletError: Error, LocalizedError, Sendable {
    case noBaseURL
    case network(Error)
    case httpStatus(Int)
    case invalidPass
    case noRootViewController

    public var errorDescription: String? {
        switch self {
        case .noBaseURL:
            return "Server URL not configured."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpStatus(let code):
            return "Server returned status \(code)."
        case .invalidPass:
            return "The gift card pass could not be opened. Please try again."
        case .noRootViewController:
            return "Could not find a window to present the pass from."
        }
    }
}

#endif // canImport(PassKit) && canImport(UIKit)
