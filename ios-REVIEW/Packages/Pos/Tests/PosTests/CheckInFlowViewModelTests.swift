#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

/// §16.25.6 — Unit tests for `CheckInFlowViewModel.finalizeSignStep()`.
///
/// Covers: signature upload, deposit payment write, ticket finalize, and
/// error-path behaviour (no advance on failure, offline fallback).
@MainActor
final class CheckInFlowViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeDraft(
        ticketId: Int64 = 42,
        depositPreset: DepositPreset = .zero,
        laborCents: Int = 5000,
        partsCents: Int = 0,
        signature: String? = "abc123"
    ) -> CheckInDraft {
        let d = CheckInDraft()
        d.ticketId = ticketId
        d.depositPreset = depositPreset
        d.laborCents = laborCents
        d.partsCents = partsCents
        d.signaturePNGBase64 = signature
        d.agreedToTerms = true
        d.consentToBackup = true
        d.authorizedDeposit = true
        return d
    }

    // MARK: - advance() from sign step calls onComplete

    func test_advance_fromSignStep_callsOnComplete_whenAPISucceeds() async {
        let api = MockCheckInAPIClient(signatureResult: .success, depositResult: .success, finalizeResult: .success)
        let draft = makeDraft()
        let vm = CheckInFlowViewModel(draft: draft, api: api)
        // Advance to last step directly
        vm.advanceToStep(.sign)

        var completedDraft: CheckInDraft?
        vm.onComplete = { completedDraft = $0 }

        await vm.advance()

        XCTAssertNotNil(completedDraft, "onComplete should fire after successful finalize")
        XCTAssertNil(vm.saveError, "no error expected on success path")
        XCTAssertTrue(api.signatureUploadCalled, "signature should be uploaded")
        XCTAssertTrue(api.finalizeTicketCalled, "ticket should be finalized")
    }

    func test_advance_fromSignStep_writesDeposit_whenDepositNonZero() async {
        let api = MockCheckInAPIClient(signatureResult: .success, depositResult: .success, finalizeResult: .success)
        let draft = makeDraft(depositPreset: .fifty, laborCents: 10_000)
        let vm = CheckInFlowViewModel(draft: draft, api: api)
        vm.advanceToStep(.sign)

        await vm.advance()

        XCTAssertTrue(api.depositPaymentCalled, "deposit payment should be written when depositCents > 0")
        XCTAssertEqual(api.depositAmountCents, 5000, accuracy: 1, "deposit should match DepositPreset.fifty on $100 total")
    }

    func test_advance_fromSignStep_skipsDepositPayment_whenDepositIsZero() async {
        let api = MockCheckInAPIClient(signatureResult: .success, depositResult: .success, finalizeResult: .success)
        let draft = makeDraft(depositPreset: .zero)
        let vm = CheckInFlowViewModel(draft: draft, api: api)
        vm.advanceToStep(.sign)

        await vm.advance()

        XCTAssertFalse(api.depositPaymentCalled, "no deposit call when depositCents == 0")
    }

    func test_advance_fromSignStep_doesNotAdvance_onAPIError() async {
        let api = MockCheckInAPIClient(signatureResult: .failure, depositResult: .success, finalizeResult: .success)
        let draft = makeDraft()
        let vm = CheckInFlowViewModel(draft: draft, api: api)
        vm.advanceToStep(.sign)

        var completedDraft: CheckInDraft?
        vm.onComplete = { completedDraft = $0 }

        await vm.advance()

        XCTAssertNil(completedDraft, "onComplete must NOT fire when signature upload fails")
        XCTAssertNotNil(vm.saveError, "saveError should be set on failure")
        XCTAssertTrue(vm.isOffline, "isOffline set on network error")
        XCTAssertEqual(vm.currentStep, .sign, "user stays on sign step to retry")
    }

    func test_advance_fromSignStep_callsOnComplete_withoutAPI() async {
        // No API — offline path: should still call onComplete.
        let draft = makeDraft()
        draft.ticketId = nil   // no ticketId forces offline path
        let vm = CheckInFlowViewModel(draft: draft, api: nil)
        vm.advanceToStep(.sign)

        var completedDraft: CheckInDraft?
        vm.onComplete = { completedDraft = $0 }

        await vm.advance()

        XCTAssertNotNil(completedDraft, "offline path should still navigate to receipt")
        XCTAssertTrue(vm.isOffline)
    }

    // MARK: - canAdvance

    func test_canAdvance_onSignStep_requiresSignatureAndChecks() {
        let draft = CheckInDraft()
        let vm = CheckInFlowViewModel(draft: draft, api: nil)
        vm.advanceToStep(.sign)

        XCTAssertFalse(vm.canAdvance(), "should not advance without checkboxes + signature")

        draft.agreedToTerms = true
        draft.consentToBackup = true
        draft.authorizedDeposit = true
        XCTAssertFalse(vm.canAdvance(), "still blocked without signature")

        draft.signaturePNGBase64 = "fake_sig"
        XCTAssertTrue(vm.canAdvance(), "should advance once signature + all required checks present")
    }
}

// MARK: - CheckInFlowViewModel test helper

private extension CheckInFlowViewModel {
    /// Fast-forward the current step without the full async sequence.
    func advanceToStep(_ step: CheckInStep) {
        currentStep = step
    }
}

// MARK: - MockCheckInAPIClient

private enum MockResult { case success, failure }

private final class MockCheckInAPIClient: APIClient, @unchecked Sendable {

    var signatureUploadCalled = false
    var depositPaymentCalled = false
    var finalizeTicketCalled = false
    var depositAmountCents: Int = 0

    private let signatureResult: MockResult
    private let depositResult: MockResult
    private let finalizeResult: MockResult

    init(signatureResult: MockResult, depositResult: MockResult, finalizeResult: MockResult) {
        self.signatureResult = signatureResult
        self.depositResult = depositResult
        self.finalizeResult = finalizeResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw URLError(.badURL)
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.badURL)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/signatures") {
            signatureUploadCalled = true
            if signatureResult == .failure {
                throw URLError(.notConnectedToInternet)
            }
            let json = #"{"success":true,"data":{}}"#.data(using: .utf8)!
            return try JSONDecoder().decode(T.self, from: json)
        }
        if path.contains("/payments") {
            depositPaymentCalled = true
            // Decode body to capture the amount for assertions.
            if let data = try? JSONEncoder().encode(body),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let amount = dict["amount"] as? Double {
                depositAmountCents = Int((amount * 100).rounded())
            }
            if depositResult == .failure {
                throw URLError(.notConnectedToInternet)
            }
            let json = #"{"success":true}"#.data(using: .utf8)!
            return try JSONDecoder().decode(T.self, from: json)
        }
        throw URLError(.badURL)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Handle ticket autosave (patchTicketDraft) and finalize (finalizeCheckinTicket)
        if path.contains("/tickets/") {
            if finalizeResult == .failure {
                throw URLError(.notConnectedToInternet)
            }
            finalizeTicketCalled = true
            let json = #"{"success":true,"data":{"id":42}}"#.data(using: .utf8)!
            return try JSONDecoder().decode(T.self, from: json)
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.badURL)
    }

    func delete(_ path: String) async throws {}

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
