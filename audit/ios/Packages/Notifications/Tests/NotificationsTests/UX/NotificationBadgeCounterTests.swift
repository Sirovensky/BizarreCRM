import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - StubBadgeAPIClient

/// Minimal APIClient stub for badge counter tests. Only `get` is needed —
/// the others are no-ops that satisfy the protocol.
actor StubBadgeAPIClient: APIClient {

    enum Response {
        case count(Int)
        case failure(Error)
    }

    private let responses: [Response]
    private var callIndex: Int = 0

    init(_ responses: [Response]) {
        self.responses = responses
    }

    convenience init(count: Int) {
        self.init([.count(count)])
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        let resp = responses.indices.contains(callIndex) ? responses[callIndex] : responses.last!
        callIndex += 1
        switch resp {
        case .count(let n):
            // The badge counter uses `fetchUnreadNotificationCount()` which
            // calls `get("/api/v1/notifications/unread-count", as: UnreadCountPayload.self)`.
            let payload = UnreadCountPayload(count: n)
            guard let cast = payload as? T else {
                throw APITransportError.decoding("type mismatch in StubBadgeAPIClient")
            }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.notImplemented
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.notImplemented
    }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}

// MARK: - NotificationBadgeCounterTests

@Suite("NotificationBadgeCounter")
@MainActor
struct NotificationBadgeCounterTests {

    // MARK: - Initial state

    @Test("initial unreadCount is 0")
    func initialUnreadCount() {
        let api = StubBadgeAPIClient(count: 0)
        let vm = NotificationBadgeCounterViewModel(api: api)
        #expect(vm.unreadCount == 0)
    }

    @Test("initial isLoading is false")
    func initialIsLoading() {
        let api = StubBadgeAPIClient(count: 0)
        let vm = NotificationBadgeCounterViewModel(api: api)
        #expect(!vm.isLoading)
    }

    @Test("badgeLabel is nil when unreadCount is 0")
    func badgeLabelNilWhenZero() {
        let api = StubBadgeAPIClient(count: 0)
        let vm = NotificationBadgeCounterViewModel(api: api)
        #expect(vm.badgeLabel == nil)
    }

    // MARK: - Fetch and publish count

    @Test("refresh sets unreadCount from API")
    func refreshSetsCount() async {
        let api = StubBadgeAPIClient(count: 5)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.unreadCount == 5)
    }

    @Test("unreadCount is never negative")
    func unreadCountNeverNegative() async {
        let api = StubBadgeAPIClient(count: -3) // defensive — server shouldn't send this
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.unreadCount == 0)
    }

    // MARK: - badgeLabel

    @Test("badgeLabel shows count as string when 1-99")
    func badgeLabelSmallCount() async {
        let api = StubBadgeAPIClient(count: 7)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.badgeLabel == "7")
    }

    @Test("badgeLabel shows 99+ when count is 100")
    func badgeLabelCappedAt100() async {
        let api = StubBadgeAPIClient(count: 100)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.badgeLabel == "99+")
    }

    @Test("badgeLabel shows 99+ when count is 200")
    func badgeLabelCappedAt200() async {
        let api = StubBadgeAPIClient(count: 200)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.badgeLabel == "99+")
    }

    @Test("badgeLabel shows 99 when count is exactly 99")
    func badgeLabelAt99() async {
        let api = StubBadgeAPIClient(count: 99)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.badgeLabel == "99")
    }

    // MARK: - accessibilityLabel

    @Test("accessibilityLabel says no unread when 0")
    func a11yLabelZero() {
        let api = StubBadgeAPIClient(count: 0)
        let vm = NotificationBadgeCounterViewModel(api: api)
        #expect(vm.accessibilityLabel == "No unread notifications")
    }

    @Test("accessibilityLabel singular when 1")
    func a11yLabelOne() async {
        let api = StubBadgeAPIClient(count: 1)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.accessibilityLabel == "1 unread notification")
    }

    @Test("accessibilityLabel plural when more than 1")
    func a11yLabelPlural() async {
        let api = StubBadgeAPIClient(count: 4)
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.accessibilityLabel == "4 unread notifications")
    }

    // MARK: - Error resilience

    @Test("refresh silently ignores network error — count stays unchanged")
    func refreshSilentOnError() async {
        let api = StubBadgeAPIClient([.failure(APITransportError.networkUnavailable)])
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.unreadCount == 0) // stayed at initial 0
    }

    @Test("refresh silently ignores decoding error — count stays unchanged")
    func refreshSilentOnDecodingError() async {
        let api = StubBadgeAPIClient([.failure(APITransportError.decoding("bad json"))])
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.unreadCount == 0)
    }

    // MARK: - Multiple refreshes

    @Test("second refresh updates count")
    func secondRefreshUpdates() async {
        let api = StubBadgeAPIClient([.count(3), .count(10)])
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh()
        #expect(vm.unreadCount == 3)
        await vm.refresh()
        #expect(vm.unreadCount == 10)
    }

    @Test("refresh after error succeeds on next call")
    func refreshAfterError() async {
        let api = StubBadgeAPIClient([.failure(APITransportError.networkUnavailable), .count(5)])
        let vm = NotificationBadgeCounterViewModel(api: api)
        await vm.refresh() // fails
        await vm.refresh() // succeeds
        #expect(vm.unreadCount == 5)
    }

    // MARK: - Stop clears polling

    @Test("stop does not crash")
    func stopDoesNotCrash() {
        let api = StubBadgeAPIClient(count: 0)
        let vm = NotificationBadgeCounterViewModel(api: api)
        vm.stop() // calling before start is safe
    }
}
