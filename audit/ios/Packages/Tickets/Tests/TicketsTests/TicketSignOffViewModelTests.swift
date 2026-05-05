import XCTest
@testable import Tickets
@testable import Networking

/// §4 — TicketSignOffViewModel unit tests.
@MainActor
final class TicketSignOffViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)
        if case .idle = vm.state { /* pass */ } else {
            XCTFail("Expected .idle")
        }
    }

    func test_initialState_signatureDataNil() {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)
        XCTAssertNil(vm.signatureData)
    }

    // MARK: - Submit without signature

    func test_submit_withoutSignature_setsFailed() async {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)

        await vm.submit()

        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed when no signature")
        }
    }

    func test_submit_emptySignatureData_setsFailed() async {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)
        vm.signatureData = Data()

        await vm.submit()

        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed for empty data")
        }
    }

    // MARK: - Submit with signature

    func test_submit_withValidSignature_success() async {
        let api = ExtendedStubAPIClient()
        await api.setSignOffResult(.success(SignOffResponse(receiptId: "RC-001", pdfUrl: "https://example.com/rc.pdf")))
        let vm = TicketSignOffViewModel(ticketId: 5, api: api)
        vm.signatureData = Data(repeating: 0xFF, count: 100) // fake PNG data

        await vm.submit()

        if case .success(let receiptId, let pdfURL) = vm.state {
            XCTAssertEqual(receiptId, "RC-001")
            XCTAssertNotNil(pdfURL)
        } else {
            XCTFail("Expected .success, got \(vm.state)")
        }
    }

    func test_submit_apiFailure_setsFailed() async {
        let api = ExtendedStubAPIClient()
        await api.setSignOffResult(.failure(APITransportError.noBaseURL))
        let vm = TicketSignOffViewModel(ticketId: 5, api: api)
        vm.signatureData = Data(repeating: 0xFF, count: 100)

        await vm.submit()

        if case .failed = vm.state { /* pass */ } else {
            XCTFail("Expected .failed")
        }
    }

    func test_submit_pdfUrlNil_whenMissing() async {
        let api = ExtendedStubAPIClient()
        await api.setSignOffResult(.success(SignOffResponse(receiptId: "RC-002", pdfUrl: nil)))
        let vm = TicketSignOffViewModel(ticketId: 5, api: api)
        vm.signatureData = Data(repeating: 0xAB, count: 50)

        await vm.submit()

        if case .success(_, let pdfURL) = vm.state {
            XCTAssertNil(pdfURL)
        } else {
            XCTFail("Expected .success")
        }
    }

    // MARK: - Clear signature

    func test_clearSignature_nilsData() {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)
        vm.signatureData = Data(repeating: 0, count: 10)

        vm.clearSignature()

        XCTAssertNil(vm.signatureData)
    }

    func test_clearSignature_resetsFailedState() async {
        let api = ExtendedStubAPIClient()
        let vm = TicketSignOffViewModel(ticketId: 1, api: api)
        // Trigger failed state
        await vm.submit()
        if case .failed = vm.state { /* good */ } else {
            XCTFail("Setup failed")
            return
        }

        vm.clearSignature()

        if case .idle = vm.state { /* pass */ } else {
            XCTFail("Expected .idle after clear")
        }
    }

    // MARK: - Disclaimer text

    func test_disclaimerText_isNotEmpty() {
        XCTAssertFalse(TicketSignOffViewModel.disclaimerText.isEmpty)
    }

    func test_disclaimerText_containsKeywords() {
        let disclaimer = TicketSignOffViewModel.disclaimerText.lowercased()
        XCTAssertTrue(disclaimer.contains("repair"))
        XCTAssertTrue(disclaimer.contains("sign"))
    }
}

extension ExtendedStubAPIClient {
    func setSignOffResult(_ result: Result<SignOffResponse, Error>) {
        signOffResult = result
    }
}
