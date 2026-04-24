import Foundation

// MARK: - LowStockThreshold

/// Immutable value type that encapsulates low-stock threshold configuration.
///
/// Supports a global default threshold and per-item overrides stored by item ID.
/// All mutations return a new copy — never mutate in place.
public struct LowStockThreshold: Sendable, Equatable {

    // MARK: Constants

    /// Minimum allowed threshold value.
    public static let minimumValue: Int = 0
    /// Maximum allowed threshold value.
    public static let maximumValue: Int = 9_999
    /// System-wide default when no override exists.
    public static let systemDefault: Int = 5

    // MARK: Stored properties

    /// Global default threshold applied when no per-item override exists.
    public let globalDefault: Int
    /// Per-item threshold overrides keyed by item ID.
    public let overrides: [Int64: Int]

    // MARK: Init

    /// Creates a threshold configuration.
    /// - Parameters:
    ///   - globalDefault: Threshold applied when no per-item override exists.
    ///     Clamped to `minimumValue...maximumValue`.
    ///   - overrides: Per-item threshold overrides. Values outside the valid range
    ///     are clamped silently.
    public init(globalDefault: Int = LowStockThreshold.systemDefault,
                overrides: [Int64: Int] = [:]) {
        self.globalDefault = Self.clamp(globalDefault)
        self.overrides = overrides.mapValues(Self.clamp)
    }

    // MARK: Threshold resolution

    /// Returns the effective threshold for a given item ID.
    /// Per-item overrides take precedence over the global default.
    public func threshold(forItemId id: Int64) -> Int {
        overrides[id] ?? globalDefault
    }

    // MARK: Non-mutating updates

    /// Returns a new `LowStockThreshold` with the global default changed.
    public func withGlobalDefault(_ value: Int) -> LowStockThreshold {
        LowStockThreshold(globalDefault: value, overrides: overrides)
    }

    /// Returns a new `LowStockThreshold` with the per-item override set.
    public func withOverride(itemId: Int64, threshold: Int) -> LowStockThreshold {
        var updated = overrides
        updated[itemId] = threshold
        return LowStockThreshold(globalDefault: globalDefault, overrides: updated)
    }

    /// Returns a new `LowStockThreshold` with the per-item override removed,
    /// falling back to the global default.
    public func removingOverride(itemId: Int64) -> LowStockThreshold {
        var updated = overrides
        updated.removeValue(forKey: itemId)
        return LowStockThreshold(globalDefault: globalDefault, overrides: updated)
    }

    // MARK: Private helpers

    public static func clampPublic(_ value: Int) -> Int { clamp(value) }

    private static func clamp(_ value: Int) -> Int {
        min(maximumValue, max(minimumValue, value))
    }
}
