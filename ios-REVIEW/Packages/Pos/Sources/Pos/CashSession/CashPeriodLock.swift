import Foundation
import Core
import Networking

// MARK: - CashPeriodLock (§39.4 period lock)

/// Represents a reconciled and locked accounting period.
///
/// Once a period is locked, any changes to transactions within that period
/// require a manager override and generate an audit entry. The lock prevents
/// accidental back-dated edits that would unbalance the reconciled totals.
public struct CashPeriodLock: Codable, Identifiable, Sendable, Equatable {

    /// Server-assigned lock ID.
    public let id: Int64

    /// The period being locked.
    public let periodStart: Date
    public let periodEnd: Date

    /// Manager who performed the lock.
    public let lockedByUserId: Int64
    public let lockedByDisplayName: String

    /// When the lock was applied.
    public let lockedAt: Date

    /// Total reconciled revenue for this period (cents).
    public let reconciledRevenueCents: Int

    /// Whether the lock is currently active. A manager override sets this
    /// to `false`, applies the change, then re-locks with a new entry.
    public let isActive: Bool

    /// Optional notes recorded at lock time (e.g. "Approved by Jane").
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case periodStart              = "period_start"
        case periodEnd                = "period_end"
        case lockedByUserId           = "locked_by_user_id"
        case lockedByDisplayName      = "locked_by_display_name"
        case lockedAt                 = "locked_at"
        case reconciledRevenueCents   = "reconciled_revenue_cents"
        case isActive                 = "is_active"
        case notes
    }
}

// MARK: - Lock request

/// Payload sent to lock a period.
public struct CashPeriodLockRequest: Encodable, Sendable {
    public let periodStart: Date
    public let periodEnd: Date
    public let reconciledRevenueCents: Int
    public let notes: String?

    public init(
        periodStart: Date,
        periodEnd: Date,
        reconciledRevenueCents: Int,
        notes: String? = nil
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.reconciledRevenueCents = reconciledRevenueCents
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case periodStart            = "period_start"
        case periodEnd              = "period_end"
        case reconciledRevenueCents = "reconciled_revenue_cents"
        case notes
    }
}

// MARK: - Override request

/// Payload sent when unlocking a locked period (manager override).
public struct CashPeriodUnlockRequest: Encodable, Sendable {
    public let managerPin: String
    public let reason: String

    public init(managerPin: String, reason: String) {
        self.managerPin = managerPin
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case managerPin = "manager_pin"
        case reason
    }
}

// MARK: - CashPeriodLockRepository protocol

/// Repository for managing period locks.
///
/// Network calls go to:
///   `GET  /pos/period-locks`              → list active locks
///   `POST /pos/period-locks`              → create a new lock
///   `POST /pos/period-locks/:id/unlock`   → manager override / unlock
public protocol CashPeriodLockRepository: Sendable {
    func listLocks() async throws -> [CashPeriodLock]
    func lockPeriod(_ request: CashPeriodLockRequest) async throws -> CashPeriodLock
    func unlockPeriod(id: Int64, request: CashPeriodUnlockRequest) async throws
}
