import XCTest
@testable import Expenses

final class MileageCalculatorTests: XCTestCase {

    // MARK: - Distance (haversine)

    func test_samePoint_zeroDistance() {
        let miles = MileageCalculator.distanceMiles(
            fromLat: 37.7749, fromLon: -122.4194,
            toLat: 37.7749, toLon: -122.4194
        )
        XCTAssertEqual(miles, 0, accuracy: 0.001)
    }

    func test_sfToLA_approx380Miles() {
        // SF (37.7749, -122.4194) → LA (34.0522, -118.2437)
        let miles = MileageCalculator.distanceMiles(
            fromLat: 37.7749, fromLon: -122.4194,
            toLat: 34.0522, toLon: -118.2437
        )
        // ~340 straight-line miles (not road distance)
        XCTAssertGreaterThan(miles, 300)
        XCTAssertLessThan(miles, 400)
    }

    func test_shortTrip_smallDistance() {
        // ~1 mile apart (rough estimate)
        let miles = MileageCalculator.distanceMiles(
            fromLat: 37.7749, fromLon: -122.4194,
            toLat: 37.7749, toLon: -122.4049   // ~0.8 miles west
        )
        XCTAssertGreaterThan(miles, 0.5)
        XCTAssertLessThan(miles, 1.5)
    }

    func test_symmetry_sameDistance() {
        let d1 = MileageCalculator.distanceMiles(fromLat: 40.7, fromLon: -74.0, toLat: 34.0, toLon: -118.2)
        let d2 = MileageCalculator.distanceMiles(fromLat: 34.0, fromLon: -118.2, toLat: 40.7, toLon: -74.0)
        XCTAssertEqual(d1, d2, accuracy: 0.001)
    }

    func test_northPoleToEquator_approxly3900Miles() {
        // North Pole (90°N) to equator (0°, 0°) = 90° arc = ~10,008 km = ~6,222 miles
        let miles = MileageCalculator.distanceMiles(
            fromLat: 90.0, fromLon: 0.0,
            toLat: 0.0, toLon: 0.0
        )
        XCTAssertGreaterThan(miles, 6000)
        XCTAssertLessThan(miles, 6500)
    }

    // MARK: - Total cents

    func test_totalCents_zeroMiles() {
        XCTAssertEqual(MileageCalculator.totalCents(miles: 0, rateCentsPerMile: 67), 0)
    }

    func test_totalCents_oneMile_at67cents() {
        XCTAssertEqual(MileageCalculator.totalCents(miles: 1, rateCentsPerMile: 67), 67)
    }

    func test_totalCents_tenMiles_at67cents() {
        XCTAssertEqual(MileageCalculator.totalCents(miles: 10, rateCentsPerMile: 67), 670)
    }

    func test_totalCents_fractionalMiles_rounds() {
        // 0.5 miles × 67¢ = 33.5¢ → rounds to 34¢
        XCTAssertEqual(MileageCalculator.totalCents(miles: 0.5, rateCentsPerMile: 67), 34)
    }

    func test_totalCents_irsStandardRate2024() {
        // IRS 2024: 67¢/mile. 100 miles = $67.00
        XCTAssertEqual(MileageCalculator.totalCents(miles: 100, rateCentsPerMile: 67), 6700)
    }

    func test_totalCents_zeroRate() {
        XCTAssertEqual(MileageCalculator.totalCents(miles: 100, rateCentsPerMile: 0), 0)
    }

    // MARK: - Convenience

    func test_reimbursementCents_returnsDistanceAndCents() {
        let (miles, cents) = MileageCalculator.reimbursementCents(
            fromLat: 37.7749, fromLon: -122.4194,
            toLat: 37.7749, toLon: -122.4049,
            rateCentsPerMile: 67
        )
        XCTAssertGreaterThan(miles, 0)
        XCTAssertGreaterThan(cents, 0)
        // cents = round(miles × 67)
        XCTAssertEqual(cents, Int((miles * 67).rounded()))
    }

    func test_reimbursementCents_samePoint_zeroTotal() {
        let (miles, cents) = MileageCalculator.reimbursementCents(
            fromLat: 40.0, fromLon: -80.0,
            toLat: 40.0, toLon: -80.0,
            rateCentsPerMile: 67
        )
        XCTAssertEqual(miles, 0, accuracy: 0.0001)
        XCTAssertEqual(cents, 0)
    }
}
