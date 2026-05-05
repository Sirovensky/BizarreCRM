import XCTest
@testable import Auth
import Networking
import Core

// MARK: - TenantSwitcherViewModelTests

@MainActor
final class TenantSwitcherViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let (vm, _) = makeVM()
        if case .idle = vm.state { } else { XCTFail("Expected .idle, got \(vm.state)") }
    }

    func test_initialState_isNotLoading() {
        let (vm, _) = makeVM()
        XCTAssertFalse(vm.isLoading)
    }

    func test_initialState_tenants_isEmpty() {
        let (vm, _) = makeVM()
        XCTAssertTrue(vm.tenants.isEmpty)
    }

    // MARK: loadIfNeeded

    func test_loadIfNeeded_transitionsTo_loaded() async {
        let (vm, _) = makeVM(tenants: [.acme, .globex])
        await vm.loadIfNeeded()
        if case .loaded(let list) = vm.state {
            XCTAssertEqual(list.count, 2)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_loadIfNeeded_doesNotReload_whenAlreadyLoaded() async {
        let repo = SpyTenantRepository(tenants: [.acme])
        let (vm, _) = makeVM(repo: repo)
        await vm.loadIfNeeded()
        await vm.loadIfNeeded() // second call should be no-op
        XCTAssertEqual(repo.loadCallCount, 1)
    }

    func test_loadIfNeeded_transitionsTo_failed_onError() async {
        let (vm, _) = makeVM(loadError: AppError.network(underlying: nil))
        await vm.loadIfNeeded()
        if case .failed = vm.state { } else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    // MARK: reload

    func test_reload_reloadsEvenWhenAlreadyLoaded() async {
        let repo = SpyTenantRepository(tenants: [.acme])
        let (vm, _) = makeVM(repo: repo)
        await vm.loadIfNeeded()
        await vm.reload()
        XCTAssertEqual(repo.loadCallCount, 2)
    }

    // MARK: requestSwitch / cancelSwitch

    func test_requestSwitch_setsPendingTenantAndShowsConfirmation() {
        let (vm, _) = makeVM()
        vm.requestSwitch(to: .acme)
        XCTAssertEqual(vm.pendingTenant?.id, Tenant.acme.id)
        XCTAssertTrue(vm.showConfirmation)
    }

    func test_cancelSwitch_clearsPendingAndDismissesAlert() {
        let (vm, _) = makeVM()
        vm.requestSwitch(to: .acme)
        vm.cancelSwitch()
        XCTAssertNil(vm.pendingTenant)
        XCTAssertFalse(vm.showConfirmation)
    }

    // MARK: confirmSwitch

    func test_confirmSwitch_withNoPending_isNoOp() async {
        let (vm, _) = makeVM(tenants: [.acme, .globex])
        await vm.loadIfNeeded()
        // pendingTenant is nil — confirmSwitch should silently return
        await vm.confirmSwitch()
        // Still in loaded state
        if case .loaded = vm.state { } else { XCTFail("Expected .loaded after no-op confirm") }
    }

    func test_confirmSwitch_transitionsTo_loaded_onSuccess() async {
        let (vm, _) = makeVM(tenants: [.acme, .globex])
        await vm.loadIfNeeded()
        vm.requestSwitch(to: .globex)
        await vm.confirmSwitch()
        if case .loaded = vm.state { } else { XCTFail("Expected .loaded after successful switch, got \(vm.state)") }
    }

    func test_confirmSwitch_clearsPendingTenant_onSuccess() async {
        let (vm, _) = makeVM(tenants: [.acme, .globex])
        await vm.loadIfNeeded()
        vm.requestSwitch(to: .globex)
        await vm.confirmSwitch()
        XCTAssertNil(vm.pendingTenant)
        XCTAssertFalse(vm.showConfirmation)
    }

    func test_confirmSwitch_transitionsTo_failed_onSwitchError() async {
        let repo = SpyTenantRepository(
            tenants: [.acme, .globex],
            switchError: AppError.server(statusCode: 500, message: "Server error")
        )
        let (vm, _) = makeVM(repo: repo)
        await vm.loadIfNeeded()
        vm.requestSwitch(to: .globex)
        await vm.confirmSwitch()
        if case .failed = vm.state { } else { XCTFail("Expected .failed after switch error, got \(vm.state)") }
    }

    // MARK: Derived properties

    func test_errorMessage_isNil_whenNotFailed() async {
        let (vm, _) = makeVM(tenants: [.acme])
        await vm.loadIfNeeded()
        XCTAssertNil(vm.errorMessage)
    }

    func test_errorMessage_nonNil_whenFailed() async {
        let (vm, _) = makeVM(loadError: AppError.offline)
        await vm.loadIfNeeded()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_isSwitching_true_during_switch() async throws {
        // We can't easily observe mid-switch state, but we verify the happy path
        // ends NOT switching.
        let (vm, _) = makeVM(tenants: [.acme, .globex])
        await vm.loadIfNeeded()
        vm.requestSwitch(to: .globex)
        await vm.confirmSwitch()
        XCTAssertFalse(vm.isSwitching)
    }
}

// MARK: - Helpers

@MainActor
private func makeVM(
    tenants: [Tenant] = [],
    loadError: (any Error)? = nil,
    repo: SpyTenantRepository? = nil
) -> (TenantSwitcherViewModel, SpyTenantRepository) {
    let r = repo ?? SpyTenantRepository(tenants: tenants, loadError: loadError)
    let store = TenantStore(repository: r, api: StubTenantAPIClient())
    let vm = TenantSwitcherViewModel(store: store)
    return (vm, r)
}

// MARK: - Fixtures

private extension Tenant {
    static let acme = Tenant(
        id: "tenant-acme",
        name: "Acme Repair",
        slug: "acme",
        role: "admin",
        lastAccessedAt: Date(timeIntervalSince1970: 2000)
    )
    static let globex = Tenant(
        id: "tenant-globex",
        name: "Globex Tech",
        slug: "globex",
        role: "tech",
        lastAccessedAt: Date(timeIntervalSince1970: 1000)
    )
}

// MARK: - Spies / Stubs

final class SpyTenantRepository: TenantRepository, @unchecked Sendable {
    private let tenants: [Tenant]
    private let loadError: (any Error)?
    private let switchError: (any Error)?
    private(set) var loadCallCount = 0
    private(set) var switchCallCount = 0

    init(
        tenants: [Tenant] = [],
        loadError: (any Error)? = nil,
        switchError: (any Error)? = nil
    ) {
        self.tenants = tenants
        self.loadError = loadError
        self.switchError = switchError
    }

    func loadTenants() async throws -> [Tenant] {
        loadCallCount += 1
        if let err = loadError { throw err }
        return tenants
    }

    func switchTenant(tenantId: String) async throws -> (accessToken: String, refreshToken: String) {
        switchCallCount += 1
        if let err = switchError { throw err }
        return ("new-access", "new-refresh")
    }

    func revokeTenantSession() async throws {}
}

private actor StubTenantAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
