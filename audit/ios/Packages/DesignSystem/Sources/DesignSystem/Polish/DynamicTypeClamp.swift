import SwiftUI

// MARK: - DynamicTypeClamp

/// Clamps the Dynamic Type size for a view hierarchy to a bounded range.
///
/// This prevents very-large Dynamic Type settings from breaking layouts
/// while still respecting user accessibility preferences within a safe range.
///
/// The default range (`xSmall...accessibility3`) is intentionally permissive;
/// callers narrow it when a layout truly cannot accommodate large type.
///
/// **Usage:**
/// ```swift
/// // Allow up to AX2 only — prevents a compact sidebar from overflowing.
/// SidebarCell(item: item)
///     .dynamicTypeClamp(max: .accessibility2)
///
/// // Full custom range:
/// BadgeView()
///     .dynamicTypeClamp(.large ... .xxLarge)
/// ```
public struct DynamicTypeClampModifier: ViewModifier {

    /// Inclusive minimum size.
    public let min: DynamicTypeSize
    /// Inclusive maximum size.
    public let max: DynamicTypeSize

    public func body(content: Content) -> some View {
        content
            .dynamicTypeSize(min ... max)
    }
}

// MARK: - View extension

public extension View {
    /// Clamps the Dynamic Type size to the given closed range.
    ///
    /// - Parameters:
    ///   - range: A `ClosedRange<DynamicTypeSize>` — both bounds are inclusive.
    func dynamicTypeClamp(_ range: ClosedRange<DynamicTypeSize>) -> some View {
        modifier(DynamicTypeClampModifier(min: range.lowerBound, max: range.upperBound))
    }

    /// Clamps Dynamic Type with explicit min and max parameters.
    ///
    /// - Parameters:
    ///   - min: Smallest allowed size. Defaults to `.xSmall`.
    ///   - max: Largest allowed size. No default — must be provided.
    func dynamicTypeClamp(
        min: DynamicTypeSize = .xSmall,
        max: DynamicTypeSize
    ) -> some View {
        modifier(DynamicTypeClampModifier(min: min, max: max))
    }
}
