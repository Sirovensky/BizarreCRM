import XCTest
@testable import Settings

// MARK: - §19.2 Active sessions tests

final class ActiveSessionsViewModelTests: XCTestCase {

    private var api: MockAPIClient!
    private var vm: ActiveSessionsViewModel!

    override func setUp() {
        super.setUp()
        api = MockAPIClient()
        vm = ActiveSessionsViewModel(api: api)
    }

    // MARK: - Load

    func test_load_populatesSessions() async throws {
        api.stubbedGet = { _ in
            """
            [
                {
                    "id": "sess-1",
                    "device_name": "iPhone 16 Pro",
                    "device_model": "iPhone",
                    "ip_address": "192.168.1.1",
                    "location": "New York, NY",
                    "last_seen_at": "2026-04-26T10:00:00.000Z",
                    "is_current_device": true
                },
                {
                    "id": "sess-2",
                    "device_name": "iPad Pro 13\"",
                    "device_model": "iPad",
                    "ip_address": "192.168.1.2",
                    "location": null,
                    "last_seen_at": "2026-04-25T08:00:00.000Z",
                    "is_current_device": false
                }
            ]
            """.data(using: .utf8)!
        }

        await vm.load()

        XCTAssertEqual(vm.sessions.count, 2)
        XCTAssertEqual(vm.sessions[0].id, "sess-1")
        XCTAssertTrue(vm.sessions[0].isCurrentDevice)
        XCTAssertEqual(vm.sessions[1].id, "sess-2")
        XCTAssertFalse(vm.sessions[1].isCurrentDevice)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsErrorOnFailure() async {
        api.stubbedError = URLError(.timedOut)

        await vm.load()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.sessions.isEmpty)
    }

    // MARK: - Revoke

    func test_requestRevoke_setsSessionToRevoke() {
        let session = ActiveSession(
            id: "sess-1",
            deviceName: "iPhone",
            deviceModel: "iPhone",
            ipAddress: "1.2.3.4",
            location: nil,
            lastSeenAt: Date(),
            isCurrentDevice: false
        )

        vm.requestRevoke(session)

        XCTAssertEqual(vm.sessionToRevoke?.id, "sess-1")
        XCTAssertTrue(vm.showRevokeConfirm)
    }

    func test_confirmRevoke_removesSession() async throws {
        let session = ActiveSession(
            id: "sess-2",
            deviceName: "iPad",
            deviceModel: "iPad",
            ipAddress: "1.2.3.5",
            location: nil,
            lastSeenAt: Date(),
            isCurrentDevice: false
        )
        vm.sessions = [session]
        vm.sessionToRevoke = session
        api.stubbedDelete = { _ in }

        await vm.confirmRevoke()

        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNil(vm.sessionToRevoke)
    }

    func test_revokeAll_keepsCurrentDevice() async {
        let current = ActiveSession(id: "c", deviceName: "My iPhone", deviceModel: "iPhone", ipAddress: "1.1.1.1", location: nil, lastSeenAt: Date(), isCurrentDevice: true)
        let other   = ActiveSession(id: "o", deviceName: "iPad", deviceModel: "iPad", ipAddress: "1.1.1.2", location: nil, lastSeenAt: Date(), isCurrentDevice: false)
        vm.sessions = [current, other]
        api.stubbedDelete = { _ in }

        await vm.revokeAll()

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.id, "c")
    }
}
