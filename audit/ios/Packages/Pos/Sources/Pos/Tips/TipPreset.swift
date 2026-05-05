import Foundation

// MARK: - TipPresetValue

/// The value carried by a tip preset — either a percentage (0.0–1.0) or a fixed
/// flat amount in cents. Using an enum prevents the "both fields non-nil" class of
/// bug that plagues plain-struct approaches.
public enum TipPresetValue: Equatable, Hashable, Codable, Sendable {
    /// Percentage of the subtotal, expressed as a fraction (e.g. 0.18 = 18 %).
    case percentage(Double)
    /// Fixed tip amount in cents (e.g. 200 = $2.00).
    case fixedCents(Int)
}

// MARK: - TipPreset

/// §16 — An immutable tip preset shown as a chip in `TipSelectorSheet`.
///
/// Both the built-in defaults and tenant-customised entries share this type.
/// `id` is stable across edits so SwiftUI `ForEach` can diff cheaply.
public struct TipPreset: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Short label displayed on the chip, e.g. "18%" or "$2".
    public let displayName: String
    /// The tip value — percentage fraction or fixed cents.
    public let value: TipPresetValue

    public init(id: UUID = UUID(), displayName: String, value: TipPresetValue) {
        self.id = id
        self.displayName = displayName
        self.value = value
    }
}

// MARK: - Defaults

extension TipPreset {
    /// Standard four-preset row shown when the tenant has not customised tips.
    public static let defaults: [TipPreset] = [
        TipPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                  displayName: "15%",
                  value: .percentage(0.15)),
        TipPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                  displayName: "18%",
                  value: .percentage(0.18)),
        TipPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                  displayName: "20%",
                  value: .percentage(0.20)),
        TipPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                  displayName: "25%",
                  value: .percentage(0.25)),
    ]
}
