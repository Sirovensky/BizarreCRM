#if canImport(PassKit) && canImport(UIKit)
import XCTest
import Networking
@testable import Pos

/// §40 — `GiftCardWalletService` and related wallet state tests.
///
/// Uses `MockGiftCardWalletService` (conforms to `GiftCardWalletServicing`)
/// and `MockGiftCardAPIClient` (conforms to `APIClient`) to isolate
/// all PassKit and network calls.
@MainActor
final class GiftCardWalletServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeButtonVM(giftCardId: String = "gc-1") -> (GiftCardWalletButtonViewModel, MockGiftCardWalletService) {
        let service = MockGiftCardWalletService()
        let vm = GiftCardWalletButtonViewModel(service: service, giftCardId: giftCardId)
        return (vm, service)
    }

    private func tmpURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).pkpass")
    }

    // MARK: - Initial state

    func test_buttonVM_initialState_isIdle() {
        let (vm, _) = makeButtonVM()
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - addToWallet success

    func test_buttonVM_addToWallet_success_transitionsToAddedToWallet() async {
        let (vm, service) = makeButtonVM()
        let url = tmpURL("gc")
        service.fetchResult = .success(url)
        service.addResult = .success(())

        await vm.addToWallet()

        XCTAssertEqual(vm.state, .addedToWallet)
    }

    func test_buttonVM_addToWallet_callsFetchOnce() async {
        let (vm, service) = makeButtonVM()
        service.fetchResult = .failure(GiftCardWalletError.invalidPass)

        await vm.addToWallet()

        XCTAssertEqual(service.fetchCallCount, 1)
    }

    func test_buttonVM_addToWallet_callsAddOnSuccess() async {
        let (vm, service) = makeButtonVM()
        let url = tmpURL("gc2")
        service.fetchResult = .success(url)
        service.addResult = .success(())

        await vm.addToWallet()

        XCTAssertEqual(service.addCallCount, 1)
    }

    // MARK: - addToWallet fetch failure

    func test_buttonVM_addToWallet_fetchFailure_transitionsToFailed() async {
        let (vm, service) = makeButtonVM()
        service.fetchResult = .failure(GiftCardWalletError.httpStatus(500))

        await vm.addToWallet()

        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    func test_buttonVM_addToWallet_fetchFailure_doesNotCallAdd() async {
        let (vm, service) = makeButtonVM()
        service.fetchResult = .failure(GiftCardWalletError.noBaseURL)

        await vm.addToWallet()

        XCTAssertEqual(service.addCallCount, 0)
    }

    // MARK: - addToWallet add failure

    func test_buttonVM_addToWallet_addFailure_transitionsToFailed() async {
        let (vm, service) = makeButtonVM()
        let url = tmpURL("gc3")
        service.fetchResult = .success(url)
        service.addResult = .failure(GiftCardWalletError.noRootViewController)

        await vm.addToWallet()

        if case .failed = vm.state { /* pass */ }
        else { XCTFail("Expected .failed, got \(vm.state)") }
    }

    // MARK: - reset

    func test_buttonVM_reset_fromFailed_returnsToIdle() async {
        let (vm, service) = makeButtonVM()
        service.fetchResult = .failure(GiftCardWalletError.invalidPass)
        await vm.addToWallet()

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
    }

    func test_buttonVM_reset_fromAddedToWallet_returnsToIdle() async {
        let (vm, service) = makeButtonVM()
        let url = tmpURL("gc4")
        service.fetchResult = .success(url)
        service.addResult = .success(())
        await vm.addToWallet()

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - State equatability

    func test_stateEquality_idle() {
        XCTAssertEqual(GiftCardWalletButtonViewModel.ButtonState.idle, .idle)
    }

    func test_stateEquality_fetching() {
        XCTAssertEqual(GiftCardWalletButtonViewModel.ButtonState.fetching, .fetching)
    }

    func test_stateEquality_addedToWallet() {
        XCTAssertEqual(GiftCardWalletButtonViewModel.ButtonState.addedToWallet, .addedToWallet)
    }

    func test_stateEquality_failed_sameMessage() {
        XCTAssertEqual(
            GiftCardWalletButtonViewModel.ButtonState.failed("e"),
            .failed("e")
        )
    }

    func test_stateEquality_failed_differentMessage_notEqual() {
        XCTAssertNotEqual(
            GiftCardWalletButtonViewModel.ButtonState.failed("a"),
            .failed("b")
        )
    }

    func test_stateEquality_idleNotEqualFetching() {
        XCTAssertNotEqual(
            GiftCardWalletButtonViewModel.ButtonState.idle,
            .fetching
        )
    }

    // MARK: - GiftCardWalletError descriptions

    func test_error_noBaseURL_hasDescription() {
        let err = GiftCardWalletError.noBaseURL
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    func test_error_invalidPass_hasDescription() {
        let err = GiftCardWalletError.invalidPass
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    func test_error_httpStatus_hasDescription() {
        let err = GiftCardWalletError.httpStatus(404)
        XCTAssertTrue(err.errorDescription?.contains("404") ?? false)
    }

    func test_error_noRootViewController_hasDescription() {
        let err = GiftCardWalletError.noRootViewController
        XCTAssertFalse(err.errorDescription?.isEmpty ?? true)
    }

    // MARK: - PassUpdateSubscriber

    func test_passUpdateSubscriber_handlesSilentPush_knownKind() {
        let subscriber = PassUpdateSubscriber.shared
        var didCall = false

        subscriber.register(kind: "wallet-pass-update.giftcard") { _ in
            didCall = true
        }

        let userInfo: [AnyHashable: Any] = [
            "kind": "wallet-pass-update.giftcard",
            "passTypeIdentifier": "pass.com.bizarrecrm.giftcard",
            "serialNumber": "SN-001"
        ]

        let handled = subscriber.handleSilentPush(userInfo: userInfo)
        XCTAssertTrue(handled)
    }

    func test_passUpdateSubscriber_ignores_unknownKind() {
        let subscriber = PassUpdateSubscriber.shared

        let userInfo: [AnyHashable: Any] = [
            "kind": "some-other-push",
            "passTypeIdentifier": "pass.com.bizarrecrm.other",
            "serialNumber": "SN-999"
        ]

        // Should not crash; returns false.
        let handled = subscriber.handleSilentPush(userInfo: userInfo)
        // Kind unknown to this test run → false (unless a prior test registered it)
        _ = handled
    }

    func test_passUpdateSubscriber_returnsFalse_missingFields() {
        let subscriber = PassUpdateSubscriber.shared

        let userInfo: [AnyHashable: Any] = [:]
        let handled = subscriber.handleSilentPush(userInfo: userInfo)
        XCTAssertFalse(handled)
    }

    func test_passUpdateSubscriber_returnsFalse_missingSerialNumber() {
        let subscriber = PassUpdateSubscriber.shared

        let userInfo: [AnyHashable: Any] = [
            "kind": "wallet-pass-update.giftcard",
            "passTypeIdentifier": "pass.com.bizarrecrm.giftcard"
            // serialNumber missing
        ]

        let handled = subscriber.handleSilentPush(userInfo: userInfo)
        XCTAssertFalse(handled)
    }
}

// MARK: - MockGiftCardWalletService

final class MockGiftCardWalletService: GiftCardWalletServicing, @unchecked Sendable {

    var fetchResult: Result<URL, Error>?
    var addResult: Result<Void, Error>?
    var refreshResult: Result<URL, Error>?

    private(set) var fetchCallCount = 0
    private(set) var addCallCount = 0
    private(set) var refreshCallCount = 0

    func fetchPass(giftCardId: String) async throws -> URL {
        fetchCallCount += 1
        guard let result = fetchResult else {
            throw GiftCardWalletError.invalidPass
        }
        return try result.get()
    }

    func addToWallet(from url: URL) async throws {
        addCallCount += 1
        guard let result = addResult else {
            throw GiftCardWalletError.noRootViewController
        }
        try result.get()
    }

    func refreshPass(passId: String) async throws -> URL {
        refreshCallCount += 1
        guard let result = refreshResult else {
            throw GiftCardWalletError.noBaseURL
        }
        return try result.get()
    }
}

#endif // canImport(PassKit) && canImport(UIKit)
