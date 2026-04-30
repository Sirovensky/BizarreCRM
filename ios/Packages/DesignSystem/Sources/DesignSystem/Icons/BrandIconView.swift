import SwiftUI

// §30.8 — Canonical icon view that wires BrandIcon + icon sizes + role.
//
// Design rules (§30.8):
//  • SF Symbols primary — > 99 % of glyphs.
//  • Custom glyphs — brand mark only (in BrandMark.imageset, not here).
//  • Fill vs outline — navigation = outline, active = fill.
//  • Sizes — .small 16pt / .medium 20pt / .large 24pt (from DesignTokens.Icon).

/// The three canonical icon sizes from §30.8.
public enum BrandIconSize: Sendable {
    case small   // 16 pt
    case medium  // 20 pt
    case large   // 24 pt

    /// Point size aligned to `DesignTokens.Icon`.
    public var pointSize: CGFloat {
        switch self {
        case .small:  return DesignTokens.Icon.small
        case .medium: return DesignTokens.Icon.medium
        case .large:  return DesignTokens.Icon.large
        }
    }
}

/// Preferred way to render a `BrandIcon` in SwiftUI.
///
/// Automatically picks fill vs outline per `role`, sizes to `size`,
/// and emits a localised `accessibilityLabel`.
///
/// ```swift
/// BrandIconView(.ticket, size: .medium, role: .navigation)
/// BrandIconView(.ticket, size: .medium, role: .active)   // fill variant
/// ```
public struct BrandIconView: View {

    public let icon: BrandIcon
    public let size: BrandIconSize
    public let role: BrandIconRole
    /// Optional tint override. Defaults to `.primary`.
    public var tint: Color

    public init(
        _ icon: BrandIcon,
        size: BrandIconSize = .medium,
        role: BrandIconRole = .navigation,
        tint: Color = .primary
    ) {
        self.icon = icon
        self.size = size
        self.role = role
        self.tint = tint
    }

    public var body: some View {
        Image(systemName: icon.resolvedSymbolName(for: role))
            .font(.system(size: size.pointSize, weight: .regular, design: .default))
            .foregroundStyle(tint)
            .accessibilityLabel(icon.accessibilityLabel)
    }
}

// MARK: — Convenience View extension

public extension View {
    /// Adds a `BrandIconView` as a leading label icon inline with text.
    ///
    /// ```swift
    /// Text("Tickets")
    ///     .leadingIcon(.ticket, size: .medium)
    /// ```
    func leadingIcon(
        _ icon: BrandIcon,
        size: BrandIconSize = .medium,
        role: BrandIconRole = .navigation,
        tint: Color = .secondary
    ) -> some View {
        Label {
            self
        } icon: {
            BrandIconView(icon, size: size, role: role, tint: tint)
        }
    }
}

#if DEBUG
#Preview("BrandIconView — size ladder") {
    HStack(spacing: 24) {
        BrandIconView(.ticket, size: .small,  role: .navigation)
        BrandIconView(.ticket, size: .medium, role: .navigation)
        BrandIconView(.ticket, size: .large,  role: .navigation)
        BrandIconView(.ticket, size: .small,  role: .active,     tint: .orange)
        BrandIconView(.ticket, size: .medium, role: .active,     tint: .orange)
        BrandIconView(.ticket, size: .large,  role: .active,     tint: .orange)
    }
    .padding()
}

#Preview("BrandIconView — fill vs outline") {
    VStack(spacing: 16) {
        ForEach([BrandIcon.customer, .invoice, .message, .bell, .star], id: \.rawValue) { icon in
            HStack(spacing: 16) {
                BrandIconView(icon, size: .medium, role: .navigation)
                BrandIconView(icon, size: .medium, role: .active, tint: .orange)
                Text(icon.accessibilityLabel)
                    .font(.caption)
                Spacer()
            }
        }
    }
    .padding()
}

#Preview("leadingIcon modifier") {
    List {
        Text("Tickets").leadingIcon(.ticket)
        Text("Customers").leadingIcon(.customer)
        Text("Inventory").leadingIcon(.shippingBox)
        Text("Active ticket").leadingIcon(.ticket, role: .active, tint: .orange)
    }
}
#endif
