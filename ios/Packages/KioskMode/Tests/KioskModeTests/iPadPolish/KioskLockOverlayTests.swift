import Testing
import Foundation
@testable import KioskMode

// MARK: - KioskLockOverlay tests

@Suite("KioskLockOverlay §22")
@MainActor
struct KioskLockOverlayTests {

    // MARK: - KioskLockOverlayConfig defaults

    @Test("Default config uses attract mode")
    func defaultModeIsAttract() {
        let config = KioskLockOverlayConfig(businessName: "Acme")
        #expect(config.mode == .attract)
    }

    @Test("Default config icon is bolt.fill")
    func defaultIconIsBolt() {
        let config = KioskLockOverlayConfig(businessName: "Acme")
        #expect(config.iconSystemName == "bolt.fill")
    }

    @Test("Config stores business name correctly")
    func configStoresBusinessName() {
        let config = KioskLockOverlayConfig(businessName: "My Shop")
        #expect(config.businessName == "My Shop")
    }

    @Test("Config stores tagline when provided")
    func configStoresTagline() {
        let config = KioskLockOverlayConfig(businessName: "Acme", tagline: "Fix anything")
        #expect(config.tagline == "Fix anything")
    }

    @Test("Config tagline is nil when not provided")
    func configTaglineNilByDefault() {
        let config = KioskLockOverlayConfig(businessName: "Acme")
        #expect(config.tagline == nil)
    }

    @Test("Config stores blackout mode correctly")
    func configStoresBlackoutMode() {
        let config = KioskLockOverlayConfig(businessName: "Acme", mode: .blackout)
        #expect(config.mode == .blackout)
    }

    @Test("Config stores custom icon system name")
    func configStoresCustomIcon() {
        let config = KioskLockOverlayConfig(businessName: "Acme", iconSystemName: "wrench.fill")
        #expect(config.iconSystemName == "wrench.fill")
    }

    // MARK: - KioskLockMode equality

    @Test("KioskLockMode equality: attract equals attract")
    func attractEqualsAttract() {
        #expect(KioskLockMode.attract == .attract)
    }

    @Test("KioskLockMode equality: blackout equals blackout")
    func blackoutEqualsBlackout() {
        #expect(KioskLockMode.blackout == .blackout)
    }

    @Test("KioskLockMode inequality: attract != blackout")
    func attractNotBlackout() {
        #expect(KioskLockMode.attract != .blackout)
    }

    // MARK: - KioskLockOverlayConfig Equatable

    @Test("Two identical configs are equal")
    func identicalConfigsEqual() {
        let a = KioskLockOverlayConfig(
            businessName: "Shop", tagline: "Open", iconSystemName: "star", mode: .attract
        )
        let b = KioskLockOverlayConfig(
            businessName: "Shop", tagline: "Open", iconSystemName: "star", mode: .attract
        )
        #expect(a == b)
    }

    @Test("Configs with different business names are not equal")
    func differentBusinessNamesNotEqual() {
        let a = KioskLockOverlayConfig(businessName: "Shop A")
        let b = KioskLockOverlayConfig(businessName: "Shop B")
        #expect(a != b)
    }

    @Test("Configs with different modes are not equal")
    func differentModesNotEqual() {
        let a = KioskLockOverlayConfig(businessName: "Shop", mode: .attract)
        let b = KioskLockOverlayConfig(businessName: "Shop", mode: .blackout)
        #expect(a != b)
    }

    @Test("Configs with different taglines are not equal")
    func differentTaglinesNotEqual() {
        let a = KioskLockOverlayConfig(businessName: "Shop", tagline: "Tag A")
        let b = KioskLockOverlayConfig(businessName: "Shop", tagline: "Tag B")
        #expect(a != b)
    }
}
