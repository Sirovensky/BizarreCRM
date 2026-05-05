import XCTest
@testable import DesignSystem

final class BrandSpacingTests: XCTestCase {
    func test_eightPointGridHolds() {
        XCTAssertEqual(BrandSpacing.sm, 8)
        XCTAssertEqual(BrandSpacing.base, 16)
        XCTAssertEqual(BrandSpacing.lg, 24)
        XCTAssertEqual(BrandSpacing.xl, 32)
    }
}
