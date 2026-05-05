import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - LeadPipelineSidebarStatus

/// The five pipeline statuses shown in the iPad sidebar.
/// Matches the values used throughout the Leads package (LeadEditView, LeadPipelineViewModel).
public enum LeadPipelineSidebarStatus: String, CaseIterable, Identifiable, Sendable {
    case new       = "new"
    case contacted = "contacted"
    case qualified = "qualified"
    case converted = "converted"
    case lost      = "lost"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .new:       return "New"
        case .contacted: return "Contacted"
        case .qualified: return "Qualified"
        case .converted: return "Converted"
        case .lost:      return "Lost"
        }
    }

    public var iconName: String {
        switch self {
        case .new:       return "star.fill"
        case .contacted: return "phone.fill"
        case .qualified: return "checkmark.seal.fill"
        case .converted: return "arrow.right.circle.fill"
        case .lost:      return "xmark.circle.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .new:       return .bizarreOrange
        case .contacted: return Color(red: 0.30, green: 0.53, blue: 0.98)
        case .qualified: return Color(red: 0.20, green: 0.75, blue: 0.45)
        case .converted: return Color(red: 0.55, green: 0.33, blue: 0.95)
        case .lost:      return .bizarreError
        }
    }

    /// Maps any raw status string (case-insensitive) from the server to a sidebar status.
    public static func from(status: String?) -> LeadPipelineSidebarStatus {
        guard let s = status?.lowercased() else { return .new }
        return LeadPipelineSidebarStatus(rawValue: s) ?? .new
    }
}

// MARK: - LeadPipelineSidebarViewModel

@MainActor
@Observable
public final class LeadPipelineSidebarViewModel {
    /// Status → count mapping, populated from a lead list.
    public private(set) var counts: [LeadPipelineSidebarStatus: Int] = {
        var d: [LeadPipelineSidebarStatus: Int] = [:]
        for s in LeadPipelineSidebarStatus.allCases { d[s] = 0 }
        return d
    }()

    /// Currently selected status filter; nil = all leads.
    public var selectedStatus: LeadPipelineSidebarStatus? = nil

    /// Update counts from a fresh lead list (immutable — does not mutate the array).
    public func updateCounts(from leads: [Lead]) {
        var newCounts: [LeadPipelineSidebarStatus: Int] = [:]
        for s in LeadPipelineSidebarStatus.allCases { newCounts[s] = 0 }
        for lead in leads {
            let bucket = LeadPipelineSidebarStatus.from(status: lead.status)
            newCounts[bucket, default: 0] += 1
        }
        counts = newCounts
    }

    public func count(for status: LeadPipelineSidebarStatus) -> Int {
        counts[status] ?? 0
    }

    public func totalCount() -> Int {
        counts.values.reduce(0, +)
    }
}

// MARK: - LeadPipelineSidebar

/// iPad-only sidebar column.  Shows a status pipeline with per-status lead counts
/// and Liquid Glass chrome on the navigation layer.
///
/// Usage:
/// ```swift
/// LeadPipelineSidebar(vm: sidebarVM)
/// ```
public struct LeadPipelineSidebar: View {
    @Bindable var vm: LeadPipelineSidebarViewModel

    public init(vm: LeadPipelineSidebarViewModel) {
        self.vm = vm
    }

    public var body: some View {
        List(selection: $vm.selectedStatus) {
            allLeadsRow
            Section("Pipeline") {
                ForEach(LeadPipelineSidebarStatus.allCases) { status in
                    statusRow(status)
                        .tag(status as LeadPipelineSidebarStatus?)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Leads")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                totalBadge
            }
        }
        .accessibilityLabel("Lead pipeline sidebar")
    }

    // MARK: - Rows

    private var allLeadsRow: some View {
        Label {
            HStack {
                Text("All Leads")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: BrandSpacing.sm)
                countBadge(vm.totalCount(), tint: nil)
            }
        } icon: {
            Image(systemName: "list.bullet")
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityHidden(true)
        }
        .tag(nil as LeadPipelineSidebarStatus?)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("All Leads, \(vm.totalCount()) total")
    }

    private func statusRow(_ status: LeadPipelineSidebarStatus) -> some View {
        Label {
            HStack {
                Text(status.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: BrandSpacing.sm)
                countBadge(vm.count(for: status), tint: status.accentColor)
            }
        } icon: {
            Image(systemName: status.iconName)
                .foregroundStyle(status.accentColor)
                .accessibilityHidden(true)
        }
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(status.displayName), \(vm.count(for: status)) leads")
    }

    private func countBadge(_ n: Int, tint: Color?) -> some View {
        Text("\(n)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .brandGlass(.regular, in: Capsule(), tint: tint)
            .accessibilityHidden(true)
    }

    private var totalBadge: some View {
        BrandGlassBadge("\(vm.totalCount())", variant: .regular)
            .accessibilityLabel("\(vm.totalCount()) total leads")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("LeadPipelineSidebar") {
    let vm = LeadPipelineSidebarViewModel()
    vm.updateCounts(from: [
        Lead(id: 1, status: "new"),
        Lead(id: 2, status: "new"),
        Lead(id: 3, status: "contacted"),
        Lead(id: 4, status: "qualified"),
        Lead(id: 5, status: "converted"),
        Lead(id: 6, status: "lost"),
        Lead(id: 7, status: "lost"),
    ])
    return NavigationSplitView {
        LeadPipelineSidebar(vm: vm)
    } detail: {
        Text("Select a status")
    }
}
#endif
