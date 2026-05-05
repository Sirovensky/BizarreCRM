import Foundation
import Core

/// Card-present charge contract. Concrete adapters (Stripe Terminal,
/// Square Reader SDK, etc.) land behind this protocol so the Pos layer
/// never sees vendor SDK types. §19 wires a real reader; this stub
/// keeps the shape stable.
public protocol CardReader: AnyObject, Sendable {
    func ping() async throws -> Bool
    func charge(cents: Int, reference: String) async throws -> ChargeResult
}

public struct ChargeResult: Sendable {
    public let approved: Bool
    public let authCode: String?
    public let transactionId: String?
    public init(approved: Bool, authCode: String?, transactionId: String?) {
        self.approved = approved
        self.authCode = authCode
        self.transactionId = transactionId
    }
}

/// Simulator fallback — always approves with deterministic mock codes
/// so UI flows can be exercised without a paired reader.
public final class MockCardReader: CardReader, @unchecked Sendable {
    public init() {}
    public func ping() async throws -> Bool { true }
    public func charge(cents: Int, reference: String) async throws -> ChargeResult {
        AppLog.hardware.info("MockCardReader charge \(cents)¢ ref=\(reference, privacy: .public)")
        return ChargeResult(approved: true, authCode: "TEST01", transactionId: UUID().uuidString)
    }
}
