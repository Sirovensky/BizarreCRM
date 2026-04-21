import Testing
import Foundation
@testable import DesignSystem

// §66 — HapticsSettings tests

@Suite("HapticsSettings")
struct HapticsSettingsTests {

    // MARK: Helpers

    private func makeSut() -> HapticsSettings {
        // Use an ephemeral domain so tests never pollute .standard.
        let suiteName = "com.bizarrecrm.test.haptics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return HapticsSettings(defaults: defaults)
    }

    // MARK: Defaults

    @Test("default hapticsEnabled is true")
    func defaultHapticsEnabled() {
        let sut = makeSut()
        #expect(sut.hapticsEnabled == true)
    }

    @Test("default soundsEnabled is true")
    func defaultSoundsEnabled() {
        let sut = makeSut()
        #expect(sut.soundsEnabled == true)
    }

    @Test("default quietHoursOn is false")
    func defaultQuietHoursOff() {
        let sut = makeSut()
        #expect(sut.quietHoursOn == false)
    }

    @Test("default quietHoursStart is 21")
    func defaultQuietStart() {
        let sut = makeSut()
        #expect(sut.quietHoursStart == 21)
    }

    @Test("default quietHoursEnd is 7")
    func defaultQuietEnd() {
        let sut = makeSut()
        #expect(sut.quietHoursEnd == 7)
    }

    // MARK: Persistence round-trips

    @Test("persists hapticsEnabled=false and restores it")
    func persistsHapticsDisabled() {
        let suiteName = "com.bizarrecrm.test.haptics.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut1 = HapticsSettings(defaults: defaults)
        sut1.hapticsEnabled = false

        let sut2 = HapticsSettings(defaults: defaults)
        #expect(sut2.hapticsEnabled == false)
    }

    @Test("persists soundsEnabled=false and restores it")
    func persistsSoundsDisabled() {
        let suiteName = "com.bizarrecrm.test.haptics.sounds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut1 = HapticsSettings(defaults: defaults)
        sut1.soundsEnabled = false

        let sut2 = HapticsSettings(defaults: defaults)
        #expect(sut2.soundsEnabled == false)
    }

    @Test("persists custom quiet hours and restores them")
    func persistsQuietHours() {
        let suiteName = "com.bizarrecrm.test.haptics.qh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut1 = HapticsSettings(defaults: defaults)
        sut1.quietHoursOn    = true
        sut1.quietHoursStart = 22
        sut1.quietHoursEnd   = 6

        let sut2 = HapticsSettings(defaults: defaults)
        #expect(sut2.quietHoursOn    == true)
        #expect(sut2.quietHoursStart == 22)
        #expect(sut2.quietHoursEnd   == 6)
    }

    // MARK: resetToDefaults

    @Test("resetToDefaults restores all defaults")
    func resetToDefaultsRestoresAll() {
        let sut = makeSut()
        sut.hapticsEnabled  = false
        sut.soundsEnabled   = false
        sut.quietHoursOn    = true
        sut.quietHoursStart = 22
        sut.quietHoursEnd   = 6

        sut.resetToDefaults()

        #expect(sut.hapticsEnabled  == true)
        #expect(sut.soundsEnabled   == true)
        #expect(sut.quietHoursOn    == false)
        #expect(sut.quietHoursStart == 21)
        #expect(sut.quietHoursEnd   == 7)
    }
}
