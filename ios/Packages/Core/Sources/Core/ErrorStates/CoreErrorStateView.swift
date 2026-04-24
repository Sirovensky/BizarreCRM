import SwiftUI

// §63 — SwiftUI view rendering any `CoreErrorState`.
//
// Visual language:
//  - Content surface uses plain `.background(.quaternary)` — no glass on
//    content per CLAUDE.md ("DON'T USE glass on cards, data tables").
//  - Icon + title + message + optional retry button.
//  - Compact layout appropriate for both inline list placeholders and
//    full-screen error presentations.

/// Renders a `CoreErrorState` with an icon, title, message, and optional
/// retry button.
///
/// ```swift
/// CoreErrorStateView(state: .network, onRetry: { await viewModel.reload() })
/// ```
public struct CoreErrorStateView: View {

    // MARK: — State

    public let state: CoreErrorState

    /// Called when the user taps the primary action button.  When `nil`, no
    /// button is shown even if the state is retryable.
    public let onRetry: (() -> Void)?

    // MARK: — Init

    public init(state: CoreErrorState, onRetry: (() -> Void)? = nil) {
        self.state = state
        self.onRetry = onRetry
    }

    // MARK: — Body

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.symbolName)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(state.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(state.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRetry, state.isRetryable {
                Button(state.retryLabel, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.background.secondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: — Accessibility

    private var accessibilityLabel: String {
        var parts = [state.title, state.message]
        if let _ = onRetry, state.isRetryable {
            parts.append("Button: \(state.retryLabel)")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: — Full-screen wrapper

/// Full-screen centred layout for `CoreErrorStateView`. Use this when the
/// error should occupy an entire navigation destination.
public struct CoreErrorStateScreen: View {
    public let state: CoreErrorState
    public let onRetry: (() -> Void)?

    public init(state: CoreErrorState, onRetry: (() -> Void)? = nil) {
        self.state = state
        self.onRetry = onRetry
    }

    public var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            CoreErrorStateView(state: state, onRetry: onRetry)
                .padding()
        }
    }
}

#if DEBUG
#Preview("Network error") {
    CoreErrorStateView(state: .network) { }
}

#Preview("Server error") {
    CoreErrorStateView(state: .server(status: 503, message: "Service Unavailable")) { }
}

#Preview("Offline") {
    CoreErrorStateView(state: .offline) { }
}

#Preview("Unauthorized") {
    CoreErrorStateView(state: .unauthorized) { }
}

#Preview("Forbidden") {
    CoreErrorStateView(state: .forbidden)
}

#Preview("Rate limited") {
    CoreErrorStateView(state: .rateLimited(retrySeconds: 30)) { }
}

#Preview("Validation") {
    CoreErrorStateView(state: .validation(["email", "phone"]))
}

#Preview("Not found") {
    CoreErrorStateView(state: .notFound)
}

#Preview("Full screen") {
    CoreErrorStateScreen(state: .network) { }
}
#endif
