import XCTest
import Networking
@testable import Loyalty

/// §38 — `LoyaltyWalletViewModel` state-transition tests.
///
/// The PassKit guard (`#if canImport(PassKit) && canImport(UIKit)`) means
/// these tests only compile and run on iOS/iPadOS simulator / device.
/// macOS (`canImport(UIKit)` is false) will skip them cleanly.
#if canImport(PassKit) && canImport(UIKit)
@MainActor
final class LoyaltyWalletViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(customerId: String = "42") -> (LoyaltyWalletViewModel, MockLoyaltyWalletService) {
        let mockAPI = MockLoyaltyAPIClient()
        let service = MockLoyaltyWalletService()
        let vm = LoyaltyWalletViewModel(service: service, customerId: customerId)
        _ = mockAPI // suppress unused warning
        return (vm, service)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isPassInWallet)
    }

    // MARK: - addToWallet success path

    func test_addToWallet_success_transitionsToAddedToWallet() async {
        let (vm, service) = makeVM()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).pkpass")
        service.fetchResult = .success(fakeURL)
        service.addResult = .success(())

        await vm.addToWallet()

        XCTAssertEqual(vm.state, .addedToWallet)
        XCTAssertTrue(vm.isPassInWallet)
    }

    func test_addToWallet_success_setsIsPassInWallet() async {
        let (vm, service) = makeVM()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).pkpass")
        service.fetchResult = .success(fakeURL)
        service.addResult = .success(())

        XCTAssertFalse(vm.isPassInWallet)
        await vm.addToWallet()
        XCTAssertTrue(vm.isPassInWallet)
    }

    // MARK: - addToWallet fetch failure

    func test_addToWallet_fetchFailure_transitionsToFailed() async {
        let (vm, service) = makeVM()
        service.fetchResult = .failure(LoyaltyWalletError.httpStatus(500))

        await vm.addToWallet()

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_addToWallet_fetchFailure_isPassInWalletRemainesFalse() async {
        let (vm, service) = makeVM()
        service.fetchResult = .failure(LoyaltyWalletError.invalidPass)

        await vm.addToWallet()

        XCTAssertFalse(vm.isPassInWallet)
    }

    // MARK: - addToWallet present failure

    func test_addToWallet_addFailure_transitionsToFailed() async {
        let (vm, service) = makeVM()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).pkpass")
        service.fetchResult = .success(fakeURL)
        service.addResult = .failure(LoyaltyWalletError.noRootViewController)

        await vm.addToWallet()

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - refreshPass success

    func test_refreshPass_success_transitionsToReady() async {
        let (vm, service) = makeVM()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("refresh_\(UUID().uuidString).pkpass")
        service.refreshResult = .success(fakeURL)

        await vm.refreshPass(passId: "pass-abc")

        XCTAssertEqual(vm.state, .ready(fakeURL))
    }

    func test_refreshPass_failure_transitionsToFailed() async {
        let (vm, service) = makeVM()
        service.refreshResult = .failure(LoyaltyWalletError.noBaseURL)

        await vm.refreshPass(passId: "pass-abc")

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    // MARK: - reset

    func test_reset_fromFailed_returnToIdle() async {
        let (vm, service) = makeVM()
        service.fetchResult = .failure(LoyaltyWalletError.invalidPass)
        await vm.addToWallet()

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
    }

    func test_reset_fromAddedToWallet_returnToIdle() async {
        let (vm, service) = makeVM()
        let fakeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).pkpass")
        service.fetchResult = .success(fakeURL)
        service.addResult = .success(())
        await vm.addToWallet()

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - State equatability

    func test_stateEquality_idle() {
        XCTAssertEqual(LoyaltyWalletViewModel.WalletState.idle, .idle)
    }

    func test_stateEquality_fetching() {
        XCTAssertEqual(LoyaltyWalletViewModel.WalletState.fetching, .fetching)
    }

    func test_stateEquality_addedToWallet() {
        XCTAssertEqual(LoyaltyWalletViewModel.WalletState.addedToWallet, .addedToWallet)
    }

    func test_stateEquality_failed_sameMessage() {
        XCTAssertEqual(
            LoyaltyWalletViewModel.WalletState.failed("err"),
            .failed("err")
        )
    }

    func test_stateEquality_failed_differentMessage_notEqual() {
        XCTAssertNotEqual(
            LoyaltyWalletViewModel.WalletState.failed("a"),
            .failed("b")
        )
    }

    func test_stateEquality_idleNotEqualFetching() {
        XCTAssertNotEqual(
            LoyaltyWalletViewModel.WalletState.idle,
            .fetching
        )
    }

    // MARK: - Fetch call count

    func test_addToWallet_callsFetchOnce() async {
        let (vm, service) = makeVM()
        service.fetchResult = .failure(LoyaltyWalletError.invalidPass)

        await vm.addToWallet()

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func test_refreshPass_callsRefreshOnce() async {
        let (vm, service) = makeVM()
        let fakeURL = URL(fileURLWithPath: "/tmp/x.pkpass")
        service.refreshResult = .success(fakeURL)

        await vm.refreshPass(passId: "p1")

        XCTAssertEqual(service.refreshCallCount, 1)
    }
}

// MARK: - MockLoyaltyWalletService

final class MockLoyaltyWalletService: LoyaltyWalletServicing, @unchecked Sendable {

    var fetchResult: Result<URL, Error>?
    var addResult: Result<Void, Error>?
    var refreshResult: Result<URL, Error>?

    private(set) var fetchCallCount = 0
    private(set) var addCallCount = 0
    private(set) var refreshCallCount = 0

    func fetchPass(customerId: String) async throws -> URL {
        fetchCallCount += 1
        guard let result = fetchResult else {
            throw LoyaltyWalletError.invalidPass
        }
        return try result.get()
    }

    func addToWallet(from url: URL) async throws {
        addCallCount += 1
        guard let result = addResult else {
            throw LoyaltyWalletError.noRootViewController
        }
        try result.get()
    }

    func refreshPass(passId: String) async throws -> URL {
        refreshCallCount += 1
        guard let result = refreshResult else {
            throw LoyaltyWalletError.noBaseURL
        }
        return try result.get()
    }
}

// MARK: - MockLoyaltyAPIClient

final class MockLoyaltyAPIClient: APIClient, @unchecked Sendable {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.badURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.badURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}

#endif // canImport(PassKit) && canImport(UIKit)
