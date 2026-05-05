import Testing
@testable import Core

// §77 Environment & Build Flavor helpers — unit tests for FeatureFlagResolver
//
// Coverage targets:
//   - UserDefaults override wins over every lower layer (layer 1)
//   - Build-flavor override wins when no UserDefaults key is set (layer 2)
//   - Remote-config value used when no local overrides exist (layer 3)
//   - FeatureFlag.defaultValue is the final fallback (layer 4)
//   - snapshot() returns all flags
//   - Development-flavor forced flags
//   - Staging-flavor forced flags
//   - Production passes through to remote / default

// MARK: - Test doubles

/// In-memory UserDefaults replacement.
final class StubUserDefaults: UserDefaultsProvider, @unchecked Sendable {
    private var store: [String: Bool] = [:]

    func set(_ value: Bool, forKey key: String) {
        store[key] = value
    }

    func boolIfPresent(forKey key: String) -> Bool? {
        store[key]
    }
}

/// Controllable remote config stub.
struct StubRemoteConfig: RemoteConfigProvider {
    private let values: [FeatureFlag: Bool]

    init(_ values: [FeatureFlag: Bool] = [:]) {
        self.values = values
    }

    func value(for flag: FeatureFlag) -> Bool? {
        values[flag]
    }
}

// MARK: - Helper

private func makeResolver(
    flavor: BuildFlavor,
    defaults: UserDefaultsProvider = StubUserDefaults(),
    remote: any RemoteConfigProvider = StubRemoteConfig()
) -> FeatureFlagResolver {
    FeatureFlagResolver(flavor: flavor, defaults: defaults, remoteConfig: remote)
}

// MARK: - Tests

@Suite("FeatureFlagResolver — layer priority")
struct FeatureFlagResolverLayerTests {

    @Test("UserDefaults override (true) beats flavor override")
    func userDefaultsOverrideTrue() {
        // .development turns debugDrawer ON by flavor; but a UD override of false wins
        let ud = StubUserDefaults()
        ud.set(false, forKey: FeatureFlagResolver.userDefaultsKeyPrefix + FeatureFlag.debugDrawer.rawValue)
        let resolver = makeResolver(flavor: .development, defaults: ud)
        #expect(resolver.isEnabled(.debugDrawer) == false)
    }

    @Test("UserDefaults override (false) beats remote config true")
    func userDefaultsOverrideFalseBeatsRemote() {
        let ud = StubUserDefaults()
        ud.set(false, forKey: FeatureFlagResolver.userDefaultsKeyPrefix + FeatureFlag.kioskMode.rawValue)
        let remote = StubRemoteConfig([.kioskMode: true])
        let resolver = makeResolver(flavor: .production, defaults: ud, remote: remote)
        #expect(resolver.isEnabled(.kioskMode) == false)
    }

    @Test("UserDefaults override (true) beats remote config false")
    func userDefaultsOverrideTrueBeatsRemoteConfigFalse() {
        let ud = StubUserDefaults()
        ud.set(true, forKey: FeatureFlagResolver.userDefaultsKeyPrefix + FeatureFlag.kioskMode.rawValue)
        let remote = StubRemoteConfig([.kioskMode: false])
        let resolver = makeResolver(flavor: .production, defaults: ud, remote: remote)
        #expect(resolver.isEnabled(.kioskMode) == true)
    }

    @Test("Flavor override beats remote config when no UD key set")
    func flavorOverrideBeatsRemote() {
        // dev forces debugDrawer ON; remote says false
        let remote = StubRemoteConfig([.debugDrawer: false])
        let resolver = makeResolver(flavor: .development, remote: remote)
        #expect(resolver.isEnabled(.debugDrawer) == true)
    }

    @Test("Remote config value used when no UD or flavor override")
    func remoteConfigFallback() {
        let remote = StubRemoteConfig([.kioskMode: true])
        let resolver = makeResolver(flavor: .production, remote: remote)
        #expect(resolver.isEnabled(.kioskMode) == true)
    }

    @Test("FeatureFlag.defaultValue is final fallback")
    func defaultValueFallback() {
        // setupWizard has defaultValue == true; no overrides
        let resolver = makeResolver(flavor: .production)
        #expect(resolver.isEnabled(.setupWizard) == true)

        // newDashboardLayout has defaultValue == false; no overrides
        #expect(resolver.isEnabled(.newDashboardLayout) == false)
    }
}

@Suite("FeatureFlagResolver — build flavor overrides")
struct FeatureFlagResolverFlavorTests {

    @Test("development enables debugDrawer by default")
    func devDebugDrawer() {
        let resolver = makeResolver(flavor: .development)
        #expect(resolver.isEnabled(.debugDrawer))
    }

    @Test("development enables featureFlagOverrides by default")
    func devFeatureFlagOverrides() {
        let resolver = makeResolver(flavor: .development)
        #expect(resolver.isEnabled(.featureFlagOverrides))
    }

    @Test("development enables dataImport by default")
    func devDataImport() {
        let resolver = makeResolver(flavor: .development)
        #expect(resolver.isEnabled(.dataImport))
    }

    @Test("staging enables debugDrawer by default")
    func stagingDebugDrawer() {
        let resolver = makeResolver(flavor: .staging)
        #expect(resolver.isEnabled(.debugDrawer))
    }

    @Test("staging enables featureFlagOverrides by default")
    func stagingFeatureFlagOverrides() {
        let resolver = makeResolver(flavor: .staging)
        #expect(resolver.isEnabled(.featureFlagOverrides))
    }

    @Test("production does NOT force debugDrawer on")
    func productionNoDebugDrawer() {
        // debugDrawer.defaultValue is false; production adds no override
        let resolver = makeResolver(flavor: .production)
        #expect(!resolver.isEnabled(.debugDrawer))
    }

    @Test("production defers to remote for kioskMode")
    func productionDeferToRemote() {
        let remote = StubRemoteConfig([.kioskMode: true])
        let resolver = makeResolver(flavor: .production, remote: remote)
        #expect(resolver.isEnabled(.kioskMode) == true)
    }
}

@Suite("FeatureFlagResolver — snapshot")
struct FeatureFlagResolverSnapshotTests {

    @Test("snapshot contains all flag keys")
    func snapshotContainsAllFlags() {
        let resolver = makeResolver(flavor: .production)
        let snap = resolver.snapshot()
        for flag in FeatureFlag.allCases {
            #expect(snap[flag.rawValue] != nil)
        }
    }

    @Test("snapshot count matches FeatureFlag.allCases")
    func snapshotCountMatchesCaseIterable() {
        let resolver = makeResolver(flavor: .production)
        #expect(resolver.snapshot().count == FeatureFlag.allCases.count)
    }

    @Test("snapshot reflects UserDefaults overrides")
    func snapshotReflectsUDOverrides() {
        let ud = StubUserDefaults()
        ud.set(true, forKey: FeatureFlagResolver.userDefaultsKeyPrefix + FeatureFlag.kioskMode.rawValue)
        let resolver = makeResolver(flavor: .production, defaults: ud)
        let snap = resolver.snapshot()
        #expect(snap[FeatureFlag.kioskMode.rawValue] == true)
    }
}
