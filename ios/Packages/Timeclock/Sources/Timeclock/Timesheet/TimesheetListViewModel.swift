import Foundation
import Observation
import Networking
import Core

// MARK: - TimesheetListViewModel
//
// Loads GET /api/v1/timesheet/clock-entries and PATCH /api/v1/timesheet/clock-entries/:id.
//
// Manager approval state is embedded in the read flow: non-manager callers
// receive only their own entries (server enforces). Managers can pass
// userId to filter by employee.
//
// Edits go to PATCH /api/v1/timesheet/clock-entries/:id and require a
// non-empty `reason` field (audit policy, enforced server-side as well).

@MainActor
@Observable
public final class TimesheetListViewModel {

    // MARK: - State

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public enum EditState: Sendable, Equatable {
        case idle, saving, saved, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var editState: EditState = .idle
    public private(set) var entries: [ClockEntry] = []

    /// Optional employee-id filter (managers only; nil = self).
    public var filterUserId: Int64? = nil
    /// ISO-8601 date ("yyyy-MM-dd"). Nil = no lower bound.
    public var fromDate: String? = nil
    /// ISO-8601 date ("yyyy-MM-dd"). Nil = no upper bound.
    public var toDate: String? = nil

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var userIdProvider: @Sendable () async -> Int64

    // MARK: - Init

    public init(
        api: APIClient,
        userIdProvider: @escaping @Sendable () async -> Int64 = { 0 }
    ) {
        self.api = api
        self.userIdProvider = userIdProvider
    }

    // MARK: - Load

    public func load() async {
        loadState = .loading
        let userId = filterUserId ?? (await userIdProvider())
        let resolvedUserId = userId > 0 ? userId : nil
        do {
            let result = try await api.listClockEntries(
                userId: resolvedUserId,
                fromDate: fromDate,
                toDate: toDate
            )
            entries = result
            loadState = .loaded
        } catch {
            AppLog.ui.error("TimesheetList load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Manager edit

    /// PATCH /api/v1/timesheet/clock-entries/:id
    ///
    /// - Parameters:
    ///   - entryId:  The clock entry to update.
    ///   - clockIn:  New ISO-8601 UTC string, or nil to leave unchanged.
    ///   - clockOut: New ISO-8601 UTC string, or nil to leave unchanged.
    ///   - notes:    Updated notes, or nil to leave unchanged.
    ///   - reason:   Mandatory audit reason (server returns 400 if blank).
    public func editEntry(
        entryId: Int64,
        clockIn: String? = nil,
        clockOut: String? = nil,
        notes: String? = nil,
        reason: String
    ) async {
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            editState = .failed("A reason is required to edit a timesheet entry.")
            return
        }
        editState = .saving
        let edit = ClockEntryEditRequest(
            clockIn: clockIn,
            clockOut: clockOut,
            notes: notes,
            reason: reason
        )
        do {
            let updated = try await api.editClockEntry(entryId: entryId, edit: edit)
            // Immutable update: replace matching entry in the array.
            entries = entries.map { $0.id == updated.id ? updated : $0 }
            editState = .saved
        } catch {
            AppLog.ui.error("TimesheetList edit failed: \(error.localizedDescription, privacy: .public)")
            editState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Computed helpers

    /// Total hours across loaded entries (nil clock-out entries contribute 0).
    public var totalHours: Double {
        entries.reduce(0) { $0 + ($1.totalHours ?? 0) }
    }
}
