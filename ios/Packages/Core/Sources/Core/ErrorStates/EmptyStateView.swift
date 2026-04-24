import SwiftUI

// §63 — Reusable empty-list / zero-data state view.
//
// Composition:
//   icon (SF Symbol or custom image name)
//   title (short headline)
//   subtitle (optional supporting text)
//   CTA (optional Button)
//
// Plain surface — no glass per CLAUDE.md content rule.

/// A reusable empty-state view for list screens and data containers.
///
/// ```swift
/// EmptyStateView(
///     symbol: "tray",
///     title: "No Tickets",
///     subtitle: "Tickets you create will appear here.",
///     ctaLabel: "New Ticket"
/// ) {
///     router.push(.newTicket)
/// }
/// ```
public struct EmptyStateView: View {

    // MARK: — Configuration

    public struct Config: Sendable {
        public let symbol: String
        public let title: String
        public let subtitle: String?
        public let ctaLabel: String?

        public init(
            symbol: String,
            title: String,
            subtitle: String? = nil,
            ctaLabel: String? = nil
        ) {
            self.symbol = symbol
            self.title = title
            self.subtitle = subtitle
            self.ctaLabel = ctaLabel
        }
    }

    // MARK: — Properties

    public let config: Config
    public let onCTA: (() -> Void)?

    // MARK: — Init

    public init(config: Config, onCTA: (() -> Void)? = nil) {
        self.config = config
        self.onCTA = onCTA
    }

    /// Convenience initialiser for the common case.
    public init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        ctaLabel: String? = nil,
        onCTA: (() -> Void)? = nil
    ) {
        self.config = Config(
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            ctaLabel: ctaLabel
        )
        self.onCTA = onCTA
    }

    // MARK: — Body

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: config.symbol)
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(config.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let ctaLabel = config.ctaLabel, let onCTA {
                Button(ctaLabel, action: onCTA)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: — Accessibility

    private var accessibilityLabel: String {
        var parts = [config.title]
        if let subtitle = config.subtitle { parts.append(subtitle) }
        if let ctaLabel = config.ctaLabel, onCTA != nil {
            parts.append("Button: \(ctaLabel)")
        }
        return parts.joined(separator: ". ")
    }
}

#if DEBUG
#Preview("With CTA") {
    EmptyStateView(
        symbol: "tray",
        title: "No Tickets",
        subtitle: "Tickets you create will appear here.",
        ctaLabel: "New Ticket"
    ) { }
}

#Preview("No subtitle, no CTA") {
    EmptyStateView(symbol: "magnifyingglass", title: "No Results")
}

#Preview("Long subtitle") {
    EmptyStateView(
        symbol: "archivebox",
        title: "Nothing Here Yet",
        subtitle: "Once you start adding customers, their records will show up in this list."
    )
}
#endif
