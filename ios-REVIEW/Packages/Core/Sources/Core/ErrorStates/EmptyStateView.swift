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
//
// §63.2 variants:
//   EmptyStateView          — standard empty / filter-empty / search-empty
//   SectionEmptyView        — inline muted copy for sub-list sections (no illustration)
//   PermissionGatedView     — "This feature is disabled for your role"

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

// MARK: — §63.2 Section empty

/// Inline muted copy for sub-list sections within a detail screen.
///
/// No illustration — intentionally lightweight so it doesn't compete with
/// primary content on the same screen.
///
/// ```swift
/// if notes.isEmpty {
///     SectionEmptyView(message: "No notes yet.")
/// }
/// ```
public struct SectionEmptyView: View {
    public let message: String
    public let systemImage: String?

    public init(message: String, systemImage: String? = nil) {
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        Label {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityLabel(message)
    }
}

// MARK: — §63.2 Permission-gated

/// Displayed when a user navigates to a feature their role cannot access.
///
/// ```swift
/// if !currentUser.can(.viewReports) {
///     PermissionGatedView()
/// }
/// ```
public struct PermissionGatedView: View {
    /// Optional override for the body message. Defaults to the standard copy.
    public let message: String
    /// Optional contact-admin action. When provided, shows an "Ask admin"
    /// button beneath the message.
    public var onContactAdmin: (() -> Void)?

    public init(
        message: String = "This feature is disabled for your role.",
        onContactAdmin: (() -> Void)? = nil
    ) {
        self.message = message
        self.onContactAdmin = onContactAdmin
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Feature Unavailable")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onContactAdmin {
                Button("Ask Admin", action: onContactAdmin)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityLabel("Ask your administrator to enable this feature")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["Feature Unavailable", message]
        if onContactAdmin != nil { parts.append("Button: Ask Admin") }
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

#Preview("Section empty — with icon") {
    List {
        Section("Notes") {
            SectionEmptyView(message: "No notes yet.", systemImage: "note.text")
        }
        Section("Files") {
            SectionEmptyView(message: "No files attached.")
        }
    }
}

#Preview("Permission gated — with admin CTA") {
    PermissionGatedView { }
}

#Preview("Permission gated — no CTA") {
    PermissionGatedView(message: "Reports are only available to managers and admins.")
}
#endif
