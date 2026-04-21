import Foundation
import Networking

/// §38.4 — Triggers a server-side Apple Wallet pass refresh.
///
/// Called whenever a customer's loyalty tier changes or their membership renews.
/// The server re-signs the pass and pushes an APNs silent push to PassKit, which
/// causes iOS to silently call `PKPassLibrary.replacePass(_:)` with the new pass.
///
/// **Server contract:**
/// `POST /passes/:passId/refresh` → `{ success: Bool, data: { passId: String } }`
///
/// **Not responsible for:**
/// - Downloading the new pass bytes — PassKit handles that via the APNs push.
/// - Displaying UI — this is a fire-and-forget background operation.
///
/// **Extension point (Phase 6 E):**
/// This actor complements `PassUpdateSubscriber` (in `Pos/Wallet/`). The subscriber
/// handles inbound silent pushes; this updater initiates outbound refresh requests.
public actor MembershipPassUpdater {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    // MARK: - Public API

    /// Notify the server to refresh the Wallet pass for `passId`.
    ///
    /// This is appropriate to call:
    /// - On tier promotion/demotion.
    /// - On membership renewal (new expiry date on the pass).
    /// - On membership cancellation (server marks pass as voided).
    ///
    /// Failures are logged but not rethrown — a pass not refreshing is non-fatal.
    public func refreshPass(passId: String) async {
        do {
            let response = try await api.post(
                "/passes/\(passId)/refresh",
                body: EmptyPassBody(),
                as: PassRefreshResult.self
            )
            AppLog.debug("[MembershipPassUpdater] refreshed pass \(response.passId)")
        } catch {
            AppLog.error("[MembershipPassUpdater] refresh failed for \(passId): \(error)")
        }
    }

    /// Refresh passes for all memberships belonging to `customerId`.
    ///
    /// Fetches the customer's loyalty pass metadata, then triggers
    /// `refreshPass(passId:)` for each applicable pass.
    public func refreshPasses(for customerId: String, passIds: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for passId in passIds {
                group.addTask { await self.refreshPass(passId: passId) }
            }
        }
    }
}

// MARK: - DTOs (module-private)

private struct EmptyPassBody: Encodable, Sendable {}

private struct PassRefreshResult: Decodable, Sendable {
    let passId: String
    enum CodingKeys: String, CodingKey {
        case passId = "pass_id"
    }
}

// MARK: - AppLog shim (avoids importing Core for a log call)

/// Thin shim so this file compiles without a hard Core import.
/// The real `AppLog` lives in `Core/Logging/AppLog.swift`.
private enum AppLog {
    static func debug(_ msg: String) {
        #if DEBUG
        print("[DEBUG] \(msg)")
        #endif
    }
    static func error(_ msg: String) {
        print("[ERROR] \(msg)")
    }
}
