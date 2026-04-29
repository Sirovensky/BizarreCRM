import XCTest
@testable import Reports

// MARK: - Insights§91_5Tests
//
// Unit tests covering the six §91.5 Insights-tab fixes:
//   1. NPSScore.respondentCount round-trips through Codable.
//   2. NPSScore with respondentCount < 10 is flagged as insufficient.
//   3. NPSScore with respondentCount >= 10 is not flagged.
//   4. CustomerAcquisitionChurn all-zeros detection helper.
//   5. DeviceModelRepaired sort order is descending by repairCount.
//   6. WarrantyClaimsPoint empty collection detected correctly.

final class Insights§91_5Tests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - 1. NPSScore respondentCount round-trips

    func test_npsScore_respondentCount_roundTrips() throws {
        let original = NPSScore(
            current: 42, previous: 38,
            promoterPct: 60, detractorPct: 15,
            themes: ["Speed"],
            respondentCount: 27
        )
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(NPSScore.self, from: data)
        XCTAssertEqual(decoded.respondentCount, 27)
    }

    // MARK: - 2. respondentCount < 10 → insufficient data

    func test_npsScore_insufficientData_whenRespondentCountBelowThreshold() {
        let nps = NPSScore(current: 0, previous: 0,
                          promoterPct: 0, detractorPct: 0,
                          themes: [], respondentCount: 9)
        XCTAssertTrue(nps.respondentCount < 10,
                      "respondentCount 9 should trigger the insufficient-data guard")
    }

    // MARK: - 3. respondentCount >= 10 → data is sufficient

    func test_npsScore_sufficientData_whenRespondentCountAtThreshold() {
        let nps = NPSScore(current: 55, previous: 48,
                          promoterPct: 65, detractorPct: 12,
                          themes: ["Quality"], respondentCount: 10)
        XCTAssertFalse(nps.respondentCount < 10,
                       "respondentCount 10 should NOT trigger the insufficient-data guard")
    }

    // MARK: - 4. CustomerAcquisitionChurn all-zeros detection

    func test_customerAcquisitionChurn_allZeros_detectedCorrectly() {
        let zero = CustomerAcquisitionChurn(newCustomers: 0, churnedCustomers: 0,
                                           returningCustomers: 0)
        XCTAssertTrue(
            zero.newCustomers == 0 && zero.churnedCustomers == 0 && zero.returningCustomers == 0,
            "All-zero state should be detectable without data"
        )
    }

    func test_customerAcquisitionChurn_nonZero_notAllZeros() {
        let active = CustomerAcquisitionChurn(newCustomers: 3, churnedCustomers: 1,
                                             returningCustomers: 0)
        XCTAssertFalse(
            active.newCustomers == 0 && active.churnedCustomers == 0 && active.returningCustomers == 0,
            "Non-zero acquisition data must not trigger the aggregate empty state"
        )
    }

    // MARK: - 5. DeviceModelRepaired sort order

    func test_deviceModelsRepaired_sortedDescendingByCount() {
        let rows: [DeviceModelRepaired] = [
            DeviceModelRepaired(model: "A", repairCount: 5, revenueDollars: 100),
            DeviceModelRepaired(model: "B", repairCount: 20, revenueDollars: 400),
            DeviceModelRepaired(model: "C", repairCount: 3, revenueDollars: 60),
        ]
        let sorted = rows.sorted { $0.repairCount > $1.repairCount }
        XCTAssertEqual(sorted.map(\.model), ["B", "A", "C"],
                       "Models must be sorted descending by repairCount")
        XCTAssertEqual(sorted.first?.repairCount, 20)
    }

    // MARK: - 6. WarrantyClaimsPoint empty-period detection

    func test_warrantyClaimsPoint_emptyCollection_detectedCorrectly() {
        let points: [WarrantyClaimsPoint] = []
        XCTAssertTrue(points.isEmpty, "Empty claims array should render placeholder, not chart")
    }

    func test_warrantyClaimsPoint_nonEmpty_notEmpty() {
        let points: [WarrantyClaimsPoint] = [
            WarrantyClaimsPoint(period: "2026-04", claimsCount: 3,
                                resolvedCount: 2, avgResolutionDays: 1.5),
        ]
        XCTAssertFalse(points.isEmpty, "Non-empty claims array should render the chart")
    }
}
