import Foundation

// MARK: - TipPresetStore

/// §16 — Actor-isolated store for tenant-customised tip presets.
///
/// Persists up to 4 presets in `UserDefaults` under the App Group
/// `group.com.bizarrecrm` so both the main app and any extension (e.g.
/// widgets) read a consistent list.
///
/// Fallback behaviour:
/// - If no data is stored yet, `load()` returns `TipPreset.defaults`.
/// - Corrupt/undecodable data is purged and the defaults are returned.
///
/// Migration path: the actor boundary makes swapping to GRDB a one-file
/// change with no API surface impact.
public actor TipPresetStore {
    public static let shared = TipPresetStore()

    // MARK: - Constants

    private static let appGroupID = "group.com.bizarrecrm"
    private static let defaultsKey = "pos_tip_presets"
    /// Hard cap: the sheet shows exactly 4 chips.
    public static let maxPresets = 4

    // MARK: - Storage

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Designated initialiser. Pass a custom `UserDefaults` in unit tests to
    /// avoid touching the real App Group suite.
    public init(defaults: UserDefaults? = nil) {
        if let custom = defaults {
            self.defaults = custom
        } else if let suite = UserDefaults(suiteName: Self.appGroupID) {
            self.defaults = suite
        } else {
            // Simulator / unit-test environments where the group is unavailable.
            self.defaults = .standard
        }
    }

    // MARK: - Public API

    /// Load the persisted presets. Returns `TipPreset.defaults` when no
    /// customisation has been saved.
    public func load() -> [TipPreset] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else {
            return TipPreset.defaults
        }
        do {
            let presets = try decoder.decode([TipPreset].self, from: data)
            return presets.isEmpty ? TipPreset.defaults : presets
        } catch {
            defaults.removeObject(forKey: Self.defaultsKey)
            return TipPreset.defaults
        }
    }

    /// Persist `presets`, clamping to `maxPresets` entries.
    ///
    /// Silently no-ops if encoding fails — the caller should not surface
    /// persistence errors to the cashier.
    public func save(_ presets: [TipPreset]) {
        let clamped = Array(presets.prefix(Self.maxPresets))
        guard let data = try? encoder.encode(clamped) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Reset to factory defaults and remove any saved customisation.
    public func resetToDefaults() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
