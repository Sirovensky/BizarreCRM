import Testing
import Foundation
@testable import Notifications

// MARK: - MockNotifPrefsRepositoryForMatrix
//
// Isolated mock — does not share state with mocks in other test files.

private final class MockMatrixRepo: NotifPrefsRepository, @unchecked Sendable {

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
        // Default: echo back full matrix derived from the batch
        return NotificationEvent.allCases.map { event in
            preferences.first(where: { $0.event == event }) ?? .defaultPreference(for: event)
        }
    }
}

// MARK: - NotificationMatrixViewModelTests

@Suite("NotificationMatrixViewModel")
@MainActor
struct NotificationMatrixViewModelTests {

    // MARK: - Load

    @Test("load populates all events")
    func loadPopulatesAll() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        #expect(vm.preferences.count == NotificationEvent.allCases.count)
    }

    @Test("load sets errorMessage on failure")
    func loadFailure() async {
        let repo = MockMatrixRepo()
        repo.fetchResult = .failure(URLError(.notConnectedToInternet))
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        // errorMessage is set
        #expect(vm.errorMessage != nil)
        // matrix still has defaults (not wiped)
        #expect(vm.matrix.rows.count == NotificationEvent.allCases.count)
    }

    @Test("isLoading is false after load")
    func isLoadingFalse() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        #expect(!vm.isLoading)
    }

    // MARK: - Toggle

    @Test("toggle push flips pushEnabled optimistically")
    func togglePush() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        let event = NotificationEvent.ticketAssigned
        let before = vm.matrix.rows.first(where: { $0.event == event })!.pushEnabled
        await vm.toggle(event: event, channel: .push)
        let after = vm.matrix.rows.first(where: { $0.event == event })!.pushEnabled
        #expect(after == !before)
    }

    @Test("toggle email flips emailEnabled")
    func toggleEmail() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        let event = NotificationEvent.invoicePaid
        let before = vm.matrix.rows.first(where: { $0.event == event })!.emailEnabled
        await vm.toggle(event: event, channel: .email)
        let after = vm.matrix.rows.first(where: { $0.event == event })!.emailEnabled
        #expect(after == !before)
    }

    @Test("toggle sms on high-volume event shows SMS cost warning")
    func toggleSMSHighVolume() async {
        let repo = MockMatrixRepo()
        let prefs = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(prefs)
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
        #expect(vm.pendingSMSRow != nil)
    }

    @Test("toggle sms on non-high-volume event does not show warning")
    func toggleSMSLowVolume() async {
        let repo = MockMatrixRepo()
        let prefs = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .invoicePaid {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(prefs)
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .invoicePaid, channel: .sms)
        #expect(!vm.showSMSCostWarning)
    }

    @Test("toggle calls batchUpdate on repository")
    func toggleCallsRepo() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .invoicePaid, channel: .email)
        #expect(!repo.capturedBatch.isEmpty)
    }

    // MARK: - SMS warning flow

    @Test("confirmSMSToggle enables SMS and dismisses warning")
    func confirmSMSToggle() async {
        let repo = MockMatrixRepo()
        let prefs = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(prefs)
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        #expect(vm.showSMSCostWarning)
        await vm.confirmSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(vm.pendingSMSRow == nil)
        let row = vm.matrix.rows.first(where: { $0.event == .smsInbound })!
        #expect(row.smsEnabled)
    }

    @Test("cancelSMSToggle dismisses warning without enabling SMS")
    func cancelSMSToggle() async {
        let repo = MockMatrixRepo()
        let prefs = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .smsInbound {
                return NotificationPreference(event: event, pushEnabled: true,
                                              inAppEnabled: true, emailEnabled: false, smsEnabled: false)
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(prefs)
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .smsInbound, channel: .sms)
        vm.cancelSMSToggle()
        #expect(!vm.showSMSCostWarning)
        #expect(vm.pendingSMSRow == nil)
        let row = vm.matrix.rows.first(where: { $0.event == .smsInbound })!
        #expect(!row.smsEnabled)
    }

    // MARK: - Quiet hours

    @Test("saveQuietHours updates row and dismisses sheet")
    func saveQuietHours() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        vm.editingQuietHoursEvent = .ticketAssigned
        await vm.saveQuietHours(qh, for: .ticketAssigned)
        let row = vm.matrix.rows.first(where: { $0.event == .ticketAssigned })
        #expect(row?.quietHours != nil)
        #expect(vm.editingQuietHoursEvent == nil)
    }

    @Test("saveQuietHours nil clears quiet hours")
    func clearQuietHours() async {
        let repo = MockMatrixRepo()
        let prefsWithQH = NotificationEvent.allCases.map { event -> NotificationPreference in
            if event == .ticketAssigned {
                return NotificationPreference(
                    event: event,
                    pushEnabled: true, inAppEnabled: true, emailEnabled: false, smsEnabled: false,
                    quietHours: QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
                )
            }
            return .defaultPreference(for: event)
        }
        repo.fetchResult = .success(prefsWithQH)
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.saveQuietHours(nil, for: .ticketAssigned)
        let row = vm.matrix.rows.first(where: { $0.event == .ticketAssigned })
        #expect(row?.quietHours == nil)
    }

    // MARK: - Reset all

    @Test("resetAllToDefaults calls batchUpdate for all events")
    func resetCallsRepo() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.resetAllToDefaults()
        #expect(repo.capturedBatch.count == NotificationEvent.allCases.count)
    }

    @Test("resetAllToDefaults restores default push values")
    func resetRestoresDefaults() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        // First enable everything
        await vm.resetAllToDefaults()
        for row in vm.matrix.rows {
            #expect(row.pushEnabled == row.event.defaultPush)
            #expect(!row.emailEnabled)
            #expect(!row.smsEnabled)
        }
    }

    // MARK: - Save failure (revert)

    @Test("toggle reverts optimistic change on save failure")
    func toggleRevertsOnFailure() async {
        let repo = MockMatrixRepo()
        repo.batchResult = .failure(URLError(.notConnectedToInternet))
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        let event = NotificationEvent.invoicePaid
        let before = vm.matrix.rows.first(where: { $0.event == event })!.emailEnabled
        await vm.toggle(event: event, channel: .email)
        let after = vm.matrix.rows.first(where: { $0.event == event })!.emailEnabled
        #expect(after == before) // reverted
        #expect(vm.errorMessage != nil)
    }

    // MARK: - rows(for:)

    @Test("rows(for:) returns only rows for that category")
    func rowsForCategory() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        let ticketRows = vm.rows(for: .tickets)
        #expect(!ticketRows.isEmpty)
        #expect(ticketRows.allSatisfy { $0.category == .tickets })
    }

    // MARK: - isSaving

    @Test("isSaving is false after successful save")
    func isSavingFalseAfterSave() async {
        let repo = MockMatrixRepo()
        let vm = NotificationMatrixViewModel(repository: repo)
        await vm.load()
        await vm.toggle(event: .invoicePaid, channel: .email)
        #expect(!vm.isSaving)
    }
}

// MARK: - ChannelTestActionTests

@Suite("ChannelTestAction")
struct ChannelTestActionTests {

    @Test("isRouteAvailable is false — no test route on server yet")
    func routeUnavailable() {
        #expect(ChannelTestAction.isRouteAvailable == false)
    }

    @Test("send returns unavailable for all channels when route not available")
    func sendReturnsUnavailable() async {
        for channel in MatrixChannel.allCases {
            let result = await ChannelTestAction.send(channel: channel, event: .invoicePaid)
            #expect(result == .unavailable)
        }
    }

    @Test("ChannelTestResult equality")
    func resultEquality() {
        #expect(ChannelTestResult.sent == .sent)
        #expect(ChannelTestResult.unavailable == .unavailable)
        #expect(ChannelTestResult.failed("error") == .failed("error"))
        #expect(ChannelTestResult.sent != .unavailable)
    }
}
