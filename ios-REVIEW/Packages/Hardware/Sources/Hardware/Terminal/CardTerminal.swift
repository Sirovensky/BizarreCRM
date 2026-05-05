import Foundation
import Core

// §17.3 BlockChyp terminal pairing — Phase 5
// Protocol + shared data types.  Concrete HTTP-direct adapter: BlockChypTerminal.swift.
//
// Sovereignty note: BlockChyp calls reach api.blockchyp.com directly — this IS a second
// network peer beyond APIClient.baseURL.  Exception is acceptable: BlockChyp is the
// tenant's payment processor, not a telemetry or analytics SDK.  Raw card data never
// enters this app; the terminal handles PAN/EMV/PIN and returns tokens only (PCI §28).

// MARK: - CardTerminal protocol

/// Thin contract the POS / Charge layer talks to.
/// Concrete adapters (BlockChyp HTTP-direct, mock) slot in behind this interface
/// so POS ViewModels never see vendor-specific types.
public protocol CardTerminal: Sendable {
    /// `true` when terminal credentials are stored in Keychain.
    var isPaired: Bool { get async }
    /// Human-readable terminal name, `nil` when not paired.
    var pairedTerminalName: String? { get async }

    /// Pair this device with a BlockChyp terminal.
    /// The user enters an activation code shown on the terminal + in-app.
    func pair(
        apiCredentials: BlockChypCredentials,
        activationCode: String,
        terminalName: String
    ) async throws

    /// Send a charge to the paired terminal. Returns the approval response.
    func charge(
        amountCents: Int,
        tipCents: Int,
        metadata: [String: String]
    ) async throws -> TerminalTransaction

    /// Return / reverse a previous charge.
    func reverse(
        transactionId: String,
        amountCents: Int
    ) async throws -> TerminalTransaction

    /// Cancel an in-flight charge (user pressed Cancel on the terminal).
    func cancel() async

    /// Ping the terminal for connectivity.
    func ping() async throws -> TerminalPingResult

    /// Unpair — clears locally stored credentials.
    func unpair() async
}

// MARK: - BlockChypCredentials

/// BlockChyp API credentials supplied by the merchant's BlockChyp dashboard.
/// Stored in Keychain; never in UserDefaults or plain-text config.
public struct BlockChypCredentials: Sendable, Codable, Equatable {
    public let apiKey: String
    public let bearerToken: String
    public let signingKey: String

    public init(apiKey: String, bearerToken: String, signingKey: String) {
        self.apiKey = apiKey
        self.bearerToken = bearerToken
        self.signingKey = signingKey
    }
}

// MARK: - TerminalTransaction

/// Result of a successful (or declined) charge or reversal.
/// Money in cents; never `Double`.
public struct TerminalTransaction: Sendable, Codable, Equatable {
    public let id: String
    public let approved: Bool
    public let approvalCode: String?
    public let amountCents: Int
    public let tipCents: Int
    public let cardBrand: String?   // "Visa", "Mastercard", etc.
    public let cardLast4: String?
    public let receiptHtml: String? // for emailing
    public let capturedAt: Date
    public let errorMessage: String?

    public init(
        id: String,
        approved: Bool,
        approvalCode: String?,
        amountCents: Int,
        tipCents: Int,
        cardBrand: String?,
        cardLast4: String?,
        receiptHtml: String?,
        capturedAt: Date,
        errorMessage: String?
    ) {
        self.id = id
        self.approved = approved
        self.approvalCode = approvalCode
        self.amountCents = amountCents
        self.tipCents = tipCents
        self.cardBrand = cardBrand
        self.cardLast4 = cardLast4
        self.receiptHtml = receiptHtml
        self.capturedAt = capturedAt
        self.errorMessage = errorMessage
    }
}

// MARK: - TerminalPingResult

/// Lightweight connectivity check result.
public struct TerminalPingResult: Sendable, Equatable {
    public let ok: Bool
    public let latencyMs: Int

    public init(ok: Bool, latencyMs: Int) {
        self.ok = ok
        self.latencyMs = latencyMs
    }
}

// MARK: - TerminalError

/// Typed errors surfaced by any `CardTerminal` implementation.
/// Maps to user-readable copy; raw BlockChyp codes never shown to cashier.
public enum TerminalError: Error, LocalizedError, Sendable, Equatable {
    case notPaired
    case pairingFailed(String)
    case chargeFailed(String)
    case reversalFailed(String)
    case pingFailed(String)
    case unreachable

    public var errorDescription: String? {
        switch self {
        case .notPaired:
            return "No terminal is paired. Go to Settings → Payment to pair a BlockChyp terminal."
        case .pairingFailed(let detail):
            return "Terminal pairing failed: \(detail)"
        case .chargeFailed(let detail):
            return "Charge failed: \(detail)"
        case .reversalFailed(let detail):
            return "Reversal failed: \(detail)"
        case .pingFailed(let detail):
            return "Terminal ping failed: \(detail)"
        case .unreachable:
            return "Terminal is unreachable. Check that the terminal is powered on and connected to the network."
        }
    }
}
