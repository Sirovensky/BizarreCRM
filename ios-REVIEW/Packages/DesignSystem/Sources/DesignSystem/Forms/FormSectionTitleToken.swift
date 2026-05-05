import SwiftUI

// §53 — Form section title token
//
// Provides a canonical design-token for form section headers so every
// form in the app uses the same typography, colour, spacing, and
// letter-spacing without hand-crafting the style at each call site.
//
// Usage:
//   Section {
//       TextField("Email", text: $email)
//   } header: {
//       FormSectionTitle("Account details")
//   }
//
//   — or imperatively —
//   Text("Billing address")
//       .formSectionTitle()

public struct FormSectionTitle: View {

    private let text: LocalizedStringKey

    public init(_ text: LocalizedStringKey) {
        self.text = text
    }

    public init(_ text: String) {
        self.text = LocalizedStringKey(text)
    }

    public var body: some View {
        Text(text)
            .formSectionTitle()
    }
}

// MARK: - Token modifier

public struct FormSectionTitleModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            // League Spartan SemiBold 13 — §30.4 subheadline slot, form-header weight.
            .font(.custom("LeagueSpartan-SemiBold", size: 13, relativeTo: .subheadline))
            .foregroundStyle(Color.bizarreTextSecondary)
            .textCase(.uppercase)
            .kerning(0.6)
            .padding(.bottom, DesignTokens.Spacing.xs)
    }
}

public extension View {
    /// Style any `Text` view as a canonical form-section title.
    ///
    /// Applies League Spartan SemiBold 13 pt, `.bizarreTextSecondary`,
    /// UPPERCASE, and 0.6 pt letter-spacing — matching the design-token
    /// spec for in-form grouping headers (§53).
    func formSectionTitle() -> some View {
        modifier(FormSectionTitleModifier())
    }
}
