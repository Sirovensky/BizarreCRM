import Foundation
import Observation
import Core

// MARK: - NotificationMatrixViewModel
//
// §70 Granular Per-Event Notification Matrix — ViewModel
//
// Loads and saves the full event × channel matrix via the existing
// NotifPrefsRepository (backed by GET/PUT /api/v1/notification-preferences/me).
//
// Optimistic UI: toggles apply locally, then batch-saved. On failure the
// pre-toggle snapshot is restored and errorMessage is set.

@MainActor
@Observable
public final class NotificationMatrixViewModel {

    // MARK: - Public state

    /// The current matrix snapshot.
    public private(set) var matrix: NotificationMatrixModel = .defaults
    /// Flat ordered rows (mirrored from matrix.rows for convenience).
    public var preferences: [MatrixRow] { matrix.rows }

    public private(set) var isLoading: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    // MARK: - Alert / sheet state

    /// SMS cost warning alert — set to the pending toggled row.
    public var pendingSMSRow: MatrixRow? = nil
    public var showSMSCostWarning: Bool = false

    /// Quiet-hours sheet — set to the event being edited.
    public var editingQuietHoursEvent: NotificationEvent? = nil

    // MARK: - Private

    /// Snapshot before the last optimistic update — used to revert on failure.
    private var preUpdateSnapshot: NotificationMatrixModel = .defaults
    /// Full original preferences, used to preserve inAppEnabled when saving.
    private var originalPreferences: [NotificationPreference] = []

    private let repository: any NotifPrefsRepository

    // MARK: - Init

    public init(repository: any NotifPrefsRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let prefs = try await repository.fetchAll()
            originalPreferences = prefs
            matrix = NotificationMatrixModel.build(from: prefs)
        } catch {
            AppLog.ui.error("MatrixVM load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Toggle

    /// Toggle a channel for an event.
    /// Shows SMS cost-warning alert on high-volume events before enabling SMS.
    public func toggle(event: NotificationEvent, channel: MatrixChannel) async {
        guard let row = matrix.rows.first(where: { $0.event == event }) else { return }
        let updated = row.toggling(channel)

        // Guard: warn before enabling SMS on high-volume events.
        if channel == .sms && updated.smsEnabled && event.isHighVolumeForSMS {
            pendingSMSRow = updated
            showSMSCostWarning = true
            return
        }

        applyOptimistically(row: updated)
        await batchSave(changed: [updated])
    }

    // MARK: - SMS cost warning confirmation

    /// Called when the user confirms the SMS cost warning.
    public func confirmSMSToggle() async {
        guard let pending = pendingSMSRow else {
            showSMSCostWarning = false
            return
        }
        showSMSCostWarning = false
        pendingSMSRow = nil
        applyOptimistically(row: pending)
        await batchSave(changed: [pending])
    }

    /// Called when the user cancels the SMS cost warning.
    public func cancelSMSToggle() {
        showSMSCostWarning = false
        pendingSMSRow = nil
    }

    // MARK: - Quiet hours

    /// Persist updated quiet hours for a single event.
    public func saveQuietHours(_ qh: QuietHours?, for event: NotificationEvent) async {
        guard let row = matrix.rows.first(where: { $0.event == event }) else { return }
        let updated = row.withQuietHours(qh)
        editingQuietHoursEvent = nil
        applyOptimistically(row: updated)
        await batchSave(changed: [updated])
    }

    // MARK: - Reset all

    /// Reset all preferences to §70 defaults and persist.
    public func resetAllToDefaults() async {
        let defaultModel = NotificationMatrixModel.defaults
        preUpdateSnapshot = matrix
        matrix = defaultModel
        await batchSave(changed: defaultModel.rows)
    }

    // MARK: - Rows by category

    public func rows(for category: MatrixEventCategory) -> [MatrixRow] {
        matrix.rows(for: category)
    }

    // MARK: - Private helpers

    private func applyOptimistically(row: MatrixRow) {
        preUpdateSnapshot = matrix
        matrix = matrix.replacing(row: row)
    }

    private func batchSave(changed: [MatrixRow]) async {
        isSaving = true
        defer { isSaving = false }
        let snapshot = preUpdateSnapshot
        do {
            let toSave = changed.map { $0.toPreference(inAppEnabled: inAppEnabled(for: $0.event)) }
            let refreshed = try await repository.batchUpdate(toSave)
            originalPreferences = refreshed
            // Merge refreshed values back — only the changed events.
            var refreshedMap: [NotificationEvent: NotificationPreference] = [:]
            for pref in refreshed { refreshedMap[pref.event] = pref }
            var updatedRows = matrix.rows
            for (idx, row) in updatedRows.enumerated() {
                if let pref = refreshedMap[row.event] {
                    updatedRows[idx] = MatrixRow(from: pref)
                }
            }
            matrix = NotificationMatrixModel(rows: updatedRows)
        } catch {
            matrix = snapshot
            AppLog.ui.error("MatrixVM save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save preferences. Please try again."
        }
    }

    private func inAppEnabled(for event: NotificationEvent) -> Bool {
        originalPreferences.first(where: { $0.event == event })?.inAppEnabled ?? true
    }
}
