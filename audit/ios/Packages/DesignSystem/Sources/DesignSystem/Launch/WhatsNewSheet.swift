import SwiftUI

// §68.3 — WhatsNewSheet
// Shown on first launch after a major version bump.
// Fetches content from GET /app/changelog?version=X.Y.Z;
// falls back to bundled placeholder text when offline or on error.

// MARK: - WhatsNewEntry

/// A single release note item.
public struct WhatsNewEntry: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let systemImage: String

    public init(id: UUID = UUID(), title: String, body: String, systemImage: String) {
        self.id          = id
        self.title       = title
        self.body        = body
        self.systemImage = systemImage
    }
}

// MARK: - WhatsNewSheet

/// Sheet shown after a major version update.
///
/// Pass `entries` pre-loaded from the changelog API or from the bundle fallback.
/// The caller is responsible for fetching; this view is presentation-only.
public struct WhatsNewSheet: View {

    private let version: String
    private let entries: [WhatsNewEntry]
    private let onDismiss: () -> Void

    public init(version: String, entries: [WhatsNewEntry], onDismiss: @escaping () -> Void) {
        self.version   = version
        self.entries   = entries
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)

                        Text("What's New in \(version)")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)

                    // Feature list
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: entry.systemImage)
                                .font(.title2)
                                .foregroundStyle(.bizarreOrange)
                                .frame(width: 36)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title)
                                    .font(.headline)
                                Text(entry.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    // CTA
                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .padding(.top, 16)
                    .accessibilityHint("Dismiss release notes and continue to the app")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onDismiss() }
                        .accessibilityHint("Dismiss without reading release notes")
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityLabel("What's new in version \(version)")
    }
}

// MARK: - BundledChangelog

/// Provides a fallback entry set when the server is unreachable.
public enum BundledChangelog {
    public static func fallbackEntries(for version: String) -> [WhatsNewEntry] {
        [
            WhatsNewEntry(
                title: "CoreHaptics Engine",
                body: "Rich haptic feedback for every action — sale completions, scans, clock in/out.",
                systemImage: "iphone.radiowaves.left.and.right"
            ),
            WhatsNewEntry(
                title: "Motion Catalog",
                body: "Smoother, Reduce Motion–aware animations throughout the app.",
                systemImage: "waveform.path"
            ),
            WhatsNewEntry(
                title: "Improved Launch Experience",
                body: "Faster cold start, state restore, and first-run server picker.",
                systemImage: "bolt"
            )
        ]
    }
}

#if DEBUG
#Preview {
    WhatsNewSheet(
        version: "2.0",
        entries: BundledChangelog.fallbackEntries(for: "2.0"),
        onDismiss: {}
    )
}
#endif
