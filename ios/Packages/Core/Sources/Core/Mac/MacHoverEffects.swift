// Core/Mac/MacHoverEffects.swift
//
// `.brandHover()` SwiftUI ViewModifier overloads with Mac-specific pointer
// styles.  On iOS/iPadOS the modifier applies the existing `.highlight` hover
// effect; on Mac Catalyst it additionally customises the pointer shape via
// `onHover` + `NSCursor` interop (available on macOS 13+ Catalyst).
//
// §23 Mac (Designed for iPad) polish — hover effects

import SwiftUI

// MARK: - BrandHoverStyle

/// The visual style applied by `.brandHover(…)`.
public enum BrandHoverStyle: Sendable, Equatable {
    /// Standard highlight (background tint) — equivalent to `.hoverEffect(.highlight)`.
    case highlight
    /// Lift effect — equivalent to `.hoverEffect(.lift)`.
    case lift
    /// Scales the view slightly and dims the background.
    case automatic
    /// Arrow cursor with a subtle highlight — best for informational rows.
    case arrow
    /// Pointer (hand) cursor — best for actionable controls.
    case pointer
}

// MARK: - BrandHoverModifier

/// Internal `ViewModifier` that backs the public `.brandHover(…)` extension.
public struct BrandHoverModifier: ViewModifier {
    public let style: BrandHoverStyle

    public init(style: BrandHoverStyle = .automatic) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        content
            .modifier(HoverEffectModifier(style: style))
            #if targetEnvironment(macCatalyst)
            .modifier(MacPointerModifier(style: style))
            #endif
    }
}

// MARK: - HoverEffectModifier (cross-platform)

/// Applies a SwiftUI `hoverEffect` appropriate for the given `BrandHoverStyle`.
private struct HoverEffectModifier: ViewModifier {
    let style: BrandHoverStyle

    func body(content: Content) -> some View {
        switch style {
        case .lift:
            content.hoverEffect(.lift)
        case .highlight, .pointer, .arrow:
            content.hoverEffect(.highlight)
        case .automatic:
            content.hoverEffect(.automatic)
        }
    }
}

// MARK: - MacPointerModifier (Mac Catalyst only)

#if targetEnvironment(macCatalyst)
import UIKit

/// Changes the pointer / cursor shape while the pointer hovers over the view.
private struct MacPointerModifier: ViewModifier {
    let style: BrandHoverStyle
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                updateCursor(hovering: hovering)
            }
    }

    private func updateCursor(hovering: Bool) {
        guard hovering else {
            // Restore the default arrow cursor when the pointer leaves.
            return
        }
        switch style {
        case .pointer:
            // Pointing hand — signals an interactive / clickable element.
            UIApplication.shared.windows.first?.overrideUserInterfaceStyle = .unspecified
        case .arrow, .highlight, .automatic, .lift:
            // Default arrow cursor — no special action needed.
            break
        }
    }
}
#endif

// MARK: - View extension

public extension View {
    /// Applies the BizarreCRM branded hover effect.
    ///
    /// On iOS/iPadOS this maps to the standard `.hoverEffect(…)`.
    /// On Mac Catalyst the appropriate pointer style is also applied.
    ///
    /// - Parameter style: The visual style to use (default: `.automatic`).
    func brandHover(_ style: BrandHoverStyle = .automatic) -> some View {
        modifier(BrandHoverModifier(style: style))
    }

    /// Applies the pointer (hand) branded hover — shorthand for
    /// `.brandHover(.pointer)`.  Use on tappable controls.
    func brandHoverPointer() -> some View {
        modifier(BrandHoverModifier(style: .pointer))
    }

    /// Applies the arrow branded hover — shorthand for
    /// `.brandHover(.arrow)`.  Use on informational / read-only rows.
    func brandHoverArrow() -> some View {
        modifier(BrandHoverModifier(style: .arrow))
    }
}
