import Testing
import Foundation
@testable import KioskMode

@Suite("KioskModeManager")
@MainActor
struct KioskModeManagerTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test-kiosk-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    // MARK: - Default state

    @Test("Starts in off mode by default")
    func startsOff() {
        let manager = KioskModeManager(defaults: makeDefaults())
        #expect(manager.currentMode == .off)
        #expect(manager.isKioskActive == false)
    }

    @Test("Starts with default config values")
    func startsWithDefaultConfig() {
        let manager = KioskModeManager(defaults: makeDefaults())
        #expect(manager.config.dimAfterSeconds == 120)
        #expect(manager.config.blackoutAfterSeconds == 300)
        #expect(manager.config.nightModeStart == 22)
        #expect(manager.config.nightModeEnd == 6)
    }

    // MARK: - Mode transitions

    @Test("setMode transitions correctly")
    func setModePersists() {
        let defaults = makeDefaults()
        let manager = KioskModeManager(defaults: defaults)

        manager.setMode(.posOnly)
        #expect(manager.currentMode == .posOnly)
        #expect(manager.isKioskActive == true)
        #expect(defaults.string(forKey: KioskModeManager.modeKey) == KioskMode.posOnly.rawValue)

        manager.setMode(.clockInOnly)
        #expect(manager.currentMode == .clockInOnly)

        manager.setMode(.training)
        #expect(manager.currentMode == .training)

        manager.setMode(.off)
        #expect(manager.currentMode == .off)
        #expect(manager.isKioskActive == false)
    }

    @Test("All modes cycle correctly")
    func allModesCycle() {
        let manager = KioskModeManager(defaults: makeDefaults())
        for mode in KioskMode.allCases {
            manager.setMode(mode)
            #expect(manager.currentMode == mode)
        }
    }

    // MARK: - Persistence

    @Test("Restores persisted mode across instantiation")
    func restoresPersistedMode() {
        let defaults = makeDefaults()
        let manager1 = KioskModeManager(defaults: defaults)
        manager1.setMode(.clockInOnly)

        let manager2 = KioskModeManager(defaults: defaults)
        #expect(manager2.currentMode == .clockInOnly)
    }

    @Test("Restores persisted config across instantiation")
    func restoresPersistedConfig() {
        let defaults = makeDefaults()
        let manager1 = KioskModeManager(defaults: defaults)
        manager1.config.dimAfterSeconds = 180
        manager1.config.nightModeStart = 20
        manager1.saveConfig()

        let manager2 = KioskModeManager(defaults: defaults)
        #expect(manager2.config.dimAfterSeconds == 180)
        #expect(manager2.config.nightModeStart == 20)
    }

    // MARK: - isKioskActive

    @Test("isKioskActive is false only for .off")
    func isKioskActiveLogic() {
        let manager = KioskModeManager(defaults: makeDefaults())

        manager.setMode(.off)
        #expect(manager.isKioskActive == false)

        manager.setMode(.posOnly)
        #expect(manager.isKioskActive == true)

        manager.setMode(.clockInOnly)
        #expect(manager.isKioskActive == true)

        manager.setMode(.training)
        #expect(manager.isKioskActive == true)
    }

    // MARK: - Night mode

    @Test("Night mode detection: overnight window (22..6)")
    func nightModeOvernightWindow() {
        let config = KioskConfig(nightModeStart: 22, nightModeEnd: 6)
        #expect(config.isNightModeActive(currentHour: 22) == true)
        #expect(config.isNightModeActive(currentHour: 23) == true)
        #expect(config.isNightModeActive(currentHour: 0)  == true)
        #expect(config.isNightModeActive(currentHour: 5)  == true)
        #expect(config.isNightModeActive(currentHour: 6)  == false)
        #expect(config.isNightModeActive(currentHour: 12) == false)
        #expect(config.isNightModeActive(currentHour: 21) == false)
    }

    @Test("Night mode detection: same-day window (8..18)")
    func nightModeSameDayWindow() {
        let config = KioskConfig(nightModeStart: 8, nightModeEnd: 18)
        #expect(config.isNightModeActive(currentHour: 8)  == true)
        #expect(config.isNightModeActive(currentHour: 17) == true)
        #expect(config.isNightModeActive(currentHour: 18) == false)
        #expect(config.isNightModeActive(currentHour: 0)  == false)
    }
}
