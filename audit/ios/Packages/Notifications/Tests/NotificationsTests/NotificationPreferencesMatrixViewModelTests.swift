import Testing
import Foundation
@testable import Notifications

// MARK: - MockNotificationPreferencesRepository

final class MockNotificationPreferencesRepository: NotificationPreferencesRepository, @unchecked Sendable {

    var fetchResult: Result<[NotificationPreference], Error> = .success(
        NotificationEvent.allCases.map { .defaultPreference(for: $0) }
    )
    var updateResult: ((NotificationPreference) -> Result<NotificationPreference, Error>) = { .success($0) }
    var updatedPreferences: [NotificationPreference] = []

    func fetchAll() async throws -> [NotificationPreference] {
        try fetchResult.get()
    }

    func update(_ preference: NotificationPreference) async throws -> NotificationPreference {
        let result = updateResult(preference)
        if case .success(let pref) = result {
            updatedPreferences.append(pref)
        }
        return try result.get()
    }
}

// MARK: - NotificationPreferencesMatrixViewModelTests

@Suite("NotificationPreferencesMatrixViewModel")
@MainActor
struct NotificationPreferencesMatrixViewModelTests {

    // MARK: - Load

    @Test("Load populates all events from repository")
    func loadPopulatesAll() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        #expect(vm.preferences.count == NotificationEvent.allCases.count)
    }

    @Test("Load sets errorMessage on failure")
    func loadSetsErrorOnFailure() async {
        let repo = MockNotificationPreferencesRepository()
        repo.fetchResult = .failure(URLError(.notConnectedToInternet))
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        #expect(vm.errorMessage != nil)
    }

    @Test("isLoading is false after successful load")
    func isLoadingFalseAfterLoad() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        #expect(!vm.isLoading)
    }

    // MARK: - Toggle

    @Test("Toggle Push flips pushEnabled optimistically")
    func togglePushFlips() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()

        let event = NotificationEvent.ticketAssigned
        let before = vm.preferences.first(where: { $0.event == event })!.pushEnabled
        await vm.toggle(event: event, channel: .push)
        let after = vm.preferences.first(where: { $0.event == event })!.pushEnabled
        #expect(after == !before)
    }

    @Test("Toggle InApp flips inAppEnabled")
    func toggleInAppFlips() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()

        let event = NotificationEvent.invoicePaid
        let before = vm.preferences.first(where: { $0.event == event })!.inAppEnabled
        await vm.toggle(event: event, channel: .inApp)
        let after = vm.preferences.first(where: { $0.event == event })!.inAppEnabled
        #expect(after == !before)
    }

    @Test("Toggle SMS on high-volume event shows warning")
    func toggleSMSHighVolumeShowsWarning() async {
        let repo = MockNotificationPreferencesRepository()
        // Ensure SMS is off for the high-volume event first
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: event.defaultPush, inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()

        // Toggle SMS on a known high-volume event
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
    }

    @Test("ConfirmSMSToggle enables SMS after warning")
    func confirmSMSToggleEnablesSMS() async {
        let repo = MockNotificationPreferencesRepository()
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true, inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
        await vm.confirmSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(vm.preferences.first(where: { $0.event == .smsInbound })!.smsEnabled)
    }

    @Test("CancelSMSToggle dismisses warning without enabling SMS")
    func cancelSMSToggleKeepsOff() async {
        let repo = MockNotificationPreferencesRepository()
        let defaults = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true, inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(defaults)

        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        vm.cancelSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(!vm.preferences.first(where: { $0.event == .smsInbound })!.smsEnabled)
    }

    // MARK: - Reset all

    @Test("ResetAllToDefault calls update for all events")
    func resetAllCallsUpdate() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        await vm.resetAllToDefault()
        #expect(repo.updatedPreferences.count == NotificationEvent.allCases.count)
    }

    @Test("ResetAllToDefault restores default pushEnabled values")
    func resetRestoresDefaults() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        await vm.resetAllToDefault()
        for pref in vm.preferences {
            #expect(pref.pushEnabled == pref.event.defaultPush, "Mismatch for \(pref.event.rawValue)")
            #expect(!pref.emailEnabled, "Email should be off by default for \(pref.event.rawValue)")
            #expect(!pref.smsEnabled, "SMS should be off by default for \(pref.event.rawValue)")
        }
    }

    // MARK: - Persistence

    @Test("Toggle calls repository update with new value")
    func toggleCallsRepoUpdate() async {
        let repo = MockNotificationPreferencesRepository()
        let vm = NotificationPreferencesMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .invoicePaid, channel: .email)
        #expect(!repo.updatedPreferences.isEmpty)
    }
}

// MARK: - NotificationPreferenceTests

@Suite("NotificationPreference immutability")
struct NotificationPreferenceTests {

    @Test("toggling creates new instance, original unchanged")
    func toggleReturnsCopy() {
        let pref = NotificationPreference.defaultPreference(for: .invoicePaid)
        let toggled = pref.toggling(.email)
        #expect(toggled.emailEnabled != pref.emailEnabled)
        #expect(toggled.event == pref.event)
    }

    @Test("withQuietHours returns new instance with quietHours set")
    func withQuietHours() {
        let pref = NotificationPreference.defaultPreference(for: .invoicePaid)
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let updated = pref.withQuietHours(qh)
        #expect(updated.quietHours != nil)
        #expect(pref.quietHours == nil)
    }

    @Test("defaultPreference for ticketAssigned has push on")
    func ticketAssignedDefaultPushOn() {
        let pref = NotificationPreference.defaultPreference(for: .ticketAssigned)
        #expect(pref.pushEnabled)
        #expect(!pref.emailEnabled)
        #expect(!pref.smsEnabled)
    }

    @Test("defaultPreference for newCustomerCreated has push off")
    func newCustomerCreatedDefaultPushOff() {
        let pref = NotificationPreference.defaultPreference(for: .newCustomerCreated)
        #expect(!pref.pushEnabled)
    }
}

// MARK: - NotificationEventTests

@Suite("NotificationEvent")
struct NotificationEventTests {

    @Test("All events have non-empty displayName")
    func allEventsHaveDisplayName() {
        for event in NotificationEvent.allCases {
            #expect(!event.displayName.isEmpty, "Event \(event.rawValue) has empty displayName")
        }
    }

    @Test("All events have a category")
    func allEventsHaveCategory() {
        for event in NotificationEvent.allCases {
            // Just ensure it doesn't crash
            _ = event.category
        }
    }

    @Test("Critical events are marked isCritical")
    func criticalEventsMarked() {
        let criticals: [NotificationEvent] = [.backupFailed, .securityEvent, .outOfStock, .paymentDeclined]
        for event in criticals {
            #expect(event.isCritical, "\(event.rawValue) should be critical")
        }
    }

    @Test("High-volume SMS events flagged")
    func highVolumeEvents() {
        #expect(NotificationEvent.smsInbound.isHighVolumeForSMS)
        #expect(NotificationEvent.ticketStatusChangeAny.isHighVolumeForSMS)
    }

    @Test("ticketAssigned has default push on")
    func ticketAssignedDefaultPush() {
        #expect(NotificationEvent.ticketAssigned.defaultPush)
    }

    @Test("All events have default email off")
    func allEventsDefaultEmailOff() {
        for event in NotificationEvent.allCases {
            #expect(!event.defaultEmail, "\(event.rawValue) should have email off by default")
        }
    }

    @Test("All events have default SMS off")
    func allEventsDefaultSMSOff() {
        for event in NotificationEvent.allCases {
            #expect(!event.defaultSms, "\(event.rawValue) should have SMS off by default")
        }
    }
}

// MARK: - StaffNotificationCategoryExclusionsTests

@Suite("StaffNotificationCategoryExclusions")
struct StaffNotificationCategoryExclusionsTests {

    @Test("Enabling SMS on high-volume event returns warning")
    func smsHighVolumeReturnsWarning() {
        let warning = StaffNotificationCategoryExclusions.checkExclusion(
            event: .smsInbound,
            channel: .sms,
            enabling: true
        )
        #expect(warning != nil)
        #expect(warning?.isHardBlock == false)
    }

    @Test("Disabling SMS never returns warning")
    func disablingSMSNoWarning() {
        let warning = StaffNotificationCategoryExclusions.checkExclusion(
            event: .smsInbound,
            channel: .sms,
            enabling: false
        )
        #expect(warning == nil)
    }

    @Test("Push channel never returns warning")
    func pushNeverWarning() {
        for event in NotificationEvent.allCases {
            let warning = StaffNotificationCategoryExclusions.checkExclusion(
                event: event,
                channel: .push,
                enabling: true
            )
            #expect(warning == nil, "Push toggle on \(event.rawValue) should never warn")
        }
    }

    @Test("InApp channel never returns warning")
    func inAppNeverWarning() {
        for event in NotificationEvent.allCases {
            let warning = StaffNotificationCategoryExclusions.checkExclusion(
                event: event,
                channel: .inApp,
                enabling: true
            )
            #expect(warning == nil)
        }
    }

    @Test("ticketStatusChangeAny email returns warning")
    func ticketStatusAnyEmailWarning() {
        let warning = StaffNotificationCategoryExclusions.checkExclusion(
            event: .ticketStatusChangeAny,
            channel: .email,
            enabling: true
        )
        #expect(warning != nil)
    }
}
