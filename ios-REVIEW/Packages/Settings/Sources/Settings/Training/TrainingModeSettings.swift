import Foundation
import Observation

// MARK: - TrainingModeSettings

/// Persists the Training Mode enabled flag via the shared App Group suite
/// (`group.com.bizarrecrm`) so that extensions and the host app always read
/// the same value.
///
/// Usage — observe from a SwiftUI view or another `@Observable`:
///
/// ```swift
/// if TrainingModeSettings.shared.isEnabled {
///     TrainingModeBanner()
/// }
/// ```
///
/// The shared instance uses the App Group suite. For tests, inject an
/// ephemeral suite via `init(defaults:)`.
@Observable
@MainActor
public final class TrainingModeSettings: Sendable {

    // MARK: - Singleton

    public static let shared = TrainingModeSettings()

    // MARK: - Keys

    private enum Keys {
        static let isEnabled = "trainingMode.isEnabled"
    }

    // MARK: - Storage

    private let defaults: UserDefaults

    // MARK: - State

    /// Whether Training Mode / Sandbox is currently active.
    /// Writes through to `UserDefaults` immediately.
    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
        }
    }

    // MARK: - Init

    /// Shared-instance init. Uses the App Group suite; falls back to
    /// `.standard` if the suite cannot be created (e.g. in unit test hosts
    /// that have no entitlements).
    private init() {
        let suite = UserDefaults(suiteName: "group.com.bizarrecrm") ?? .standard
        self.defaults = suite
        self.isEnabled = suite.bool(forKey: Keys.isEnabled)
    }

    /// Designated initializer for testing — inject an ephemeral suite to
    /// avoid polluting the real store:
    ///
    /// ```swift
    /// let sut = TrainingModeSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    /// ```
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
    }

    // MARK: - Mutations (explicit API — prefer over direct assignment in tests)

    /// Enables Training Mode and persists the change.
    public func enable() {
        isEnabled = true
    }

    /// Disables Training Mode and persists the change.
    public func disable() {
        isEnabled = false
    }

    /// Toggles Training Mode.
    public func toggle() {
        isEnabled = !isEnabled
    }
}
