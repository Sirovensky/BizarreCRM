#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §5 Customer Groups & Tags — GroupAssignSheet
//
// Presents a searchable list of existing (static) groups.
// The caller provides the full group list; selection is confirmed
// via `onAssign([Int64])` which receives the chosen group IDs.
//
// Usage:
//   .sheet(isPresented: $showingAssign) {
//       GroupAssignSheet(groups: vm.groups, selectedGroupIds: vm.assignedGroupIds) { ids in
//           Task { await vm.assignToGroups(ids) }
//       }
//   }

public struct GroupAssignSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// All available static groups (dynamic groups are excluded — members can't be
    /// manually assigned to a dynamic group per server rule).
    private let groups: [CustomerGroup]

    /// The caller-supplied initial selection (group IDs the customer is already in).
    @State private var selectedIds: Set<Int64>

    @State private var searchText: String = ""
    @State private var isSubmitting: Bool = false

    private let title: String
    private let onAssign: ([Int64]) -> Void

    public init(
        title: String = "Assign to Groups",
        groups: [CustomerGroup],
        selectedGroupIds: Set<Int64> = [],
        onAssign: @escaping ([Int64]) -> Void
    ) {
        self.title = title
        self.groups = groups.filter { !$0.isDynamic }
        self._selectedIds = State(wrappedValue: selectedGroupIds)
        self.onAssign = onAssign
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search groups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Assigning…" : "Done") {
                        commitAssignment()
                    }
                    .disabled(isSubmitting)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Group list

    private var groupList: some View {
        List(filteredGroups) { group in
            GroupAssignRow(
                group: group,
                isSelected: selectedIds.contains(group.id)
            ) {
                toggleSelection(groupId: group.id)
            }
            .listRowBackground(Color.bizarreSurface1)
            .listRowInsets(EdgeInsets(
                top: BrandSpacing.sm,
                leading: BrandSpacing.base,
                bottom: BrandSpacing.sm,
                trailing: BrandSpacing.base
            ))
            .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
            .if(!Platform.isCompact) { $0.hoverEffect(.highlight) }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty state (no static groups exist)

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No groups available")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Create a static group first to assign customers.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var filteredGroups: [CustomerGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return groups }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || ($0.description?.localizedCaseInsensitiveContains(q) == true)
        }
    }

    private func toggleSelection(groupId: Int64) {
        if selectedIds.contains(groupId) {
            selectedIds = selectedIds.subtracting([groupId])
        } else {
            selectedIds = selectedIds.union([groupId])
        }
    }

    private func commitAssignment() {
        isSubmitting = true
        onAssign(Array(selectedIds))
        dismiss()
    }
}

// MARK: - GroupAssignRow

private struct GroupAssignRow: View {
    let group: CustomerGroup
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.sm) {
                Circle()
                    .fill(Color.bizarreTeal.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.bizarreTeal)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text(group.displayMemberCount)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.bizarreTeal : Color.bizarreOnSurfaceMuted.opacity(0.5))
            }
            .contentShape(Rectangle())
            .padding(.vertical, BrandSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.displayMemberCount)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - View+if helper (local)

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
#endif
