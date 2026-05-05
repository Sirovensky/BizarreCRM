import XCTest
@testable import Auth

/// §2 Shared-device mode — SharedDeviceManager unit tests.
/// Uses `InMemoryDeviceStorage` to avoid `UserDefaults` Sendable issues.
final class SharedDeviceManagerTests: XCTestCase {

    // MARK: - Initial state

    func test_defaultState_isNotSharedDevice() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        let enabled = await mgr.isSharedDevice
        XCTAssertFalse(enabled)
    }

    func test_persistedState_isRestoredOnInit() async {
        let storage = InMemoryDeviceStorage()
        storage.set(true, forKey: "shared_device_mode")
        let mgr = SharedDeviceManager(storage: storage)
        let enabled = await mgr.isSharedDevice
        XCTAssertTrue(enabled)
    }

    // MARK: - enable / disable

    func test_enable_setsIsSharedDevice_true() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        let enabled = await mgr.isSharedDevice
        XCTAssertTrue(enabled)
    }

    func test_enable_persistsToStorage() async {
        let storage = InMemoryDeviceStorage()
        let mgr = SharedDeviceManager(storage: storage)
        await mgr.enable()
        XCTAssertTrue(storage.bool(forKey: "shared_device_mode"))
    }

    func test_disable_setsIsSharedDevice_false() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        await mgr.disable()
        let enabled = await mgr.isSharedDevice
        XCTAssertFalse(enabled)
    }

    func test_disable_persistsToStorage() async {
        let storage = InMemoryDeviceStorage()
        let mgr = SharedDeviceManager(storage: storage)
        await mgr.enable()
        await mgr.disable()
        XCTAssertFalse(storage.bool(forKey: "shared_device_mode"))
    }

    func test_disable_clearsSessionExpiry() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        await mgr.setSessionExpiry(Date(timeIntervalSinceNow: 3600))
        await mgr.disable()
        let expiry = await mgr.sessionExpiresAt
        XCTAssertNil(expiry)
    }

    // MARK: - sessionExpiresAt

    func test_setSessionExpiry_storesDate() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        let date = Date(timeIntervalSinceNow: 3600)
        await mgr.setSessionExpiry(date)
        let stored = await mgr.sessionExpiresAt
        XCTAssertEqual(stored, date)
    }

    func test_setSessionExpiry_nil_clearsDate() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.setSessionExpiry(Date(timeIntervalSinceNow: 3600))
        await mgr.setSessionExpiry(nil)
        let stored = await mgr.sessionExpiresAt
        XCTAssertNil(stored)
    }

    // MARK: - effectiveSessionExpiry

    func test_effectiveSessionExpiry_whenNotSharedDevice_returnsNil() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        let expiry = await mgr.effectiveSessionExpiry()
        XCTAssertNil(expiry)
    }

    func test_effectiveSessionExpiry_whenSharedDevice_returnsCustomExpiry() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        let custom = Date(timeIntervalSinceNow: 7200)
        await mgr.setSessionExpiry(custom)
        let expiry = await mgr.effectiveSessionExpiry()
        XCTAssertEqual(expiry, custom)
    }

    func test_effectiveSessionExpiry_whenSharedDevice_noCustom_returnsDefault() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        let expiry = await mgr.effectiveSessionExpiry()
        XCTAssertNotNil(expiry)
        let expected = Date(timeIntervalSinceNow: SharedDeviceManager.defaultSessionDuration)
        let diff = abs(expiry!.timeIntervalSince(expected))
        XCTAssertLessThan(diff, 5)
    }

    // MARK: - idleTimeout

    func test_idleTimeout_normalMode_returns15Min() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        let timeout = await mgr.idleTimeout()
        XCTAssertEqual(timeout, 15 * 60)
    }

    func test_idleTimeout_sharedDeviceMode_returns4Min() async {
        let mgr = SharedDeviceManager(storage: InMemoryDeviceStorage())
        await mgr.enable()
        let timeout = await mgr.idleTimeout()
        XCTAssertEqual(timeout, 4 * 60)
    }
}
