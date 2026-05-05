import Foundation
import Networking

// MARK: - §14 Timeclock Manager Approval — Models & API extensions
//
// Server routes (grounded in packages/server/src/routes/timesheet.routes.ts):
//
//   GET  /api/v1/timesheet/clock-entries          — list entries (all pending when
//        called by manager with no user_id filter)
//   PATCH /api/v1/timesheet/clock-entries/:id     — manager edit with mandatory
//        `reason`; writes clock_entry_edits + audit row.
//
// There is NO dedicated approve/reject route on the server. Approval is modelled
// client-side as a PATCH that records a standardised reason prefix so history
// views can distinguish approval edits from correction edits. The server's
// `clock_entry_edits` table stores every change with editor_user_id, before/after
// JSON, and reason — that is the approval audit trail.
//
// ApprovalEntry wraps ClockEntry and annotates it with the manager's decision
// while the session is live.  It is value-type (struct) — no mutation.

// MARK: - ApprovalStatus

/// The in-session decision a manager has made for a pending clock entry.
public enum ApprovalStatus: Sendable, Equatable {
    case pending
    case approved
    case rejected(reason: String)
}

// MARK: - ApprovalEntry

/// A pending clock entry decorated with the manager's in-session decision.
/// Immutable — create a new value rather than mutating.
public struct ApprovalEntry: Sendable, Identifiable, Hashable {
    public let entry: ClockEntry
    public let status: ApprovalStatus

    public var id: Int64 { entry.id }

    public init(entry: ClockEntry, status: ApprovalStatus = .pending) {
        self.entry = entry
        self.status = status
    }

    /// Returns a new `ApprovalEntry` with the given status applied.
    public func withStatus(_ newStatus: ApprovalStatus) -> ApprovalEntry {
        ApprovalEntry(entry: entry, status: newStatus)
    }

    public static func == (lhs: ApprovalEntry, rhs: ApprovalEntry) -> Bool {
        lhs.entry == rhs.entry && lhs.status == rhs.status
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entry)
    }
}

// MARK: - EmployeeGroup

/// A manager-visible group of pending entries belonging to one employee.
public struct EmployeeGroup: Sendable, Identifiable {
    public let employeeId: Int64
    /// Display name derived from server response fields when available.
    public let displayName: String
    public let entries: [ApprovalEntry]

    public var id: Int64 { employeeId }

    public var pendingCount: Int { entries.filter { $0.status == .pending }.count }
    public var allApproved: Bool { entries.allSatisfy { $0.status == .approved } }

    public init(employeeId: Int64, displayName: String, entries: [ApprovalEntry]) {
        self.employeeId = employeeId
        self.displayName = displayName
        self.entries = entries
    }

    /// Returns a new group with the given entry replaced by an updated copy.
    public func replacing(_ updated: ApprovalEntry) -> EmployeeGroup {
        let newEntries = entries.map { $0.id == updated.id ? updated : $0 }
        return EmployeeGroup(employeeId: employeeId, displayName: displayName, entries: newEntries)
    }

    /// Returns a new group with all entries set to `.approved`.
    public func approvingAll() -> EmployeeGroup {
        let newEntries = entries.map { $0.withStatus(.approved) }
        return EmployeeGroup(employeeId: employeeId, displayName: displayName, entries: newEntries)
    }
}

// MARK: - ApprovalHistoryEntry

/// One row from clock_entry_edits — who approved/changed what and when.
public struct ApprovalHistoryEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let clockEntryId: Int64
    public let editorUserId: Int64
    public let beforeJson: String
    public let afterJson: String
    public let reason: String
    public let editedAt: String   // ISO-8601

    public init(
        id: Int64,
        clockEntryId: Int64,
        editorUserId: Int64,
        beforeJson: String,
        afterJson: String,
        reason: String,
        editedAt: String
    ) {
        self.id           = id
        self.clockEntryId = clockEntryId
        self.editorUserId = editorUserId
        self.beforeJson   = beforeJson
        self.afterJson    = afterJson
        self.reason       = reason
        self.editedAt     = editedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clockEntryId  = "clock_entry_id"
        case editorUserId  = "editor_user_id"
        case beforeJson    = "before_json"
        case afterJson     = "after_json"
        case reason
        case editedAt      = "edited_at"
    }
}

// MARK: - Approval reason helpers

/// Standardised reason prefixes written to the audit table by the approval VM.
/// History view uses these to distinguish approval actions from corrections.
public enum ApprovalReasonPrefix {
    public static let approved = "[APPROVED]"
    public static let rejected = "[REJECTED]"

    /// Returns `true` when the reason string represents an approval action.
    public static func isApprovalAction(_ reason: String) -> Bool {
        reason.hasPrefix(approved) || reason.hasPrefix(rejected)
    }
}
