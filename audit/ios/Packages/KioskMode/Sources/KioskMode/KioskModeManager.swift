import Foundation
import Observation

// MARK: - KioskModeManager

/// §55 Kiosk mode state manager.
/// Persists current mode in UserDefaults.
@Observable
@MainActor
public final class KioskModeManager {
    // MARK: - Public state

    public private(set) var currentMode: KioskMode
    public var config: KioskConfig

    // MARK: - Private

    private let defaults: UserDefaults

    static let modeKey = "kiosk_mode"
    static let configKey = "kiosk_config"

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore persisted mode
        if let raw = defaults.string(forKey: KioskModeManager.modeKey),
           let mode = KioskMode(rawValue: raw) {
            self.currentMode = mode
        } else {
            self.currentMode = .off
        }

        // Restore persisted config
        if let data = defaults.data(forKey: KioskModeManager.configKey),
           let config = try? JSONDecoder().decode(KioskConfig.self, from: data) {
            self.config = config
        } else {
            self.config = KioskConfig()
        }
    }

    // MARK: - Mode transitions

    public func setMode(_ mode: KioskMode) {
        currentMode = mode
        defaults.set(mode.rawValue, forKey: KioskModeManager.modeKey)
    }

    public func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: KioskModeManager.configKey)
        }
    }

    // MARK: - Derived

    public var isKioskActive: Bool {
        currentMode != .off
    }
}
