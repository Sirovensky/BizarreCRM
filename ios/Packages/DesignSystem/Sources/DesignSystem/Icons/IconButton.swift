// IconButton.swift — §30 Brand Icon Catalog
//
// A small, uniformly styled button that renders a BrandIcon.
// Enforces minimum tap target (44 pt) via MinTapTargetModifier,
// attaches the icon's VoiceOver label automatically, and applies
// the brand foreground tint so callers don't have to repeat it.
//
// Usage:
//   IconButton(.trash) { viewModel.delete() }
//   IconButton(.filter, isActive: filters.isActive) { showFilters = true }

import SwiftUI

/// A uniform icon-button built on top of ``BrandIcon``.
///
/// - Parameters:
///   - icon: The ``BrandIcon`` to display.
///   - isActive: When `true` the icon renders in `.tint`; otherwise `.secondary`.
///   - action: The closure called on tap.
public struct IconButton: View {

    private let icon: BrandIcon
    private let isActive: Bool
    private let action: () -> Void

    public init(
        _ icon: BrandIcon,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon.image
                .imageScale(.medium)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .accessibilityLabel(icon.accessibilityLabel)
        .buttonStyle(.plain)
        .minTapTarget()
    }
}

// minTapTarget() is provided by §72 Polish/MinTapTargetModifier.swift

// MARK: - Previews

#if DEBUG
#Preview("Icon Button Catalog") {
    VStack(spacing: 16) {
        HStack(spacing: 24) {
            IconButton(.plus) {}
            IconButton(.trash) {}
            IconButton(.xmark) {}
            IconButton(.checkmarkCircleFill) {}
            IconButton(.filter, isActive: false) {}
            IconButton(.filterFill, isActive: true) {}
        }
        HStack(spacing: 24) {
            IconButton(.ticket) {}
            IconButton(.invoice) {}
            IconButton(.customer) {}
            IconButton(.magnifyingGlass) {}
            IconButton(.chevronRight) {}
            IconButton(.ellipsisCircle) {}
        }
    }
    .padding()
}
#endif
