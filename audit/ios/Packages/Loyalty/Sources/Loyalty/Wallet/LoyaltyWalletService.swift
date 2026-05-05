#if canImport(PassKit) && canImport(UIKit)
import Foundation
import PassKit
import UIKit
import Networking

/// §38 — Loyalty Apple Wallet pass service.
///
/// Actor isolation ensures thread-safe access to the cache and
/// provides a clear async boundary for all PassKit operations.
///
/// **Entitlements required (add in Xcode Signing & Capabilities):**
/// - `com.apple.developer.pass-type-identifiers` — array containing the
///   pass type identifier matching the server-signed pass
///   (e.g. `pass.com.bizarrecrm.loyalty`).
/// - `com.apple.developer.associated-domains` — `applinks:app.bizarrecrm.com`
///   (already needed for Universal Links; no additional entry required).
///
/// **Server contract:**
/// `GET /customers/:id/wallet/loyalty.pkpass` — returns a signed
/// `.pkpass` archive (application/vnd.apple.pkpass).
public actor LoyaltyWalletService {

    // MARK: - Dependencies

    private let api: APIClient
    private let passLibrary: PassLibraryProtocol

    // MARK: - Init

    public init(api: APIClient, passLibrary: PassLibraryProtocol = LivePassLibrary()) {
        self.api = api
        self.passLibrary = passLibrary
    }

    // MARK: - Public API

    /// Download the signed `.pkpass` for `customerId`, write to a temp
    /// file, and return its `URL`.
    ///
    /// - Returns: A `file://` URL pointing to the downloaded `.pkpass`.
    /// - Throws: `LoyaltyWalletError.network` on transport failures.
    public func fetchPass(customerId: String) async throws -> URL {
        guard let base = await api.currentBaseURL() else {
            throw LoyaltyWalletError.noBaseURL
        }
        let url = base.appendingPathComponent("/customers/\(customerId)/wallet/loyalty.pkpass")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LoyaltyWalletError.network(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LoyaltyWalletError.httpStatus(http.statusCode)
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loyalty_\(customerId)_\(UUID().uuidString).pkpass")
        try data.write(to: tmpURL)
        return tmpURL
    }

    /// Present `PKAddPassesViewController` for the pass at `url`.
    ///
    /// Uses the topmost `UIViewController` in the active window scene.
    /// - Throws: `LoyaltyWalletError.invalidPass` if the file cannot be
    ///   parsed as a `PKPass`.
    /// - Throws: `LoyaltyWalletError.noRootViewController` if no window
    ///   is available to present from.
    public func addToWallet(from url: URL) async throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoyaltyWalletError.invalidPass
        }

        let pass: PKPass
        do {
            pass = try PKPass(data: data)
        } catch {
            throw LoyaltyWalletError.invalidPass
        }

        try await MainActor.run {
            guard let controller = PKAddPassesViewController(pass: pass) else {
                throw LoyaltyWalletError.invalidPass
            }
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else {
                throw LoyaltyWalletError.noRootViewController
            }
            guard let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
                throw LoyaltyWalletError.noRootViewController
            }
            var top = window.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            guard let root = top else { throw LoyaltyWalletError.noRootViewController }
            root.present(controller, animated: true)
        }
    }

    /// Notify the server to re-sign and re-push the pass.
    ///
    /// The server responds with `{ success: true, data: { passUrl: String } }`.
    /// The client then re-downloads via `fetchPass`.
    ///
    /// - Returns: Updated pass `URL`.
    /// - Throws: `LoyaltyWalletError.network` on failures.
    public func refreshPass(passId: String) async throws -> URL {
        let response = try await api.post(
            "/wallet/loyalty/passes/\(passId)/refresh",
            body: EmptyBody(),
            as: PassRefreshResponse.self
        )
        guard let base = await api.currentBaseURL() else {
            throw LoyaltyWalletError.noBaseURL
        }
        let passURL = base.appendingPathComponent(response.passUrl)
        var request = URLRequest(url: passURL)
        request.httpMethod = "GET"
        let (data, _) = try await URLSession.shared.data(for: request)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("loyalty_refresh_\(passId)_\(UUID().uuidString).pkpass")
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

// MARK: - PassRefreshResponse

struct PassRefreshResponse: Decodable, Sendable {
    let passUrl: String
    enum CodingKeys: String, CodingKey {
        case passUrl = "pass_url"
    }
}

// MARK: - EmptyBody

struct EmptyBody: Encodable, Sendable {}

// MARK: - PassLibraryProtocol

/// Abstracts `PKPassLibrary` for testing.
public protocol PassLibraryProtocol: Sendable {
    func containsPass(_ pass: PKPass) -> Bool
    func replacePass(with pass: PKPass) -> Bool
}

/// Live implementation backed by `PKPassLibrary.default()`.
public struct LivePassLibrary: PassLibraryProtocol {
    public init() {}

    public func containsPass(_ pass: PKPass) -> Bool {
        PKPassLibrary().containsPass(pass)
    }

    public func replacePass(with pass: PKPass) -> Bool {
        PKPassLibrary().replacePass(with: pass)
    }
}

// MARK: - LoyaltyWalletError

public enum LoyaltyWalletError: Error, LocalizedError, Sendable {
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
            return "The loyalty pass could not be opened. Please try again."
        case .noRootViewController:
            return "Could not find a window to present the pass from."
        }
    }
}

#endif // canImport(PassKit) && canImport(UIKit)
