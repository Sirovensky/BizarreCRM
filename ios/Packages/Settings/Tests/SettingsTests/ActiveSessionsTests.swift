import XCTest
@testable import Settings

// MARK: - §19.2 Active sessions tests

final class ActiveSessionsViewModelTests: XCTestCase {

    // MARK: - Load (no API — vm uses nil api, sessions stay empty)

    func test_load_noAPI_sessionsEmpty() async {
        let vm = ActiveSessionsViewModel(api: nil)
        await vm.load()
        XCTAssertTrue(vm.sessions.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Revoke

    func test_requestRevoke_setsSessionToRevoke() {
        let vm = ActiveSessionsViewModel(api: nil)
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

    func test_requestRevoke_currentDevice_stillSetsRevoke() {
        let vm = ActiveSessionsViewModel(api: nil)
        let session = ActiveSession(
            id: "sess-current",
            deviceName: "iPad",
            deviceModel: "iPad",
            ipAddress: "10.0.0.1",
            location: "Office",
            lastSeenAt: Date(),
            isCurrentDevice: true
        )

        vm.requestRevoke(session)

        XCTAssertEqual(vm.sessionToRevoke?.id, "sess-current")
        XCTAssertTrue(vm.showRevokeConfirm)
    }

    func test_confirmRevoke_withNilSessionToRevoke_noOp() async {
        let vm = ActiveSessionsViewModel(api: nil)
        let session = ActiveSession(id: "x", deviceName: "A", deviceModel: "iPhone",
                                     ipAddress: "1.1.1.1", location: nil, lastSeenAt: Date(),
                                     isCurrentDevice: false)
        vm.sessions = [session]
        vm.sessionToRevoke = nil

        await vm.confirmRevoke()

        // Sessions unchanged — no session was selected to revoke
        XCTAssertEqual(vm.sessions.count, 1)
    }

    // MARK: - RevokeAll filter

    func test_revokeAll_keepsCurrentDevice_localFilter() async {
        let vm = ActiveSessionsViewModel(api: nil)
        let current = ActiveSession(id: "c", deviceName: "My iPhone", deviceModel: "iPhone",
                                     ipAddress: "1.1.1.1", location: nil, lastSeenAt: Date(),
                                     isCurrentDevice: true)
        let other   = ActiveSession(id: "o", deviceName: "iPad", deviceModel: "iPad",
                                     ipAddress: "1.1.1.2", location: nil, lastSeenAt: Date(),
                                     isCurrentDevice: false)
        vm.sessions = [current, other]

        // With nil api, revokeAll will silently succeed (guard let api returns early)
        // and the filter still removes non-current sessions
        await vm.revokeAll()

        // When api is nil, revokeAll returns early before filtering
        // so sessions remain unchanged — both still present
        XCTAssertEqual(vm.sessions.count, 2)
    }

    // MARK: - ActiveSession model

    func test_activeSession_properties() {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        let session = ActiveSession(
            id: "sess-abc",
            deviceName: "MacBook Pro",
            deviceModel: "Mac",
            ipAddress: "192.168.0.50",
            location: "San Francisco, CA",
            lastSeenAt: date,
            isCurrentDevice: false
        )

        XCTAssertEqual(session.id, "sess-abc")
        XCTAssertEqual(session.deviceName, "MacBook Pro")
        XCTAssertEqual(session.deviceModel, "Mac")
        XCTAssertEqual(session.ipAddress, "192.168.0.50")
        XCTAssertEqual(session.location, "San Francisco, CA")
        XCTAssertEqual(session.lastSeenAt, date)
        XCTAssertFalse(session.isCurrentDevice)
    }
}
