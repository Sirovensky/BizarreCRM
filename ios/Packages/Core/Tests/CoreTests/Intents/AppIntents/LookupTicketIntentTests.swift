import XCTest
#if os(iOS)
@testable import Core

@available(iOS 16, *)
final class LookupTicketIntentTests: XCTestCase {

    // MARK: - perform()

    func test_perform_withValidOrderId_doesNotThrow() async throws {
        let intent = LookupTicketIntent(orderId: "T-042")
        _ = try await intent.perform()
    }

    func test_perform_withWhitespaceAroundId_doesNotThrow() async throws {
        let intent = LookupTicketIntent(orderId: "  T-001  ")
        _ = try await intent.perform()
    }

    func test_perform_withEmptyOrderId_throwsEmptyOrderIdError() async throws {
        let intent = LookupTicketIntent(orderId: "")
        do {
            _ = try await intent.perform()
            XCTFail("Expected LookupTicketIntentError.emptyOrderId to be thrown")
        } catch LookupTicketIntentError.emptyOrderId {
            // expected
        }
    }

    func test_perform_withWhitespaceOnlyOrderId_throwsEmptyOrderIdError() async throws {
        let intent = LookupTicketIntent(orderId: "   ")
        do {
            _ = try await intent.perform()
            XCTFail("Expected LookupTicketIntentError.emptyOrderId to be thrown")
        } catch LookupTicketIntentError.emptyOrderId {
            // expected
        }
    }

    // MARK: - Error localisation

    func test_emptyOrderIdError_hasLocalizedDescription() {
        let error = LookupTicketIntentError.emptyOrderId
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    // MARK: - Metadata

    func test_title_isLookUpTicket() {
        let title = String(localized: LookupTicketIntent.title)
        XCTAssertEqual(title, "Look Up Ticket")
    }

    func test_openAppWhenRun_isTrue() {
        XCTAssertTrue(LookupTicketIntent.openAppWhenRun)
    }

    // MARK: - Default init

    func test_defaultInit_orderIdIsEmpty() {
        let intent = LookupTicketIntent()
        XCTAssertEqual(intent.orderId, "")
    }

    func test_memberwise_init_preservesOrderId() {
        let intent = LookupTicketIntent(orderId: "T-999")
        XCTAssertEqual(intent.orderId, "T-999")
    }
}
#endif // os(iOS)
