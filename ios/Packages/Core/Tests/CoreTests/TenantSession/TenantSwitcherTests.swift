import XCTest
import Combine
@testable import Core

// §79 Multi-Tenant Session management — switcher + events tests

@MainActor
final class TenantSwitcherTests: XCTestCase {

    // MARK: — Fixtures

    private var store: TenantSessionStore!
    private var switcher: TenantSwitcher!
    private var notificationCenter: NotificationCenter!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        store = TenantSessionStore(keychain: InMemoryKeychainStore())
        notificationCenter = NotificationCenter()
        switcher = TenantSwitcher(store: store, notificationCenter: notificationCenter)
        cancellables = []
    }

    override func tearDown() async throws {
        cancellables = nil
        try await super.tearDown()
    }

    private func descriptor(
        id: String,
        name: String = "Tenant",
        url: String = "https://example.com"
    ) -> TenantSessionDescriptor {
        TenantSessionDescriptor(
            id: id,
            displayName: name,
            baseURL: URL(string: url)!
        )
    }

    // MARK: — Initial state

    func test_initialActiveTenant_isNil() {
        XCTAssertNil(switcher.activeTenant)
    }

    // MARK: — switchTo

    func test_switchTo_setsActiveTenant() async throws {
        let t = descriptor(id: "acme")
        try await switcher.switchTo(t)
        XCTAssertEqual(switcher.activeTenant?.id, "acme")
    }

    func test_switchTo_updatesLastUsedAt() async throws {
        let before = Date()
        let t = descriptor(id: "acme")
        try await switcher.switchTo(t)
        let after = Date()

        let active = try XCTUnwrap(switcher.activeTenant)
        XCTAssertGreaterThanOrEqual(active.lastUsedAt, before)
        XCTAssertLessThanOrEqual(active.lastUsedAt, after)
    }

    func test_switchTo_persistsInStore() async throws {
        let t = descriptor(id: "acme")
        try await switcher.switchTo(t)

        let stored = try await store.tenant(id: "acme")
        XCTAssertNotNil(stored, "tenant must be persisted in the store")
    }

    func test_switchTo_emitsCombineEvent() async throws {
        let expectation = expectation(description: "Combine event received")
        var received: TenantSessionEvent?

        switcher.events.sink { event in
            received = event
            expectation.fulfill()
        }
        .store(in: &cancellables)

        try await switcher.switchTo(descriptor(id: "acme"))
        await fulfillment(of: [expectation], timeout: 1.0)

        guard case let .tenantDidChange(_, to) = received else {
            XCTFail("Expected .tenantDidChange, got \(String(describing: received))")
            return
        }
        XCTAssertEqual(to.id, "acme")
    }

    func test_switchTo_emitsNotification() async throws {
        let expectation = expectation(description: "Notification received")
        var userInfo: [AnyHashable: Any]?

        notificationCenter.addObserver(
            forName: .tenantSessionDidChange,
            object: nil,
            queue: .main
        ) { note in
            userInfo = note.userInfo
            expectation.fulfill()
        }

        try await switcher.switchTo(descriptor(id: "beta"))
        await fulfillment(of: [expectation], timeout: 1.0)

        let current = userInfo?[TenantSessionNotificationKey.currentTenant] as? TenantSessionDescriptor
        XCTAssertEqual(current?.id, "beta")
    }

    func test_switchTo_previousTenantPopulatedOnSecondSwitch() async throws {
        try await switcher.switchTo(descriptor(id: "first"))

        let expectation = expectation(description: "second switch event")
        var received: TenantSessionEvent?

        switcher.events.sink { event in
            received = event
            expectation.fulfill()
        }
        .store(in: &cancellables)

        try await switcher.switchTo(descriptor(id: "second"))
        await fulfillment(of: [expectation], timeout: 1.0)

        guard case let .tenantDidChange(from, to) = received else {
            XCTFail("Expected .tenantDidChange"); return
        }
        XCTAssertEqual(from?.id, "first")
        XCTAssertEqual(to.id, "second")
    }

    // MARK: — clearActive

    func test_clearActive_nilsActiveTenant() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))
        switcher.clearActive()
        XCTAssertNil(switcher.activeTenant)
    }

    func test_clearActive_emitsCombineSessionCleared() async throws {
        let expectation = expectation(description: "session cleared event")
        var received: TenantSessionEvent?

        switcher.events.sink { event in
            received = event
            expectation.fulfill()
        }
        .store(in: &cancellables)

        switcher.clearActive()
        await fulfillment(of: [expectation], timeout: 1.0)

        guard case .sessionCleared = received else {
            XCTFail("Expected .sessionCleared, got \(String(describing: received))")
            return
        }
    }

    func test_clearActive_emitsNotification() async throws {
        let expectation = expectation(description: "cleared notification")

        notificationCenter.addObserver(
            forName: .tenantSessionCleared,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        switcher.clearActive()
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: — removeTenant

    func test_removeTenant_clearsActiveWhenMatchesActiveTenant() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))
        try await switcher.removeTenant(id: "acme")
        XCTAssertNil(switcher.activeTenant)
    }

    func test_removeTenant_doesNotClearActiveForDifferentId() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))
        try await switcher.removeTenant(id: "other")
        XCTAssertEqual(switcher.activeTenant?.id, "acme")
    }

    func test_removeTenant_removesFromStore() async throws {
        try await switcher.switchTo(descriptor(id: "acme"))
        try await switcher.removeTenant(id: "acme")

        let stored = try await store.tenant(id: "acme")
        XCTAssertNil(stored)
    }
}
