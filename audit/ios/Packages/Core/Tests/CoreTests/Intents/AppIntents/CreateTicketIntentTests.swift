import XCTest
#if os(iOS)
@testable import Core

@available(iOS 16, *)
final class CreateTicketIntentTests: XCTestCase {

    // MARK: - Helpers

    private func makeCustomer(id: Int64 = 1, name: String = "Alice") -> CustomerEntity {
        CustomerEntity(id: id, displayName: name, phone: "555-0001", email: "alice@example.com")
    }

    // MARK: - perform()

    func test_perform_withoutParams_doesNotThrow() async throws {
        let intent = CreateTicketIntent()
        _ = try await intent.perform()
    }

    func test_perform_withCustomerAndDevice_doesNotThrow() async throws {
        let intent = CreateTicketIntent(customer: makeCustomer(), device: "iPhone 15 Pro")
        _ = try await intent.perform()
    }

    func test_perform_withCustomerOnly_doesNotThrow() async throws {
        let intent = CreateTicketIntent(customer: makeCustomer(id: 7, name: "Bob"))
        _ = try await intent.perform()
    }

    func test_perform_withDeviceOnly_doesNotThrow() async throws {
        let intent = CreateTicketIntent(device: "Galaxy S24")
        _ = try await intent.perform()
    }

    func test_perform_withEmptyDevice_doesNotThrow() async throws {
        let intent = CreateTicketIntent(device: "")
        _ = try await intent.perform()
    }

    // MARK: - Metadata

    func test_title_isCreateTicket() {
        let title = String(localized: CreateTicketIntent.title)
        XCTAssertEqual(title, "Create Ticket")
    }

    func test_openAppWhenRun_isTrue() {
        XCTAssertTrue(CreateTicketIntent.openAppWhenRun)
    }

    // MARK: - Parameter wiring

    func test_defaultInit_customerIsNil() {
        let intent = CreateTicketIntent()
        XCTAssertNil(intent.customer)
        XCTAssertNil(intent.device)
    }

    func test_init_customerPreserved() {
        let c = makeCustomer(id: 42, name: "Carol")
        let intent = CreateTicketIntent(customer: c, device: "iPad Air")
        XCTAssertEqual(intent.customer?.numericId, 42)
        XCTAssertEqual(intent.customer?.displayName, "Carol")
        XCTAssertEqual(intent.device, "iPad Air")
    }

    func test_customerEntity_numericIdRoundtrips() {
        let c = makeCustomer(id: 99, name: "Dan")
        XCTAssertEqual(c.id, "99")
        XCTAssertEqual(c.numericId, 99)
    }
}
#endif // os(iOS)
