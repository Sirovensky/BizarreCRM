// Core/TestFixtures/PreviewTraitsHelper.swift
//
// §31 — PreviewTraitsHelper: composable SwiftUI preview environment helpers.
//
// Provides a lightweight, side-effect-free way to configure common preview
// trait combinations (appearance, size class, Dynamic Type, locale, a11y)
// without pulling in DesignSystem or any snapshot library.
//
// Usage:
//   #Preview("Dark + Large Text") {
//       MyView()
//           .previewTraits(.dark, .accessibilityXXXL)
//   }
//
//   #Preview("RTL compact") {
//       MyView()
//           .previewTraits(.rtl, .compactWidth)
//   }

import SwiftUI

// MARK: - PreviewTrait

/// A single, composable preview environment mutation.
public enum PreviewTrait {
    // MARK: Appearance
    case light
    case dark

    // MARK: Layout direction
    case ltr
    case rtl

    // MARK: Size class
    case compactWidth
    case regularWidth
    case compactHeight
    case regularHeight

    // MARK: Dynamic Type
    case accessibilitySmall     // .small
    case accessibilityMedium    // .medium (default)
    case accessibilityLarge     // .large
    case accessibilityXL        // .extraLarge
    case accessibilityXXL       // .extraExtraLarge
    case accessibilityXXXL      // .extraExtraExtraLarge
    case accessibilityA11yLarge // .accessibilityExtraExtraExtraLarge

    // MARK: Locale
    case locale(Locale)
}

// MARK: - View extension

extension View {

    /// Apply one or more `PreviewTrait` values to this view's SwiftUI environment.
    ///
    /// Traits are applied in declaration order; later traits override earlier ones
    /// when they target the same environment key.
    ///
    /// - Parameter traits: Variadic list of traits to compose.
    /// - Returns: The view with the requested environment overrides applied.
    @ViewBuilder
    public func previewTraits(_ traits: PreviewTrait...) -> some View {
        traits.reduce(AnyView(self)) { view, trait in
            AnyView(view.applyingPreviewTrait(trait))
        }
    }

    // MARK: - Internal single-trait application

    @ViewBuilder
    fileprivate func applyingPreviewTrait(_ trait: PreviewTrait) -> some View {
        switch trait {
        case .light:
            self.preferredColorScheme(.light)
        case .dark:
            self.preferredColorScheme(.dark)

        case .ltr:
            self.environment(\.layoutDirection, .leftToRight)
                .environment(\.locale, Locale(identifier: "en"))
        case .rtl:
            self.environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))

        case .compactWidth:
            self.environment(\.horizontalSizeClass, .compact)
        case .regularWidth:
            self.environment(\.horizontalSizeClass, .regular)
        case .compactHeight:
            self.environment(\.verticalSizeClass, .compact)
        case .regularHeight:
            self.environment(\.verticalSizeClass, .regular)

        case .accessibilitySmall:
            self.environment(\.sizeCategory, .small)
        case .accessibilityMedium:
            self.environment(\.sizeCategory, .medium)
        case .accessibilityLarge:
            self.environment(\.sizeCategory, .large)
        case .accessibilityXL:
            self.environment(\.sizeCategory, .extraLarge)
        case .accessibilityXXL:
            self.environment(\.sizeCategory, .extraExtraLarge)
        case .accessibilityXXXL:
            self.environment(\.sizeCategory, .extraExtraExtraLarge)
        case .accessibilityA11yLarge:
            self.environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)

        case .locale(let loc):
            self.environment(\.locale, loc)
        }
    }
}

// MARK: - PreviewTraitsContainer

/// Wraps a view in a fixed-width container for snapshot-friendliness.
public struct PreviewTraitsContainer<Content: View>: View {
    let width: CGFloat
    let content: Content

    public init(width: CGFloat = 390, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    public var body: some View {
        content
            .frame(width: width)
    }
}
