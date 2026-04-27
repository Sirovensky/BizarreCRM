import Foundation
import Core
import Networking
import Persistence

// MARK: - SignatureRoute

/// §16.26 — Output of `SignatureRouter.route(...)`.
///
/// Determines where a payment signature is captured after BlockChyp approval.
/// Terminal is always preferred; on-phone is the fallback.
public enum SignatureRoute: Equatable, Sendable {
    /// Capture signature on the paired BlockChyp terminal (customer signs on hardware).
    case terminal(name: String)
    /// Capture signature on the iOS device screen via `PKCanvasView` sheet.
    case onPhone
}

// MARK: - SignatureRouter

/// §16.26 — Pure routing logic for post-approval signature capture.
///
/// **Routing rules** (terminal preferred):
/// 1. No terminal paired in Keychain → `.onPhone`
/// 2. Terminal heartbeat failed or `sigRequired == false` → `.onPhone`
/// 3. `process-payment` response has no `terminalName` → `.onPhone`
/// 4. User explicitly selected "Sign on phone" → `.onPhone`
/// 5. All checks pass → `.terminal(name:)`
///
/// This is a pure struct with no SwiftUI dependencies.
/// It does not perform network calls — it evaluates the conditions
/// supplied by `PosTenderViewModel` after the payment call returns.
///
/// Payment math is NOT here. This struct only decides WHERE the signature
/// is captured after the payment result arrives.
public struct SignatureRouter: Sendable {

    // MARK: - Init

    public init() {}

    // MARK: - Route decision

    /// Evaluate the routing conditions and return a `SignatureRoute`.
    ///
    /// - Parameters:
    ///   - sigRequired:        Whether the payment result requires a signature.
    ///   - terminalName:       Terminal name from the `process-payment` response. `nil` = cloud relay, no terminal.
    ///   - terminalAvailable:  Whether the heartbeat check passed within the 3s timeout.
    ///   - userRequestedPhone: `true` if the cashier tapped "Sign on phone" in the overflow menu.
    /// - Returns: Where to capture the signature.
    public func route(
        sigRequired: Bool,
        terminalName: String?,
        terminalAvailable: Bool,
        userRequestedPhone: Bool = false
    ) -> SignatureRoute {
        // Short-circuit: signature not required.
        guard sigRequired else { return .onPhone }
        // Cashier explicitly wants on-phone capture.
        if userRequestedPhone { return .onPhone }
        // No terminal name in the payment response.
        guard let name = terminalName, !name.isEmpty else { return .onPhone }
        // Terminal heartbeat failed.
        guard terminalAvailable else { return .onPhone }
        // All checks pass → terminal.
        return .terminal(name: name)
    }

    // MARK: - Terminal pairing check

    /// Returns `true` if a terminal pairing is stored in the Keychain.
    ///
    /// Used before making the heartbeat call so we skip the network round-trip
    /// entirely when no terminal has ever been paired.
    public func isTerminalPaired() -> Bool {
        PairingKeychainStore.load(key: "com.bizarrecrm.pos.terminal") != nil
    }
}

// MARK: - BlockChypCaptureSignatureRequest

/// Request body for `POST /api/v1/blockchyp/capture-signature`.
///
/// Server: `packages/server/src/routes/blockchyp.routes.ts`.
/// Instructs the paired terminal to display a signature prompt.
public struct BlockChypCaptureSignatureRequest: Encodable, Sendable {
    /// Name of the paired terminal (from `process-payment` response).
    public let terminalName: String
    /// Signature image format (always "PNG" per server contract).
    public let sigFormat: String
    /// Signature canvas width in pixels (400 per server contract).
    public let sigWidth: Int

    public init(terminalName: String, sigFormat: String = "PNG", sigWidth: Int = 400) {
        self.terminalName = terminalName
        self.sigFormat    = sigFormat
        self.sigWidth     = sigWidth
    }

    enum CodingKeys: String, CodingKey {
        case terminalName = "terminalName"
        case sigFormat    = "sigFormat"
        case sigWidth     = "sigWidth"
    }
}

/// Response from `POST /api/v1/blockchyp/capture-signature`.
public struct BlockChypCaptureSignatureResponse: Decodable, Sendable {
    /// Base-64 encoded PNG of the signature drawn on the terminal.
    public let sig: String?
    public let success: Bool

    enum CodingKeys: String, CodingKey {
        case sig, success
    }
}

// MARK: - SignatureCapture event types

public extension PosAuditEntry.EventType {
    /// Emitted when a signature is captured (terminal or on-phone).
    static let signatureCaptured = "signature_captured"
}

// MARK: - TerminalSignatureFetcher

/// §16.26 — Polls `POST /api/v1/blockchyp/capture-signature` with a 30-second
/// total timeout and 2-second retry interval until the terminal responds.
///
/// SCAFFOLD: BlockChyp math blocked per hard rule. The network call is wired
/// through `APIClient+BlockChyp.swift` (Agent 2 owns the SDK wiring).
/// This class performs the polling loop and delivers the base-64 PNG.
@MainActor
public final class TerminalSignatureFetcher {

    // MARK: - State

    public enum FetchState: Equatable {
        case idle
        case waiting          // Spinner: "Customer signing on terminal…"
        case received(sigBase64: String)
        case timedOut
        case error(String)
    }

    public private(set) var state: FetchState = .idle

    // MARK: - Configuration

    private let maxWait: Duration    = .seconds(30)
    private let retryInterval: Duration = .seconds(2)

    // MARK: - Dependencies

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Fetch

    /// Start polling for the terminal signature.
    /// Calls `onComplete` with the result when the terminal responds or timeout fires.
    ///
    /// **SCAFFOLD** — actual `capture-signature` call deferred until BlockChyp
    /// SDK wiring (Agent 2). Emits `.timedOut` after `maxWait` as a safe default.
    public func fetch(
        terminalName: String,
        invoiceId: Int64,
        actorId: Int64
    ) async {
        state = .waiting
        AppLog.pos.info("TerminalSignatureFetcher: waiting for terminal=\(terminalName, privacy: .public)")

        let deadline = ContinuousClock.now + maxWait
        let req = BlockChypCaptureSignatureRequest(terminalName: terminalName)

        while ContinuousClock.now < deadline {
            guard !Task.isCancelled else {
                state = .error("Cancelled")
                return
            }

            do {
                // SCAFFOLD — route: POST /api/v1/blockchyp/capture-signature
                // Uncomment when Agent 2 ships the BlockChyp SDK wiring:
                // let resp = try await api.blockChypCaptureSignature(req)
                // if let sig = resp.sig, resp.success {
                //     state = .received(sigBase64: sig)
                //     await logCapture(method: "terminal", invoiceId: invoiceId, actorId: actorId)
                //     return
                // }
                _ = req // suppress unused warning until real call
                throw APITransportError.httpStatus(501, message: "BLOCKCHYP-CAPTURE-001 — pending SDK wiring")
            } catch let APITransportError.httpStatus(501, _) {
                // SDK not wired yet — fall through to timeout.
                state = .timedOut
                AppLog.pos.warning("TerminalSignatureFetcher: capture-signature not yet wired (501)")
                return
            } catch {
                // Retriable network error — wait and retry.
                AppLog.pos.error("TerminalSignatureFetcher: retryable error — \(error.localizedDescription, privacy: .public)")
            }

            try? await Task.sleep(for: retryInterval)
        }

        // Timeout path.
        state = .timedOut
        AppLog.pos.warning("TerminalSignatureFetcher: timed out after 30s, terminal=\(terminalName, privacy: .public)")
    }

    // MARK: - Audit

    private func logCapture(method: String, invoiceId: Int64, actorId: Int64) async {
        try? await PosAuditLogStore.shared.record(
            event: PosAuditEntry.EventType.signatureCaptured,
            cashierId: actorId,
            context: [
                "method":     method,
                "invoice_id": invoiceId
            ]
        )
    }
}

// MARK: - OnPhoneSignatureAudit

/// §16.26 — Records an on-phone signature capture audit event.
///
/// Called by the `SignatureSheet` view after the customer accepts.
public func recordOnPhoneSignatureCapture(invoiceId: Int64, actorId: Int64) async {
    try? await PosAuditLogStore.shared.record(
        event: PosAuditEntry.EventType.signatureCaptured,
        cashierId: actorId,
        context: [
            "method":     "phone",
            "invoice_id": invoiceId
        ]
    )
}
