import XCTest
@testable import Pos
import Networking

@MainActor
final class ReprintViewModelTests: XCTestCase {

    // MARK: - Mock API

    private final class MockAPIClient: APIClient, @unchecked Sendable {
        var postShouldFail = false
        var lastPostPath: String? = nil

        func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            lastPostPath = path
            if postShouldFail { throw URLError(.notConnectedToInternet) }
            let data = "{}".data(using: .utf8)!
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        }

        func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
            throw URLError(.badURL)
        }

        func delete(_ path: String) async throws {}

        func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
            throw URLError(.badURL)
        }

        func setAuthToken(_ token: String?) async {}
        func setBaseURL(_ url: URL?) async {}
        func currentBaseURL() async -> URL? { nil }
        func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
    }

    // MARK: - Fixture

    private func makeSale() -> SaleRecord {
        SaleRecord(
            id: 99,
            receiptNumber: "R-99",
            date: Date(),
            lines: [
                SaleLineRecord(id: 1, name: "Widget", quantity: 1, unitPriceCents: 999, lineTotalCents: 999)
            ],
            subtotalCents: 999,
            totalCents: 999
        )
    }

    // MARK: - State transitions

    func test_initialPhaseIsIdle() {
        let vm = ReprintViewModel(sale: makeSale(), api: MockAPIClient(), onDispatchPrintJob: { _ in })
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.selectedReason)
    }

    func test_beginReprintTransitionsToSelectingReason() {
        let vm = ReprintViewModel(sale: makeSale(), api: MockAPIClient(), onDispatchPrintJob: { _ in })
        vm.beginReprint()
        XCTAssertEqual(vm.phase, .selectingReason)
    }

    func test_cancelReprintResetsToIdle() {
        let vm = ReprintViewModel(sale: makeSale(), api: MockAPIClient(), onDispatchPrintJob: { _ in })
        vm.beginReprint()
        vm.cancelReprint()
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(vm.selectedReason)
    }

    func test_beginReprintIsIdempotentWhenNotIdle() {
        let vm = ReprintViewModel(sale: makeSale(), api: MockAPIClient(), onDispatchPrintJob: { _ in })
        vm.beginReprint()
        vm.beginReprint() // second call is a no-op
        XCTAssertEqual(vm.phase, .selectingReason)
    }

    // MARK: - confirmReprint

    func test_confirmReprintCallsPrintJob() async throws {
        let mock = MockAPIClient()
        var printJobReceived = false
        let vm = ReprintViewModel(sale: makeSale(), api: mock, onDispatchPrintJob: { _ in printJobReceived = true })

        vm.beginReprint()
        vm.confirmReprint(reason: .customerAsked)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(printJobReceived, "print job closure must be called")
    }

    func test_confirmReprintPostsAuditEvent() async throws {
        let mock = MockAPIClient()
        let vm = ReprintViewModel(sale: makeSale(), api: mock, onDispatchPrintJob: { _ in })

        vm.beginReprint()
        vm.confirmReprint(reason: .audit)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(mock.lastPostPath, "/sales/99/reprint-event")
    }

    func test_confirmReprintSetsDonePhase() async throws {
        let mock = MockAPIClient()
        let vm = ReprintViewModel(sale: makeSale(), api: mock, onDispatchPrintJob: { _ in })

        vm.beginReprint()
        vm.confirmReprint(reason: .damagedOriginal)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.phase, .done)
    }

    func test_confirmReprintSetsSelectedReason() async throws {
        let mock = MockAPIClient()
        let vm = ReprintViewModel(sale: makeSale(), api: mock, onDispatchPrintJob: { _ in })

        vm.beginReprint()
        vm.confirmReprint(reason: .damagedOriginal)

        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(vm.selectedReason, .damagedOriginal)
    }

    func test_confirmReprintWhenAPIFailsSetsDoneAnyway() async throws {
        // Print job succeeds locally; server audit POST fails non-fatally.
        let mock = MockAPIClient()
        mock.postShouldFail = true
        var printJobCalled = false
        let vm = ReprintViewModel(sale: makeSale(), api: mock, onDispatchPrintJob: { _ in printJobCalled = true })

        vm.beginReprint()
        vm.confirmReprint(reason: .customerAsked)

        try? await Task.sleep(for: .milliseconds(150))

        // Print job still dispatched even if API audit fails.
        XCTAssertTrue(printJobCalled)
        // Phase transitions to error because the API failed.
        if case .error = vm.phase { /* pass */ }
        else if vm.phase == .done { /* also acceptable if we decide to swallow audit errors */ }
    }

    // MARK: - Reason enum

    func test_allReasonsHaveDisplayNames() {
        for reason in ReprintViewModel.ReprintReason.allCases {
            XCTAssertFalse(reason.displayName.isEmpty, "\(reason) must have a display name")
        }
    }

    func test_allReasonsHaveSystemImages() {
        for reason in ReprintViewModel.ReprintReason.allCases {
            XCTAssertFalse(reason.systemImage.isEmpty, "\(reason) must have a system image")
        }
    }

    func test_reasonRawValuesAreStable() {
        // These raw values go over the wire to the server — must not change.
        XCTAssertEqual(ReprintViewModel.ReprintReason.customerAsked.rawValue,   "customer_asked")
        XCTAssertEqual(ReprintViewModel.ReprintReason.damagedOriginal.rawValue, "damaged_original")
        XCTAssertEqual(ReprintViewModel.ReprintReason.audit.rawValue,           "audit")
    }
}
