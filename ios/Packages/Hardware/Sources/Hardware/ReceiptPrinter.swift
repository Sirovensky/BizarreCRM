import Foundation
import Core

public protocol ReceiptPrinter: AnyObject, Sendable {
    var isConnected: Bool { get }
    func connect() async throws
    func print(_ receipt: Receipt) async throws
    func disconnect()
}

public struct Receipt: Sendable {
    public let header: String
    public let lines: [Line]
    public let footer: String?

    public struct Line: Sendable {
        public let label: String
        public let value: String
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public init(header: String, lines: [Line], footer: String? = nil) {
        self.header = header
        self.lines = lines
        self.footer = footer
    }
}

/// Simulator / "designed for iPad on Mac" fallback — logs but does nothing.
public final class MockPrinter: ReceiptPrinter, @unchecked Sendable {
    public init() {}
    public var isConnected: Bool { true }
    public func connect() async throws {}
    public func print(_ receipt: Receipt) async throws {
        AppLog.hardware.info("MockPrinter: \(receipt.header, privacy: .public) (\(receipt.lines.count) lines)")
    }
    public func disconnect() {}
}

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

public final class MockCardReader: CardReader, @unchecked Sendable {
    public init() {}
    public func ping() async throws -> Bool { true }
    public func charge(cents: Int, reference: String) async throws -> ChargeResult {
        AppLog.hardware.info("MockCardReader charge \(cents)¢ ref=\(reference, privacy: .public)")
        return ChargeResult(approved: true, authCode: "TEST01", transactionId: UUID().uuidString)
    }
}
