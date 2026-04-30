import SwiftUI

// §53 — Error message animation
//
// Animated inline error label that slides down + fades in when an error
// string appears, and reverses on clear.  Pairs with any field by storing
// the error string in a `@State`/`@Binding` and conditionally passing it.
//
// Usage:
//   @State private var emailError: String? = nil
//
//   TextField("Email", text: $email)
//   FormErrorMessage(emailError)
//
// The view announces itself to VoiceOver as a live region so the user
// hears the error without having to move focus.

public struct FormErrorMessage: View {

    private let message: String?

    public init(_ message: String?) {
        self.message = message
    }

    @State private var isVisible = false

    public var body: some View {
        Group {
            if let message, !message.isEmpty {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .imageScale(.small)
                    Text(message)
                        .font(.custom("Roboto-Regular", size: 12, relativeTo: .caption1))
                }
                .foregroundStyle(Color.bizarreDanger)
                .padding(.top, DesignTokens.Spacing.xs)
                .transition(
                    .asymmetric(
                        insertion: .push(from: .top)
                            .combined(with: .opacity),
                        removal: .push(from: .bottom)
                            .combined(with: .opacity)
                    )
                )
                // Live-region so VoiceOver reads the error automatically.
                .accessibilityLabel(message)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(BrandMotion.errorReveal, value: message)
    }
}

// MARK: - Motion token

extension BrandMotion {
    /// 240 ms ease-out spring — snappy but not jarring for an error reveal.
    /// Reduces to instant when Reduce Motion is active.
    static var errorReveal: Animation {
        @Environment(\.accessibilityReduceMotion) var reduced
        return reduced
            ? .linear(duration: 0)
            : .spring(response: 0.24, dampingFraction: 0.8)
    }
}

// MARK: - View modifier convenience

public struct FormErrorMessageModifier: ViewModifier {
    public let error: String?

    public func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            FormErrorMessage(error)
        }
    }
}

public extension View {
    /// Attach an animated error message below this view.
    ///
    /// Pass `nil` to hide; pass a non-empty string to reveal with a
    /// slide-down / fade-in transition (§53 error animation).
    func formError(_ message: String?) -> some View {
        modifier(FormErrorMessageModifier(error: message))
    }
}
