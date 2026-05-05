import SwiftUI
import DesignSystem

// MARK: - ExportKind

/// The four top-level sections shown in the sidebar on iPad.
public enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case onDemand  = "on_demand"
    case scheduled = "scheduled"
    case gdpr      = "gdpr"
    case settings  = "settings"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onDemand:  return "On-Demand"
        case .scheduled: return "Scheduled"
        case .gdpr:      return "GDPR"
        case .settings:  return "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .onDemand:  return "arrow.down.circle.fill"
        case .scheduled: return "calendar.badge.clock"
        case .gdpr:      return "person.badge.shield.checkmark.fill"
        case .settings:  return "gearshape.2.fill"
        }
    }

    public var accessibilityHint: String {
        switch self {
        case .onDemand:  return "View and trigger on-demand exports"
        case .scheduled: return "Manage recurring export schedules"
        case .gdpr:      return "Export or erase customer personal data"
        case .settings:  return "Export and import app settings"
        }
    }
}

// MARK: - ExportKindSidebar

/// iPad sidebar column — lists the four export kinds with Liquid Glass chrome.
/// Gated to non-compact: always embedded inside `NavigationSplitView`'s
/// `sidebar` column on iPad, never shown standalone on iPhone.
public struct ExportKindSidebar: View {

    @Binding var selection: ExportKind?

    public init(selection: Binding<ExportKind?>) {
        self._selection = selection
    }

    public var body: some View {
        List(ExportKind.allCases, selection: $selection) { kind in
            sidebarRow(kind)
                .tag(kind)
        }
        .listStyle(.sidebar)
        .navigationTitle("Data Export")
        .exportInlineTitleMode()
        .exportToolbarBackground()
        .accessibilityLabel("Export kind selector")
    }

    private func sidebarRow(_ kind: ExportKind) -> some View {
        Label {
            Text(kind.displayName)
                .font(.body)
        } icon: {
            Image(systemName: kind.systemImage)
                .foregroundStyle(iconColor(for: kind))
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .hoverEffect(.highlight)
        .accessibilityLabel(kind.displayName)
        .accessibilityHint(kind.accessibilityHint)
        .accessibilityAddTraits(selection == kind ? .isSelected : [])
    }

    private func iconColor(for kind: ExportKind) -> Color {
        switch kind {
        case .onDemand:  return .accentColor
        case .scheduled: return Color.blue
        case .gdpr:      return Color.orange
        case .settings:  return Color.secondary
        }
    }
}
