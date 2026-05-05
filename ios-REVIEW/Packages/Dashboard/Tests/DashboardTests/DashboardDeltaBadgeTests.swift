import XCTest
@testable import Dashboard

// MARK: - §3.1 Previous-period delta badge tests

final class DashboardDeltaBadgeTests: XCTestCase {

    // MARK: - DeltaDirection.from(_:)

    func test_positiveValue_isUp() {
        XCTAssertEqual(DeltaDirection.from(12.5), .up)
        XCTAssertEqual(DeltaDirection.from(0.1), .up)
        XCTAssertEqual(DeltaDirection.from(100), .up)
    }

    func test_negativeValue_isDown() {
        XCTAssertEqual(DeltaDirection.from(-5.3), .down)
        XCTAssertEqual(DeltaDirection.from(-0.1), .down)
    }

    func test_zeroValue_isFlat() {
        XCTAssertEqual(DeltaDirection.from(0.0), .flat)
        XCTAssertEqual(DeltaDirection.from(0.001), .flat)  // within threshold
        XCTAssertEqual(DeltaDirection.from(-0.001), .flat)
    }

    // MARK: - DeltaDirection properties

    func test_up_hasCorrectSystemImage() {
        XCTAssertEqual(DeltaDirection.up.systemImageName, "arrow.up")
    }

    func test_down_hasCorrectSystemImage() {
        XCTAssertEqual(DeltaDirection.down.systemImageName, "arrow.down")
    }

    func test_flat_hasCorrectSystemImage() {
        XCTAssertEqual(DeltaDirection.flat.systemImageName, "minus")
    }

    // MARK: - KpiTileItemWithDelta init

    func test_tile_deltaIsOptional() {
        let tile = KpiTileItemWithDelta(label: "Revenue", value: "$1,200", icon: "dollarsign.circle")
        XCTAssertNil(tile.delta)
    }

    func test_tile_storesdelta() {
        let tile = KpiTileItemWithDelta(label: "Revenue", value: "$1,200", icon: "dollarsign.circle", delta: 14.2)
        XCTAssertEqual(tile.delta, 14.2)
    }

    func test_tile_negativeDelta() {
        let tile = KpiTileItemWithDelta(label: "Refunds", value: "$50", icon: "arrow.uturn.backward", delta: -3.1)
        XCTAssertEqual(DeltaDirection.from(tile.delta!), .down)
    }
}
