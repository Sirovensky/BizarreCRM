import Foundation
import Observation

// §66 — HapticsSettings
// @Observable class persisted to UserDefaults.
// Master toggles for haptics, sounds, and quiet hours window.

// MARK: - HapticsSettings

/// Persistent user preferences for haptics and sounds.
///
/// Observe via SwiftUI's `.environment` or direct `@State` capture.
/// Mutations are written to `UserDefaults` immediately (synchronous).
@Observable
public final class HapticsSettings: @unchecked Sendable {

    // MARK: Shared instance

    public static let shared = HapticsSettings()

    // MARK: UserDefaults keys

    private enum Keys {
        static let hapticsEnabled   = "com.bizarrecrm.haptics.enabled"
        static let soundsEnabled    = "com.bizarrecrm.haptics.soundsEnabled"
        static let quietHoursOn     = "com.bizarrecrm.haptics.quietHoursOn"
        static let quietHoursStart  = "com.bizarrecrm.haptics.quietHoursStart"
        static let quietHoursEnd    = "com.bizarrecrm.haptics.quietHoursEnd"
    }

    // MARK: Stored properties

    /// Master haptics toggle. When `false`, no haptics fire.
    public var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    /// Master sounds toggle. When `false`, no event sounds play.
    public var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }

    /// Whether the quiet hours window is active.
    public var quietHoursOn: Bool {
        didSet { defaults.set(quietHoursOn, forKey: Keys.quietHoursOn) }
    }

    /// Quiet hours start — hour of day (0–23). Default: 21 (9 pm).
    public var quietHoursStart: Int {
        didSet { defaults.set(quietHoursStart, forKey: Keys.quietHoursStart) }
    }

    /// Quiet hours end — hour of day (0–23). Default: 7 (7 am).
    public var quietHoursEnd: Int {
        didSet { defaults.set(quietHoursEnd, forKey: Keys.quietHoursEnd) }
    }

    // MARK: Private

    private let defaults: UserDefaults

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Read persisted values; fall back to sensible defaults.
        let storedHaptics = defaults.object(forKey: Keys.hapticsEnabled) as? Bool
        hapticsEnabled = storedHaptics ?? true

        let storedSounds = defaults.object(forKey: Keys.soundsEnabled) as? Bool
        soundsEnabled = storedSounds ?? true

        let storedQHOn = defaults.object(forKey: Keys.quietHoursOn) as? Bool
        quietHoursOn = storedQHOn ?? false

        let storedQHStart = defaults.object(forKey: Keys.quietHoursStart) as? Int
        quietHoursStart = storedQHStart ?? 21

        let storedQHEnd = defaults.object(forKey: Keys.quietHoursEnd) as? Int
        quietHoursEnd = storedQHEnd ?? 7
    }

    // MARK: Convenience

    /// Resets all settings to default values and persists them.
    public func resetToDefaults() {
        hapticsEnabled  = true
        soundsEnabled   = true
        quietHoursOn    = false
        quietHoursStart = 21
        quietHoursEnd   = 7
    }
}
