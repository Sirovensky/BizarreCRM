import XCTest
@testable import Auth

final class DeviceBindingTests: XCTestCase {

    private let tenantId = "test-tenant-\(UUID().uuidString)"
    private var sut: DeviceBinding!

    override func setUp() {
        super.setUp()
        sut = DeviceBinding()
        sut.clear(tenantId: tenantId)
    }

    override func tearDown() {
        sut.clear(tenantId: tenantId)
        super.tearDown()
    }

    func test_noBinding_isValid() {
        // No binding stored — should pass through (bind after next login)
        XCTAssertTrue(sut.isValid(tenantId: tenantId))
    }

    func test_bindAndCheck_isSameDevice() {
        sut.bind(tenantId: tenantId)
        XCTAssertTrue(sut.isValid(tenantId: tenantId))
    }

    func test_clear_removesBinding() {
        sut.bind(tenantId: tenantId)
        sut.clear(tenantId: tenantId)
        // After clearing: no binding stored → isValid returns true (allows re-bind)
        XCTAssertTrue(sut.isValid(tenantId: tenantId))
    }

    func test_perTenantScope_doesNotBleed() {
        let t2 = "test-tenant-2-\(UUID().uuidString)"
        sut.bind(tenantId: tenantId)
        // t2 has no binding — should be valid (no binding = no mismatch)
        XCTAssertTrue(sut.isValid(tenantId: t2))
        sut.clear(tenantId: t2)
    }

    func test_currentDeviceClassId_isNonEmpty() {
        let id = DeviceBinding.currentDeviceClassId()
        XCTAssertFalse(id.isEmpty)
    }

    func test_currentDeviceClassId_isStable() {
        let id1 = DeviceBinding.currentDeviceClassId()
        let id2 = DeviceBinding.currentDeviceClassId()
        XCTAssertEqual(id1, id2)
    }
}
