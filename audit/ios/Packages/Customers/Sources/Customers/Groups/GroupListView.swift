#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §5 Customer Groups & Tags — Group List screen
// iPhone: NavigationStack + List
// iPad:   NavigationSplitView sidebar/detail

public struct GroupListView: View {

    @State private var vm: GroupListViewModel
    @State private var selectedGroupId: Int64?
    @State private var compactPath: [Int64] = []
    private let repo: CustomerGroupsRepository

    public init(repo: CustomerGroupsRepository) {
        self.repo = repo
        _vm = State(wrappedValue: GroupListViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            groupListBody(onSelect: { id in compactPath.append(id) })
                .navigationTitle("Customer Groups")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { addToolbarItem }
                .sheet(isPresented: $vm.showingCreate) {
                    CreateGroupSheet(vm: vm)
                }
                .navigationDestination(for: Int64.self) { id in
                    GroupDetailView(repo: repo, groupId: id)
                }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        NavigationSplitView {
            groupListBody(onSelect: { id in selectedGroupId = id })
                .navigationTitle("Customer Groups")
                .navigationBarTitleDisplayMode(.large)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 480)
                .toolbar { addToolbarItem }
                .sheet(isPresented: $vm.showingCreate) {
                    CreateGroupSheet(vm: vm)
                }
        } detail: {
            if let id = selectedGroupId {
                NavigationStack {
                    GroupDetailView(repo: repo, groupId: id)
                }
            } else {
                emptyDetailPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared list body

    @ViewBuilder
    private func groupListBody(onSelect: @escaping (Int64) -> Void) -> some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                groupErrorState(message: err)
            } else if vm.groups.isEmpty {
                groupEmptyState
            } else {
                groupList(onSelect: onSelect)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
    }

    private func groupList(onSelect: @escaping (Int64) -> Void) -> some View {
        List(selection: Platform.isCompact ? .constant(nil) : Binding(
            get: { selectedGroupId },
            set: { if let id = $0 { selectedGroupId = id } }
        )) {
            ForEach(vm.groups) { group in
                GroupRowView(group: group)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(group.id) }
                    .listRowBackground(Color.bizarreSurface1)
                    .listRowInsets(EdgeInsets(
                        top: BrandSpacing.sm,
                        leading: BrandSpacing.base,
                        bottom: BrandSpacing.sm,
                        trailing: BrandSpacing.base
                    ))
                    .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                    .if(!Platform.isCompact) {
                        $0.hoverEffect(.highlight)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await vm.deleteGroup(id: group.id) }
                                } label: {
                                    Label("Delete group", systemImage: "trash")
                                }
                            }
                    }
                    .if(Platform.isCompact) {
                        $0.swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.deleteGroup(id: group.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Toolbar

    private var addToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { vm.showingCreate = true } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New group")
        }
    }

    // MARK: - Empty / Error states

    private var groupEmptyState: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No customer groups yet")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap + to create your first group.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupErrorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
            Text("Failed to load groups")
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

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Select a group")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Group row

private struct GroupRowView: View {
    let group: CustomerGroup

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Circle()
                .fill(Color.bizarreTeal.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: group.isDynamic ? "gearshape.fill" : "person.3.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.bizarreTeal)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: BrandSpacing.xs) {
                    Text(group.displayMemberCount)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if group.isDynamic {
                        Text("· Dynamic")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreTeal)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name), \(group.displayMemberCount)\(group.isDynamic ? ", dynamic" : "")")
    }
}

// MARK: - Create group sheet

private struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: GroupListViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $vm.newGroupName)
                        .font(.brandBodyMedium())
                        .autocorrectionDisabled()
                        .accessibilityLabel("Group name")

                    TextField("Description (optional)", text: $vm.newGroupDescription, axis: .vertical)
                        .font(.brandBodyMedium())
                        .lineLimit(3...6)
                        .accessibilityLabel("Group description")
                } header: {
                    Text("Group details")
                        .font(.brandLabelSmall())
                }

                if let err = vm.createError {
                    Section {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.cancelCreate() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isCreating ? "Creating…" : "Create") {
                        Task { await vm.submitCreate() }
                    }
                    .disabled(vm.isCreating || vm.newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - View+if helper (local, not exported)

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
