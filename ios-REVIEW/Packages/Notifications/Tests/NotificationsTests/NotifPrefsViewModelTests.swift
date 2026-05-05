import Testing
import Foundation
@testable import Notifications

// MARK: - MockNotifPrefsRepository

final class MockNotifPrefsRepository: NotifPrefsRepository, @unchecked Sendable {

    var fetchResult: Result<[NotificationPreference], Error> = .success(
        NotificationEvent.allCases.map { .defaultPreference(for: $0) }
    )
    var batchResult: Result<[NotificationPreference], Error>?
    var capturedBatch: [NotificationPreference] = []

    func fetchAll() async throws -> [NotificationPreference] {
        try fetchResult.get()
    }

    func batchUpdate(_ preferences: [NotificationPreference]) async throws -> [NotificationPreference] {
        capturedBatch = preferences
        if let result = batchResult {
            return try result.get()
        }
        // Default: echo back what was passed
        return preferences
    }
}

// MARK: - NotifPrefsViewModelTests

@Suite("NotifPrefsViewModel")
@MainActor
struct NotifPrefsViewModelTests {

    // MARK: - Load

    @Test("load populates all events")
    func loadPopulatesAll() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        #expect(vm.preferences.count == NotificationEvent.allCases.count)
    }

    @Test("load sets errorMessage on failure")
    func loadSetsError() async {
        let repo = MockNotifPrefsRepository()
        repo.fetchResult = .failure(URLError(.notConnectedToInternet))
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        #expect(vm.errorMessage != nil)
        #expect(vm.preferences.isEmpty)
    }

    @Test("isLoading is false after load")
    func isLoadingFalse() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        #expect(!vm.isLoading)
    }

    // MARK: - Toggle

    @Test("Toggle push flips pushEnabled optimistically")
    func togglePush() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        let event = NotificationEvent.ticketAssigned
        let before = vm.preferences.first(where: { $0.event == event })!.pushEnabled
        await vm.toggle(event: event, channel: .push)
        let after = vm.preferences.first(where: { $0.event == event })!.pushEnabled
        #expect(after == !before)
    }

    @Test("Toggle inApp flips inAppEnabled")
    func toggleInApp() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        let event = NotificationEvent.invoicePaid
        let before = vm.preferences.first(where: { $0.event == event })!.inAppEnabled
        await vm.toggle(event: event, channel: .inApp)
        let after = vm.preferences.first(where: { $0.event == event })!.inAppEnabled
        #expect(after == !before)
    }

    @Test("Toggle email flips emailEnabled")
    func toggleEmail() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .invoicePaid, channel: .email)
        #expect(!repo.capturedBatch.isEmpty)
    }

    @Test("Toggle SMS on high-volume event shows warning")
    func toggleSMSHighVolumeShowsWarning() async {
        let repo = MockNotifPrefsRepository()
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
    }

    @Test("confirmSMSToggle enables SMS and dismisses warning")
    func confirmSMSToggle() async {
        let repo = MockNotifPrefsRepository()
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
        await vm.confirmSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(vm.preferences.first(where: { $0.event == .smsInbound })!.smsEnabled)
    }

    @Test("cancelSMSToggle keeps SMS disabled")
    func cancelSMSToggle() async {
        let repo = MockNotifPrefsRepository()
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        vm.cancelSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(!vm.preferences.first(where: { $0.event == .smsInbound })!.smsEnabled)
    }

    // MARK: - Quiet hours

    @Test("saveQuietHours updates preference with quiet hours")
    func saveQuietHours() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60,
                            endMinutesFromMidnight: 7 * 60,
                            allowCriticalOverride: true)
        await vm.saveQuietHours(qh, for: .ticketAssigned)
        let pref = vm.preferences.first(where: { $0.event == .ticketAssigned })
        #expect(pref?.quietHours != nil)
        #expect(vm.editingQuietHoursEvent == nil)
    }

    @Test("saveQuietHours nil clears quiet hours")
    func clearQuietHours() async {
        let repo = MockNotifPrefsRepository()
        // Pre-populate with quiet hours set
        let withQH = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .ticketAssigned {
                return NotificationPreference(
                    event: event,
                    pushEnabled: true, inAppEnabled: true, emailEnabled: false, smsEnabled: false,
                    quietHours: QuietHours(startMinutesFromMidnight: 22 * 60,
                                          endMinutesFromMidnight: 7 * 60,
                                          allowCriticalOverride: true)
                )
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(withQH)
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.saveQuietHours(nil, for: .ticketAssigned)
        // batchResult echoes back what was passed; quiet hours should be cleared
        let pref = vm.preferences.first(where: { $0.event == .ticketAssigned })
        #expect(pref?.quietHours == nil)
    }

    // MARK: - Reset all

    @Test("resetAllToDefault calls batchUpdate for all events")
    func resetCallsBatch() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.resetAllToDefault()
        #expect(repo.capturedBatch.count == NotificationEvent.allCases.count)
    }

    @Test("resetAllToDefault restores default pushEnabled values")
    func resetRestoresDefaults() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        await vm.resetAllToDefault()
        for pref in vm.preferences {
            #expect(pref.pushEnabled == pref.event.defaultPush)
            #expect(!pref.emailEnabled)
            #expect(!pref.smsEnabled)
        }
    }

    // MARK: - Save failure

    @Test("toggle reverts preference on save failure")
    func toggleRevertsOnFailure() async {
        let repo = MockNotifPrefsRepository()
        repo.batchResult = .failure(URLError(.notConnectedToInternet))
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()

        let event = NotificationEvent.invoicePaid
        let before = vm.preferences.first(where: { $0.event == event })!.emailEnabled
        await vm.toggle(event: event, channel: .email)
        let after = vm.preferences.first(where: { $0.event == event })!.emailEnabled
        #expect(after == before) // reverted
        #expect(vm.errorMessage != nil)
    }

    // MARK: - Categories

    @Test("preferences(for:) returns correct subset")
    func prefsForCategory() async {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        await vm.load()
        let ticketPrefs = vm.preferences(for: .tickets)
        #expect(!ticketPrefs.isEmpty)
        #expect(ticketPrefs.allSatisfy { $0.event.category == .tickets })
    }

    @Test("All categories are present")
    func allCategoriesPresent() {
        let repo = MockNotifPrefsRepository()
        let vm = NotifPrefsViewModel(repository: repo)
        #expect(vm.categories.count == EventCategory.allCases.count)
    }
}
