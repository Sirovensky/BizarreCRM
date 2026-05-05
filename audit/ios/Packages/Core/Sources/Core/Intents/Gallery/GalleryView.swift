#if os(iOS)
import SwiftUI
import AppIntents

/// Admin Settings → Shortcuts → Gallery.
///
/// Lists every registered App Intent with a description and an "Add to Siri" button
/// that deep-links to the Shortcuts app with the intent pre-filled.
///
/// iPhone: single-column list.
/// iPad:   2-column lazy grid.
@available(iOS 16, *)
public struct GalleryView: View {

    // MARK: - Model

    public struct IntentEntry: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let systemImage: String
        public let shortcutsURL: URL?

        public init(
            id: String,
            title: String,
            subtitle: String,
            systemImage: String,
            shortcutsURL: URL? = nil
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.systemImage = systemImage
            self.shortcutsURL = shortcutsURL
        }
    }

    // MARK: - Entries

    public static let defaultEntries: [IntentEntry] = [
        .init(
            id: "new-ticket",
            title: "New Ticket",
            subtitle: "Create a new repair ticket.",
            systemImage: "ticket",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "find-customer",
            title: "Find Customer",
            subtitle: "Find customers by name or phone number.",
            systemImage: "person.fill.questionmark",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "next-appointment",
            title: "Next Appointment",
            subtitle: "Tell me my next appointment.",
            systemImage: "calendar",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "todays-revenue",
            title: "Today's Revenue",
            subtitle: "Speak today's total revenue.",
            systemImage: "dollarsign.circle",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "clock-in",
            title: "Clock In",
            subtitle: "Clock in to start your shift.",
            systemImage: "clock.fill",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "clock-out",
            title: "Clock Out",
            subtitle: "Clock out to end your shift.",
            systemImage: "clock",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "open-pos",
            title: "Open POS",
            subtitle: "Open the Point of Sale screen.",
            systemImage: "cart",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "open-tickets",
            title: "Open Tickets",
            subtitle: "Open the repair tickets list.",
            systemImage: "wrench.and.screwdriver",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "open-dashboard",
            title: "Open Dashboard",
            subtitle: "Open the main dashboard.",
            systemImage: "gauge.medium",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
        .init(
            id: "open-cash-drawer",
            title: "Open Cash Drawer",
            subtitle: "Open the connected cash drawer.",
            systemImage: "rectangle.and.hand.point.up.left",
            shortcutsURL: URL(string: "shortcuts://shortcuts")
        ),
    ]

    // MARK: - State

    private let entries: [IntentEntry]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL

    public init(entries: [IntentEntry] = GalleryView.defaultEntries) {
        self.entries = entries
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if sizeClass == .compact {
                iPhoneList
            } else {
                iPadGrid
            }
        }
        .navigationTitle("Shortcuts Gallery")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - iPhone layout

    private var iPhoneList: some View {
        List {
            ForEach(entries) { entry in
                GalleryRow(entry: entry) {
                    openShortcuts(for: entry)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - iPad layout

    private var iPadGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { entry in
                    GalleryCard(entry: entry) {
                        openShortcuts(for: entry)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func openShortcuts(for entry: IntentEntry) {
        if let url = entry.shortcutsURL {
            openURL(url)
        }
    }
}

// MARK: - GalleryRow (iPhone)

@available(iOS 16, *)
private struct GalleryRow: View {
    let entry: GalleryView.IntentEntry
    let onAddToSiri: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onAddToSiri) {
                Text("Add to Siri")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(entry.title) to Siri")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title). \(entry.subtitle)")
        .accessibilityHint("Double-tap Add to Siri to configure in Shortcuts.")
    }
}

// MARK: - GalleryCard (iPad)

@available(iOS 16, *)
private struct GalleryCard: View {
    let entry: GalleryView.IntentEntry
    let onAddToSiri: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: entry.systemImage)
                    .font(.title)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Spacer()
            }

            Text(entry.title)
                .font(.headline)

            Text(entry.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button(action: onAddToSiri) {
                Label("Add to Siri", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Add \(entry.title) to Siri")
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title). \(entry.subtitle)")
        .accessibilityHint("Double-tap Add to Siri to configure in Shortcuts.")
    }
}

// MARK: - Preview

@available(iOS 16, *)
#Preview("iPhone") {
    NavigationStack {
        GalleryView()
    }
    .environment(\.horizontalSizeClass, .compact)
}

@available(iOS 16, *)
#Preview("iPad") {
    NavigationStack {
        GalleryView()
    }
    .environment(\.horizontalSizeClass, .regular)
}
#endif
