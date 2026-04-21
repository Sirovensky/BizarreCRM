import Foundation

// MARK: - CashSession

/// Canonical domain model for a POS cash-register session (drawer open → close).
/// Wire DTO: Networking/Endpoints/CashRegisterEndpoints.swift (CashSessionDTO).
/// Server endpoints are currently stubbed (POS-SESSIONS-001); local state
/// is the authority until the endpoint ships.
public struct CashSession: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let openedByUserId: Int64?
    public let closedByUserId: Int64?
    public let status: CashSessionStatus
    public let openingFloatCents: Cents
    public let closingCountedCents: Cents?
    public let expectedCents: Cents?
    public let varianceCents: Cents?
    public let notes: String?
    public let openedAt: Date
    public let closedAt: Date?

    public init(
        id: Int64,
        openedByUserId: Int64? = nil,
        closedByUserId: Int64? = nil,
        status: CashSessionStatus = .open,
        openingFloatCents: Cents = 0,
        closingCountedCents: Cents? = nil,
        expectedCents: Cents? = nil,
        varianceCents: Cents? = nil,
        notes: String? = nil,
        openedAt: Date,
        closedAt: Date? = nil
    ) {
        self.id = id
        self.openedByUserId = openedByUserId
        self.closedByUserId = closedByUserId
        self.status = status
        self.openingFloatCents = openingFloatCents
        self.closingCountedCents = closingCountedCents
        self.expectedCents = expectedCents
        self.varianceCents = varianceCents
        self.notes = notes
        self.openedAt = openedAt
        self.closedAt = closedAt
    }

    public var isOpen: Bool { status == .open }

    /// Positive = over; negative = short.
    public var varianceDescription: String {
        guard let v = varianceCents else { return "—" }
        let abs = Swift.abs(v)
        let dollars = String(format: "%.2f", Double(abs) / 100)
        return v >= 0 ? "+$\(dollars)" : "-$\(dollars)"
    }
}

// MARK: - CashSessionStatus

public enum CashSessionStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case closed
    case reconciled

    public var displayName: String {
        switch self {
        case .open:         return "Open"
        case .closed:       return "Closed"
        case .reconciled:   return "Reconciled"
        }
    }
}
