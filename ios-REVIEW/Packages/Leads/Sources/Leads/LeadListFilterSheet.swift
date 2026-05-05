#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §9.1 Lead list filter + sort

/// Status filter multi-select + sort sheet for the Leads list.
/// Follows the same glass-bottom-sheet pattern as other list filter sheets.
public enum LeadSortOrder: String, CaseIterable, Sendable {
    case name           = "Name A–Z"
    case nameDesc       = "Name Z–A"
    case createdDesc    = "Newest"
    case createdAsc     = "Oldest"
    case leadScoreDesc  = "Score ↓"
    case leadScoreAsc   = "Score ↑"
    case lastActivity   = "Last activity"
    case nextAction     = "Next action"
}

public struct LeadListFilterSheet: View {
    @Binding var selectedStatuses: Set<String>
    @Binding var sortOrder: LeadSortOrder

    @Environment(\.dismiss) private var dismiss

    private let allStatuses: [String] = [
        "new", "contacted", "scheduled", "qualified", "proposal", "converted", "lost"
    ]

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    // Sort
                    Section {
                        ForEach(LeadSortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                    Spacer()
                                    if sortOrder == order {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.bizarreOrange)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityLabel(order.rawValue + (sortOrder == order ? ". Selected." : ""))
                        }
                    } header: {
                        Text("Sort By").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    // Status filter
                    Section {
                        ForEach(allStatuses, id: \.self) { status in
                            Button {
                                if selectedStatuses.contains(status) {
                                    selectedStatuses.remove(status)
                                } else {
                                    selectedStatuses.insert(status)
                                }
                            } label: {
                                HStack {
                                    Text(status.capitalized)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                    Spacer()
                                    if selectedStatuses.contains(status) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.bizarreOrange)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityLabel(status.capitalized + (selectedStatuses.contains(status) ? ". Selected." : ""))
                        }
                    } header: {
                        HStack {
                            Text("Filter by Status").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            if !selectedStatuses.isEmpty {
                                Button("Clear") { selectedStatuses.removeAll() }
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityLabel("Clear status filters")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Apply filters and close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
