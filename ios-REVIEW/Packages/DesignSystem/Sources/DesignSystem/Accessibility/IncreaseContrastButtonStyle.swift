import SwiftUI

// MARK: - §26.5 Increase Contrast — clearer button states (solid vs outlined)
//
// When the user enables "Increase Contrast" at the OS level
// (`@Environment(\.colorSchemeContrast) == .increased`), buttons swap to a
// stronger visual distinction between primary (solid fill) and secondary
// (outlined) states. Default ships the regular brand styling.
//
// Usage:
// ```swift
// Button("Save")  { … }.buttonStyle(.a11yPrimary)
// Button("Cancel"){ … }.buttonStyle(.a11ySecondary)
// ```
//
// Under regular contrast: brand-tinted soft fill / chip styling.
// Under increased contrast: solid `bizarrePrimary` fill + `bizarreOnPrimary`
// text on primary; 1.5pt foreground stroke + transparent fill on secondary.
// This makes the
// hierarchy unambiguous for low-vision users without forcing the look on
// everyone else.

public struct A11yPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let increased = contrast == .increased
        configuration.label
            .padding(.horizontal, increased ? 18 : 16)
            .padding(.vertical, increased ? 12 : 10)
            .foregroundStyle(increased ? Color.bizarreOnPrimary : Color.bizarreOnSurface)
            .background(
                Capsule(style: .continuous)
                    .fill(increased ? Color.bizarrePrimary : Color.bizarreSurface2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

public struct A11ySecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        let increased = contrast == .increased
        configuration.label
            .padding(.horizontal, increased ? 18 : 16)
            .padding(.vertical, increased ? 12 : 10)
            .foregroundStyle(Color.bizarreOnSurface)
            .background(
                Capsule(style: .continuous)
                    .stroke(Color.bizarreOnSurface, lineWidth: increased ? 1.5 : 0.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(increased ? Color.clear : Color.bizarreSurface1)
                    )
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == A11yPrimaryButtonStyle {
    /// Primary button styling that becomes solid `bizarreInk` fill under
    /// "Increase Contrast" and stays brand-soft otherwise.
    public static var a11yPrimary: A11yPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == A11ySecondaryButtonStyle {
    /// Secondary button styling that becomes a 1.5 pt outlined capsule under
    /// "Increase Contrast" and stays surface-filled otherwise.
    public static var a11ySecondary: A11ySecondaryButtonStyle { .init() }
}
