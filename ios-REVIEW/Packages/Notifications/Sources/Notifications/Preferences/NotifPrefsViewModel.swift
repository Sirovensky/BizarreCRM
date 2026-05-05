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
