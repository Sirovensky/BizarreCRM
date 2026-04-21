import Testing
import Foundation
@testable import Settings
import Core

// MARK: - FeatureFlagManager Tests

@Suite("FeatureFlagManager — override precedence")
@MainActor
struct FeatureFlagManagerTests {

    /// Each test gets a fresh UserDefaults suite to avoid test bleed.
    func makeSUT() -> FeatureFlagManager {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        return FeatureFlagManager(testDefaults: defaults)
    }

    // MARK: - Default fallback

    @Test("Returns compile-time default when no override or server value")
    func defaultFallback() async {
        let sut = makeSUT()
        for flag in FeatureFlag.allCases {
            #expect(sut.isEnabled(flag) == flag.defaultValue,
                    "Flag \(flag.rawValue) should fall back to defaultValue")
        }
    }

    // MARK: - Server value precedence

    @Test("Server value overrides compile-time default")
    func serverOverridesDefault() async {
        let sut = makeSUT()
        let flag = FeatureFlag.loyaltyProgram  // default = false
        sut.updateServerValue(flag, enabled: true)
        #expect(sut.isEnabled(flag) == true)
    }

    @Test("Server value false overrides true default")
    func serverFalseOverridesTrueDefault() async {
        let sut = makeSUT()
        let flag = FeatureFlag.paymentLinks  // default = true
        sut.updateServerValue(flag, enabled: false)
        #expect(sut.isEnabled(flag) == false)
    }

    // MARK: - Local override precedence

    @Test("Local override true beats server false and default false")
    func localOverrideTrueWins() async {
        let sut = makeSUT()
        let flag = FeatureFlag.loyaltyProgram  // default = false
        sut.updateServerValue(flag, enabled: false)
        sut.setLocalOverride(flag, enabled: true)
        #expect(sut.isEnabled(flag) == true)
    }

    @Test("Local override false beats server true and default true")
    func localOverrideFalseWins() async {
        let sut = makeSUT()
        let flag = FeatureFlag.paymentLinks  // default = true
        sut.updateServerValue(flag, enabled: true)
        sut.setLocalOverride(flag, enabled: false)
        #expect(sut.isEnabled(flag) == false)
    }

    @Test("Local override nil removes override — falls back to server value")
    func nilOverrideFallsBackToServer() async {
        let sut = makeSUT()
        let flag = FeatureFlag.loyaltyProgram
        sut.updateServerValue(flag, enabled: true)
        sut.setLocalOverride(flag, enabled: false)
        // Confirm override is active
        #expect(sut.isEnabled(flag) == false)
        // Remove override
        sut.setLocalOverride(flag, enabled: nil)
        // Should now see server value
        #expect(sut.isEnabled(flag) == true)
    }

    @Test("Local override nil with no server falls back to compile-time default")
    func nilOverrideFallsBackToDefault() async {
        let sut = makeSUT()
        let flag = FeatureFlag.kioskMode  // default = false
        sut.setLocalOverride(flag, enabled: true)
        sut.setLocalOverride(flag, enabled: nil)
        #expect(sut.isEnabled(flag) == flag.defaultValue)
    }

    // MARK: - clearAllOverrides

    @Test("clearAllOverrides removes all local overrides")
    func clearAllOverrides() async {
        let sut = makeSUT()
        let flags: [FeatureFlag] = [.loyaltyProgram, .kioskMode, .debugDrawer]
        for flag in flags {
            sut.setLocalOverride(flag, enabled: true)
        }
        sut.clearAllOverrides()
        for flag in flags {
            #expect(!sut.hasLocalOverride(for: flag),
                    "Override for \(flag.rawValue) should be cleared")
        }
    }

    @Test("clearAllOverrides does not affect server values")
    func clearAllOverridesPreservesServerValues() async {
        let sut = makeSUT()
        let flag = FeatureFlag.loyaltyProgram
        sut.updateServerValue(flag, enabled: true)
        sut.setLocalOverride(flag, enabled: false)
        sut.clearAllOverrides()
        // Server value should now be effective
        #expect(sut.isEnabled(flag) == true)
    }

    // MARK: - hasLocalOverride

    @Test("hasLocalOverride returns false when no override set")
    func hasNoOverrideByDefault() async {
        let sut = makeSUT()
        #expect(!sut.hasLocalOverride(for: .loyaltyProgram))
    }

    @Test("hasLocalOverride returns true after setLocalOverride")
    func hasOverrideAfterSet() async {
        let sut = makeSUT()
        sut.setLocalOverride(.loyaltyProgram, enabled: true)
        #expect(sut.hasLocalOverride(for: .loyaltyProgram))
    }

    @Test("hasLocalOverride returns false after nil removal")
    func hasNoOverrideAfterNil() async {
        let sut = makeSUT()
        sut.setLocalOverride(.loyaltyProgram, enabled: true)
        sut.setLocalOverride(.loyaltyProgram, enabled: nil)
        #expect(!sut.hasLocalOverride(for: .loyaltyProgram))
    }

    // MARK: - updateServerValues bulk

    @Test("updateServerValues sets multiple flags at once")
    func bulkServerUpdate() async {
        let sut = makeSUT()
        let dict: [String: Bool] = [
            FeatureFlag.loyaltyProgram.rawValue: true,
            FeatureFlag.kioskMode.rawValue: true,
            FeatureFlag.debugDrawer.rawValue: false,
        ]
        sut.updateServerValues(dict)
        #expect(sut.serverValue(for: .loyaltyProgram) == true)
        #expect(sut.serverValue(for: .kioskMode) == true)
        #expect(sut.serverValue(for: .debugDrawer) == false)
    }

    @Test("updateServerValues ignores unknown keys")
    func bulkServerUpdateIgnoresUnknown() async {
        let sut = makeSUT()
        let dict = ["unknown_flag_xyz": true]
        sut.updateServerValues(dict)
        for flag in FeatureFlag.allCases {
            #expect(sut.serverValue(for: flag) == nil)
        }
    }

    // MARK: - serverValue / localOverride accessors

    @Test("serverValue returns nil before any server update")
    func serverValueNilByDefault() async {
        let sut = makeSUT()
        #expect(sut.serverValue(for: .loyaltyProgram) == nil)
    }

    @Test("localOverride returns nil before any local set")
    func localOverrideNilByDefault() async {
        let sut = makeSUT()
        #expect(sut.localOverride(for: .loyaltyProgram) == nil)
    }

    @Test("localOverride reflects set value exactly")
    func localOverrideReflectsValue() async {
        let sut = makeSUT()
        sut.setLocalOverride(.loyaltyProgram, enabled: false)
        #expect(sut.localOverride(for: .loyaltyProgram) == false)
    }

    // MARK: - All flags coverage

    @Test("isEnabled works for all FeatureFlag cases without crashing")
    func isEnabledForAllCases() async {
        let sut = makeSUT()
        for flag in FeatureFlag.allCases {
            let result = sut.isEnabled(flag)
            #expect(result == flag.defaultValue)
        }
    }
}
