import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - NotifPrefsViewModel

/// ViewModel for the per-channel notification preferences screen.
///
/// Groups events by `EventCategory` and exposes per-event toggle actions.
/// Optimistic UI: toggles apply locally, then the full matrix is batch-saved.
/// On server failure, the pre-toggle snapshot is restored.
@MainActor
@Observable
public final class NotifPrefsViewModel {

    // MARK: - Public state

    public private(set) var preferences: [NotificationPreference] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    /// Quiet-hours sheet: nil = closed, non-nil = event being edited.
    public var editingQuietHoursEvent: NotificationEvent?

    /// SMS cost warning alert state.
    public var showSMSCostWarning: Bool = false
    public private(set) var pendingSMSToggle: NotificationPreference?

    // MARK: - Derived state

    public var categories: [EventCategory] { EventCategory.allCases }

    public func preferences(for category: EventCategory) -> [NotificationPreference] {
        preferences.filter { $0.event.category == category }
    }

    // MARK: - Dependencies

    private let repository: any NotifPrefsRepository

    // MARK: - Init

    public init(repository: any NotifPrefsRepository) {
        self.repository = repository
    }

    // MARK: - Load

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            preferences = try await repository.fetchAll()
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: read-only load. View teardown / `.task`
            // re-fire on sheet redisplay cancels the in-flight fetch — that
            // is not an error condition. Painting `errorMessage` would
            // surface a banner the user never triggered.
            return
        } catch {
            AppLog.ui.error("NotifPrefs load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Toggle

    /// Toggle a single channel for an event. Shows SMS cost warning when appropriate.
    public func toggle(event: NotificationEvent, channel: NotificationChannel) async {
        guard let idx = preferences.firstIndex(where: { $0.event == event }) else { return }
        let current = preferences[idx]
        let updated = current.toggling(channel)

        // Guard: warn if enabling SMS on a high-volume event
        if channel == .sms && updated.smsEnabled && event.isHighVolumeForSMS {
            pendingSMSToggle = updated
            showSMSCostWarning = true
            return
        }

        preferences = replacing(preferences, at: idx, with: updated)
        await save([updated])
    }

    /// Called when user confirms the SMS cost warning.
    public func confirmSMSToggle() async {
        guard let pending = pendingSMSToggle,
              let idx = preferences.firstIndex(where: { $0.event == pending.event })
        else {
            showSMSCostWarning = false
            return
        }
        showSMSCostWarning = false
        pendingSMSToggle = nil
        preferences = replacing(preferences, at: idx, with: pending)
        await save([pending])
    }

    public func cancelSMSToggle() {
        showSMSCostWarning = false
        pendingSMSToggle = nil
    }

    // MARK: - Quiet hours

    public func saveQuietHours(_ qh: QuietHours?, for event: NotificationEvent) async {
        guard let idx = preferences.firstIndex(where: { $0.event == event }) else { return }
        let updated = preferences[idx].withQuietHours(qh)
        preferences = replacing(preferences, at: idx, with: updated)
        editingQuietHoursEvent = nil
        await save([updated])
    }

    // MARK: - Reset all

    public func resetAllToDefault() async {
        let defaults = NotificationEvent.allCases.map { NotificationPreference.defaultPreference(for: $0) }
        preferences = defaults
        await save(defaults)
    }

    // MARK: - Private helpers

    /// Batch-save; revert snapshot on failure.
    private func save(_ changed: [NotificationPreference]) async {
        isSaving = true
        defer { isSaving = false }
        let snapshot = preferences
        do {
            preferences = try await repository.batchUpdate(changed)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: write path. Reverting the snapshot AND
            // painting "Couldn't save preferences" on cancellation tempts
            // the user to re-tap the channel toggle — which fires a second
            // PUT /api/v1/notification-preferences/me with a fresh idempotency
            // path. The server then writes duplicate audit log rows
            // (preference_changed × N), and may swap channel state in the
            // server's favour after the cancelled-but-applied save lands.
            // Leave the optimistic state in place; the next legitimate save
            // or load() will reconcile. Server-side idempotency for this
            // endpoint is keyed only on (user, event), so on the rare case
            // the server already committed the request before cancellation
            // the row count stays correct.
            return
        } catch {
            preferences = snapshot
            AppLog.ui.error("NotifPrefs save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Couldn't save preferences. Please try again."
        }
    }

    /// Immutable array replace at index — never mutates the original.
    private func replacing<T>(
        _ array: [T], at index: Int, with element: T
    ) -> [T] {
        var copy = array
        copy[index] = element
        return copy
    }
}
