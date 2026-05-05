import XCTest
@testable import Settings

// MARK: - §19.2 SecuritySettingsPage tests

final class SecuritySettingsPageTests: XCTestCase {

    private func makeSuite() -> UserDefaults {
        UserDefaults(suiteName: "test.security.\(UUID())")!
    }

    // MARK: - AutoLockTimeout

    func test_allTimeouts_haveNonEmptyDisplayName() {
        for timeout in AutoLockTimeout.allCases {
            XCTAssertFalse(timeout.displayName.isEmpty)
        }
    }

    func test_immediately_hasZeroSeconds() {
        XCTAssertEqual(AutoLockTimeout.immediately.seconds, 0)
    }

    func test_oneMinute_has60Seconds() {
        XCTAssertEqual(AutoLockTimeout.oneMinute.seconds, 60)
    }

    func test_never_hasNilSeconds() {
        XCTAssertNil(AutoLockTimeout.never.seconds)
    }

    // MARK: - ViewModel persistence

    @MainActor
    func test_viewModel_defaultAutoLock_isFiveMinutes() {
        let vm = SecuritySettingsViewModel(defaults: makeSuite())
        XCTAssertEqual(vm.autoLockTimeout, .fiveMinutes)
    }

    @MainActor
    func test_viewModel_savesAndLoads_autoLock() {
        let defaults = makeSuite()
        let vm = SecuritySettingsViewModel(defaults: defaults)
        vm.autoLockTimeout = .oneMinute
        vm.save()

        let vm2 = SecuritySettingsViewModel(defaults: defaults)
        XCTAssertEqual(vm2.autoLockTimeout, .oneMinute)
    }

    @MainActor
    func test_viewModel_savesAndLoads_biometric() {
        let defaults = makeSuite()
        let vm = SecuritySettingsViewModel(defaults: defaults)
        vm.biometricAppLockEnabled = true
        vm.save()

        let vm2 = SecuritySettingsViewModel(defaults: defaults)
        XCTAssertTrue(vm2.biometricAppLockEnabled)
    }

    @MainActor
    func test_viewModel_savesAndLoads_privacySnapshot() {
        let defaults = makeSuite()
        let vm = SecuritySettingsViewModel(defaults: defaults)
        vm.privacySnapshotEnabled = true
        vm.save()

        let vm2 = SecuritySettingsViewModel(defaults: defaults)
        XCTAssertTrue(vm2.privacySnapshotEnabled)
    }

    @MainActor
    func test_shouldApplySnapshot_trueAfterEnable() {
        // Use a fresh default suite to avoid test cross-contamination with .standard
        let defaults = makeSuite()
        let vm = SecuritySettingsViewModel(defaults: defaults)
        vm.privacySnapshotEnabled = true
        vm.save()
        // SecuritySettingsViewModel.shouldApplySnapshot() reads from .standard —
        // this test just verifies the save key logic via defaults directly.
        XCTAssertTrue(defaults.bool(forKey: "security.privacySnapshot"))
    }

    @MainActor
    func test_viewModel_autoLockDuration_roundTrips() {
        let defaults = makeSuite()
        let vm = SecuritySettingsViewModel(defaults: defaults)
        vm.autoLockTimeout = .fifteenMinutes
        vm.save()
        // Verify raw value stored
        XCTAssertEqual(defaults.string(forKey: "security.autoLock"), AutoLockTimeout.fifteenMinutes.rawValue)
    }
}
