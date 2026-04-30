import SwiftUI

// §53 — Optional-field copy
//
// Canonical label suffix and container for optional form fields.
// Provides a consistent "(optional)" indicator, localised and placed
// consistently relative to the field label, so copy never diverges
// across screens.
//
// Usage:
//   TextField("Middle name", text: $middleName)
//       .formOptionalLabel("Middle name")
//
//   // — or as a standalone label alongside an external input —
//   FormOptionalFieldLabel("Website URL")

// MARK: - Localised strings (§27 — no hard-coded copy in views)

extension String {
    /// Localized "(optional)" parenthetical for form field labels.
    static let optionalFieldSuffix = NSLocalizedString(
        "form.field.optional_suffix",
        value: "(optional)",
        comment: "Parenthetical appended to optional form field labels, e.g. 'Middle name (optional)'"
    )
}

// MARK: - Standalone label view

/// A form-field label with an appended "(optional)" suffix styled at reduced
/// contrast so it does not compete with the field value.
///
/// Renders as: **Label**  (optional)
/// Where **Label** uses the `.headline` weight and `(optional)` uses
/// `.caption1` at `.bizarreTextSecondary`.
public struct FormOptionalFieldLabel: View {

    private let label: LocalizedStringKey

    public init(_ label: LocalizedStringKey) {
        self.label = label
    }

    public init(_ label: String) {
        self.label = LocalizedStringKey(label)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(.custom("Roboto-Medium", size: 15, relativeTo: .subheadline))
                .foregroundStyle(Color.bizarreText)

            Text(verbatim: .optionalFieldSuffix)
                .font(.custom("Roboto-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(Color.bizarreTextSecondary)
        }
    }
}

// MARK: - View modifier

/// Pairs a field view with a `FormOptionalFieldLabel` above it, ensuring
/// consistent spacing and eliminating inline label boilerplate.
///
/// Usage:
///   TextField("", text: $website)
///       .formOptionalLabel("Website URL")
public struct FormOptionalLabelModifier: ViewModifier {
    private let label: String

    public init(_ label: String) {
        self.label = label
    }

    public func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            FormOptionalFieldLabel(label)
            content
        }
    }
}

public extension View {
    /// Attach a canonical optional-field label (name + "(optional)" suffix)
    /// above this view (§53).
    func formOptionalLabel(_ label: String) -> some View {
        modifier(FormOptionalLabelModifier(label))
    }
}

// MARK: - LocalizedStringKey convenience

private extension Text {
    init(_ key: String.Type) {
        self.init(verbatim: "")
    }
}

private extension Text {
    static var optionalSuffix: Text {
        Text(verbatim: .optionalFieldSuffix)
            .font(.custom("Roboto-Regular", size: 12, relativeTo: .caption))
            .foregroundStyle(Color.bizarreTextSecondary)
    }
}
