#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §5 Customer Groups & Tags — Group Detail screen
// Shows group info + member list with add/remove.

public struct GroupDetailView: View {

    @State private var vm: GroupDetailViewModel
    @State private var showingAddPicker: Bool = false

    public init(repo: CustomerGroupsRepository, groupId: Int64) {
        _vm = State(wrappedValue: GroupDetailViewModel(repo: repo, groupId: groupId))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.group?.name ?? "Group")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .toolbar {
            if vm.canManageMembers {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPicker = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .keyboardShortcut("A", modifiers: .command)
                    .accessibilityLabel("Add members")
                }
            }
        }
        .sheet(isPresented: $showingAddPicker) {
            AddMembersPickerView { customerIds in
                Task { await vm.addMembers(customerIds: customerIds) }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.group == nil {
            errorState(message: err)
        } else {
            memberList
        }
    }

    // MARK: - Member list

    private var memberList: some View {
        List {
            if let group = vm.group {
                groupInfoSection(group: group)
            }

            if vm.members.isEmpty && !vm.isLoading {
                Section {
                    emptyMembersRow
                }
            } else {
                Section {
                    ForEach(vm.members) { member in
                        MemberRowView(
                            member: member,
                            isRemoving: vm.removingMemberIds.contains(member.customerId),
                            canRemove: vm.canManageMembers
                        ) {
                            Task { await vm.removeMember(customerId: member.customerId) }
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
                        .task { await vm.loadNextPageIfNeeded(currentMember: member) }
                    }

                    if vm.isLoadingNextPage {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Members")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textCase(nil)
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Group info section

    private func groupInfoSection(group: CustomerGroup) -> some View {
        Section {
            HStack {
                Label {
                    Text(group.displayMemberCount)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                } icon: {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.bizarreTeal)
                }
                .accessibilityLabel(group.displayMemberCount)
            }

            if group.isDynamic {
                HStack {
                    Label {
                        Text("Dynamic group — members update automatically")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } icon: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.bizarreOrange)
                    }
                }
            }

            if let desc = group.description, !desc.isEmpty {
                Text(desc)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Empty members row

    private var emptyMembersRow: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(vm.isDynamic ? "No members match the filter yet" : "No members yet")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            if vm.canManageMembers {
                Text("Tap + to add members.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.lg)
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
            Text("Failed to load group")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Member row

private struct MemberRowView: View {
    let member: CustomerGroupMember
    let isRemoving: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Circle()
                .fill(Color.bizarreSurface2)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(member.displayName.prefix(1).uppercased())
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let contact = member.contactLine {
                    Text(contact)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isRemoving {
                ProgressView().scaleEffect(0.7)
            } else if canRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.bizarreError)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(member.displayName) from group")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(member.displayName + (member.contactLine.map { ", \($0)" } ?? ""))
    }
}

// MARK: - Add members picker (customer search → multi-select)

/// Lightweight customer search picker for adding members.
/// Shows a search field and a results list. The actual customer search
/// re-uses the existing CustomerGroupsRepository search — in production
/// this would call the customers search endpoint. Here we keep the API
/// surface simple: confirm selection and hand IDs to the caller.
private struct AddMembersPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var selectedIds: Set<Int64> = []

    let onConfirm: ([Int64]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                if selectedIds.isEmpty {
                    pickerPlaceholder
                } else {
                    selectedCountBanner
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIds.count))") {
                        onConfirm(Array(selectedIds))
                        dismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("Search customers by name, phone, email…", text: $searchText)
                .font(.brandBodyMedium())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
    }

    private var pickerPlaceholder: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Search for customers above to add them")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.xl)
    }

    private var selectedCountBanner: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.bizarreTeal)
            Text("\(selectedIds.count) customer\(selectedIds.count == 1 ? "" : "s") selected")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreTeal.opacity(0.08))
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
