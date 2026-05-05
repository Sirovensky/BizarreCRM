import XCTest
#if os(iOS)
@testable import Core

final class NextAppointmentIntentTests: XCTestCase {

    // MARK: - Stub repo

    final class StubAppointmentRepo: AppointmentEntityRepository, @unchecked Sendable {
        var stubbedNext: AppointmentEntity?
        var stubbedById: [String: AppointmentEntity] = [:]

        func appointments(for stringIds: [String]) async throws -> [AppointmentEntity] {
            stringIds.compactMap { stubbedById[$0] }
        }

        func nextAppointment() async throws -> AppointmentEntity? {
            stubbedNext
        }
    }

    private var stub: StubAppointmentRepo!

    override func setUp() {
        super.setUp()
        stub = StubAppointmentRepo()
        AppointmentEntityQueryConfig.register(stub)
    }

    // MARK: - NextAppointmentIntent

    @available(iOS 16, *)
    func test_perform_whenAppointmentExists_returnsEntity() async throws {
        let appt = AppointmentEntity(
            id: 1,
            customerName: "Ivan",
            scheduledAt: Date(timeIntervalSinceNow: 3600),
            serviceName: "Screen Repair"
        )
        stub.stubbedNext = appt

        let intent = NextAppointmentIntent()
        // Verify perform() does not throw
        _ = try await intent.perform()
    }

    @available(iOS 16, *)
    func test_perform_whenNoAppointment_doesNotThrow() async throws {
        stub.stubbedNext = nil
        let intent = NextAppointmentIntent()
        _ = try await intent.perform()
    }

    // MARK: - AppointmentEntityQuery

    @available(iOS 16, *)
    func test_appointmentQuery_entitiesForIds_returnsMatched() async throws {
        let appt = AppointmentEntity(id: 5, customerName: "Judy", scheduledAt: Date())
        stub.stubbedById["5"] = appt

        let query = AppointmentEntityQuery()
        let results = try await query.entities(for: ["5"])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.customerName, "Judy")
    }

    @available(iOS 16, *)
    func test_appointmentQuery_suggestedEntities_returnsNextWhenPresent() async throws {
        let appt = AppointmentEntity(id: 9, customerName: "Karl", scheduledAt: Date())
        stub.stubbedNext = appt

        let query = AppointmentEntityQuery()
        let results = try await query.suggestedEntities()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.customerName, "Karl")
    }

    @available(iOS 16, *)
    func test_appointmentQuery_suggestedEntities_emptyWhenNoNext() async throws {
        stub.stubbedNext = nil
        let query = AppointmentEntityQuery()
        let results = try await query.suggestedEntities()
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - AppointmentEntity displayRepresentation

    func test_appointmentEntity_displayRepresentation_includesCustomerName() {
        let appt = AppointmentEntity(
            id: 12,
            customerName: "Lara",
            scheduledAt: Date(),
            serviceName: "Battery"
        )
        let title = String(localized: appt.displayRepresentation.title)
        XCTAssertTrue(title.contains("Lara"))
    }
}
#endif // os(iOS)
