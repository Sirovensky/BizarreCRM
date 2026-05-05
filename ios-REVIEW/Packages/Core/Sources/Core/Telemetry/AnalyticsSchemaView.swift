#if canImport(UIKit)
import SwiftUI

// §71 Privacy-first analytics — schema transparency view

// MARK: — AnalyticsSchemaView

/// Displays every analytics event and its property shape to the user.
///
/// Reached via Settings → Privacy → "View what's shared".
public struct AnalyticsSchemaView: View {

    @State private var searchText = ""

    private var groupedEvents: [(AnalyticsCategory, [AnalyticsEvent])] {
        let filtered: [AnalyticsEvent] = searchText.isEmpty
            ? AnalyticsEvent.allCases
            : AnalyticsEvent.allCases.filter {
                $0.rawValue.localizedCaseInsensitiveContains(searchText)
            }

        return AnalyticsCategory.allCases.compactMap { category in
            let events = filtered.filter { $0.category == category }
            return events.isEmpty ? nil : (category, events)
        }
    }

    public init() {}

    public var body: some View {
        List {
            privacyBanner
            ForEach(groupedEvents, id: \.0) { category, events in
                Section(header: Text(category.displayName)) {
                    ForEach(events, id: \.self) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("What's Shared")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search events")
    }

    // MARK: — Sub-views

    private var privacyBanner: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("No personal data is ever sent", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Text("Events contain only anonymized usage patterns — no names, emails, phone numbers, or financial data. Session IDs are rotated on each launch and are never tied to your identity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: — EventRow

    private struct EventRow: View {
        let event: AnalyticsEvent

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                Text(event.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityLabel("Event: \(event.rawValue), category: \(event.category.displayName)")
        }
    }
}

// MARK: — AnalyticsCategory display name

private extension AnalyticsCategory {
    var displayName: String {
        switch self {
        case .appLifecycle: return "App Lifecycle"
        case .navigation:   return "Navigation"
        case .auth:         return "Authentication"
        case .domain:       return "Business Actions"
        case .hardware:     return "Hardware"
        case .marketing:    return "Marketing"
        case .survey:       return "Surveys"
        case .settings:     return "Settings"
        case .support:      return "Help & Support"
        case .error:        return "Errors & Crashes"
        }
    }
}

#endif
