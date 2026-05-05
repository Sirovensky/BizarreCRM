import Foundation
#if canImport(PassKit)
import PassKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// §24 / §38 / §40 — APNs silent push bridge for Apple Wallet pass updates.
///
/// Apple Wallet passes use their own push pipeline:
///   1. The server signs a pass and includes an `authenticationToken` +
///      `webServiceURL` in the pass JSON.
///   2. PassKit registers for push updates independently (standard APNs,
///      not PushKit/VoIP). The OS calls the web-service `registerDevice`
///      endpoint automatically.
///   3. When pass content changes (balance, tier, expiry), the server sends
///      an APNs silent push with `passTypeIdentifier` + `serialNumber`.
///   4. The OS calls `updatePass` on the web-service, NOT the iOS app directly.
///
/// For the MVP the server delivers a **silent APNs push** with the custom
/// payload key `"kind": "wallet-pass-update"` to wake the app. On receipt,
/// `PassUpdateSubscriber` fetches a fresh pass and replaces it in the library.
///
/// **Integration with SilentPushHandler (Phase 6 §21):**
/// If `SilentPushHandler` exists in the Notifications package, register
/// from `AppDelegate.application(_:didReceiveRemoteNotification:)`:
/// ```swift
/// // AppDelegate or Scene delegate — do NOT edit RootView/BizarreCRMApp
/// PassUpdateSubscriber.shared.handleSilentPush(userInfo: userInfo) { handled in
///     completionHandler(handled ? .newData : .noData)
/// }
/// ```
///
/// **Required entitlements:**
/// - `com.apple.developer.pass-type-identifiers` — must list every pass
///   type identifier the tenant uses (e.g. `pass.com.bizarrecrm.loyalty`,
///   `pass.com.bizarrecrm.giftcard`).
/// These are NOT added automatically — the merchant adds them in Xcode
/// Signing & Capabilities before shipping.
@MainActor
public final class PassUpdateSubscriber {

    // MARK: - Singleton

    public static let shared = PassUpdateSubscriber()

    // MARK: - State

    /// Registered handlers keyed by `kind` string.
    private var handlers: [String: (PassUpdatePayload) async -> Void] = [:]

    // MARK: - Init

    private init() {}

    // MARK: - Registration

    /// Register a handler for wallet-pass-update silent pushes.
    ///
    /// The Pos and Loyalty modules call this during app init to
    /// wire their respective `fetchPass` + `replacePass` paths.
    ///
    /// - Parameters:
    ///   - kind: Identifies the pass type. Use `"wallet-pass-update.loyalty"`
    ///     or `"wallet-pass-update.giftcard"`.
    ///   - handler: Called on the main actor when a matching push arrives.
    public func register(kind: String, handler: @escaping @Sendable (PassUpdatePayload) async -> Void) {
        handlers[kind] = handler
    }

    // MARK: - Silent push entry point

    /// Call from `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
    /// (or from an existing `SilentPushHandler` dispatcher).
    ///
    /// Returns `true` if the payload was handled by a registered handler.
    @discardableResult
    public func handleSilentPush(
        userInfo: [AnyHashable: Any],
        completionHandler: ((Bool) -> Void)? = nil
    ) -> Bool {
        guard
            let kind = userInfo["kind"] as? String,
            let passTypeIdentifier = userInfo["passTypeIdentifier"] as? String,
            let serialNumber = userInfo["serialNumber"] as? String
        else {
            completionHandler?(false)
            return false
        }

        let payload = PassUpdatePayload(
            kind: kind,
            passTypeIdentifier: passTypeIdentifier,
            serialNumber: serialNumber
        )

        // Try exact kind match, then prefix match for "wallet-pass-update.*".
        let matchedHandler = handlers[kind]
            ?? handlers.first(where: { kind.hasPrefix($0.key) })?.value

        guard let handler = matchedHandler else {
            completionHandler?(false)
            return false
        }

        Task {
            await handler(payload)
            completionHandler?(true)
        }
        return true
    }
}

// MARK: - PassUpdatePayload

public struct PassUpdatePayload: Sendable {
    public let kind: String
    public let passTypeIdentifier: String
    public let serialNumber: String
}

// MARK: - Convenience pass-replacement helper

#if canImport(PassKit) && canImport(UIKit)
/// Replace an existing pass in the user's Wallet with fresh data.
///
/// Fetches the raw `.pkpass` bytes from `url`, parses them, and calls
/// `PKPassLibrary.default().replacePass(with:)`. No UI is presented —
/// this is a silent background update.
///
/// - Parameters:
///   - url: Local `file://` URL pointing to the updated `.pkpass`.
/// - Returns: `true` if the library accepted the replacement.
/// - Throws: `PassReplaceError` on parsing failure.
public func replacePassSilently(from url: URL) throws -> Bool {
    let data = try Data(contentsOf: url)
    let pass = try PKPass(data: data)
    return PKPassLibrary().replacePass(with: pass)
}

public enum PassReplaceError: Error, LocalizedError, Sendable {
    case invalidData
    public var errorDescription: String? { "Pass data could not be parsed." }
}
#endif
