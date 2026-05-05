import Foundation

// §77 Environment & Build Flavor helpers
// FeatureFlagResolver — merges three override layers (highest priority wins):
//
//   1. UserDefaults overrides   (set by in-app debug drawer at runtime)
//   2. Build-flavor overrides   (hardcoded per environment, e.g. debug drawer ON in dev)
//   3. Remote-config stub       (injectable; defaults to FeatureFlagRemoteConfigStub)
//   4. FeatureFlag.defaultValue (final fallback)
//
// Thread safety: the resolver is a struct (value type); its store dependencies
// are Sendable-conformant. Callers on any actor can call `isEnabled(_:)` safely.

// MARK: - RemoteConfigProvider

/// Abstraction over a remote feature-flag source.
///
/// The production implementation will live in the Networking package.
/// The stub below is used when no remote source is registered.
public protocol RemoteConfigProvider: Sendable {
    /// Returns the server-supplied value for `flag`, or `nil` if unknown.
    func value(for flag: FeatureFlag) -> Bool?
}

// MARK: - FeatureFlagRemoteConfigStub

/// No-op stub — always returns `nil`, letting lower layers decide the value.
public struct FeatureFlagRemoteConfigStub: RemoteConfigProvider {
    public init() {}
    public func value(for flag: FeatureFlag) -> Bool? { nil }
}

// MARK: - FeatureFlagResolver

/// Resolves the effective boolean value for a `FeatureFlag` by merging
/// three override layers on top of each flag's conservative default.
public struct FeatureFlagResolver: Sendable {

    // MARK: - Constants

    /// UserDefaults key prefix for manual overrides.
    /// Stored as: `com.bizarrecrm.featureFlag.<rawValue>`
    public static let userDefaultsKeyPrefix = "com.bizarrecrm.featureFlag."

    // MARK: - Dependencies

    private let flavor: BuildFlavor
    private let defaults: UserDefaultsProvider
    private let remoteConfig: any RemoteConfigProvider

    // MARK: - Init

    /// Creates the shared resolver backed by `BuildFlavor.current` and
    /// `UserDefaults.standard`.
    public init(
        flavor: BuildFlavor = .current,
        defaults: UserDefaultsProvider = UserDefaults.standard,
        remoteConfig: any RemoteConfigProvider = FeatureFlagRemoteConfigStub()
    ) {
        self.flavor = flavor
        self.defaults = defaults
        self.remoteConfig = remoteConfig
    }

    // MARK: - Public API

    /// Returns `true` if `flag` should be considered enabled for the current
    /// session, applying all override layers.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        // 1. UserDefaults manual override (highest priority)
        let udKey = Self.userDefaultsKeyPrefix + flag.rawValue
        if let udOverride = defaults.boolIfPresent(forKey: udKey) {
            return udOverride
        }

        // 2. Build-flavor override
        if let flavorOverride = flavorOverride(for: flag) {
            return flavorOverride
        }

        // 3. Remote config
        if let remoteValue = remoteConfig.value(for: flag) {
            return remoteValue
        }

        // 4. Conservative default
        return flag.defaultValue
    }

    /// Returns the effective value for every known flag as a dictionary.
    public func snapshot() -> [String: Bool] {
        Dictionary(
            uniqueKeysWithValues: FeatureFlag.allCases.map { flag in
                (flag.rawValue, isEnabled(flag))
            }
        )
    }

    // MARK: - Private helpers

    /// Hardcoded per-flavor defaults that differ from `FeatureFlag.defaultValue`.
    ///
    /// Returns `nil` to indicate "this flavor has no opinion — fall through".
    private func flavorOverride(for flag: FeatureFlag) -> Bool? {
        switch flavor {
        case .production:
            return nil   // production: never override — trust remote + defaults

        case .staging:
            switch flag {
            case .debugDrawer:          return true
            case .featureFlagOverrides: return true
            default:                    return nil
            }

        case .development:
            switch flag {
            case .debugDrawer:          return true
            case .featureFlagOverrides: return true
            case .dataImport:           return true
            case .dataExport:           return true
            default:                    return nil
            }
        }
    }
}

// MARK: - UserDefaultsProvider

/// Abstraction over `UserDefaults` for testability.
public protocol UserDefaultsProvider: Sendable {
    /// Returns the stored `Bool` for `key`, or `nil` if no value is set.
    func boolIfPresent(forKey key: String) -> Bool?
}

extension UserDefaults: UserDefaultsProvider {
    public func boolIfPresent(forKey key: String) -> Bool? {
        guard object(forKey: key) != nil else { return nil }
        return bool(forKey: key)
    }
}
