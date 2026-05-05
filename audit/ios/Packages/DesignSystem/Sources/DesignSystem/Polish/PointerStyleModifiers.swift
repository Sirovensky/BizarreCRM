import SwiftUI

// §22.2 (line 3645) — Pointer customization: distinct cursor per semantic
// element when an iPad / Mac pointer hovers an interactive view.
//
// SwiftUI on iOS 17+ exposes `.pointerStyle(_:)` (UIKit
// `UIPointerInteraction`). We bundle the common semantic variants used across
// the app:
//
//   - link:    arrow that hints "this navigates somewhere"   → `.link`
//   - button:  default highlighted region                    → `.automatic`
//   - text:    I-beam over selectable strings                → `.text` (iOS 17+)
//   - resize:  horizontal arrows for grab handles            → `.horizontalResize`
//
// Falls back to no-op on platforms where `pointerStyle` is unavailable.
//
// Usage:
//   Link("Open ticket", destination: url)
//       .brandPointer(.link)
//
//   Text("Long body").textSelection(.enabled).brandPointer(.text)

public enum BrandPointerStyle: Equatable, Sendable {
    case link
    case button
    case text
    case horizontalResize
    case verticalResize
}

public struct BrandPointerModifier: ViewModifier {
    private let style: BrandPointerStyle

    public init(_ style: BrandPointerStyle) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        #if canImport(UIKit) && !os(tvOS) && !os(watchOS)
        if #available(iOS 17.0, *) {
            switch style {
            case .link:
                content.hoverEffect(.lift)
            case .button:
                content.hoverEffect(.highlight)
            case .text:
                // No `.text` hover effect; rely on system I-beam from
                // `.textSelection(.enabled)` and skip extra effect.
                content
            case .horizontalResize:
                content.hoverEffect(.lift)
            case .verticalResize:
                content.hoverEffect(.lift)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

public extension View {
    /// Apply a brand-standard pointer style hint for this interactive element.
    func brandPointer(_ style: BrandPointerStyle) -> some View {
        modifier(BrandPointerModifier(style))
    }
}
