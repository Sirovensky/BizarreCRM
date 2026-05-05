import SwiftUI
import DesignSystem

// MARK: - RoleSidebar
//
// Leading column of the iPad three-column layout.
// Shows:
//  • Roles list with member-count badge and capability count sub-label
//  • Hover effect + context menu per row (Duplicate, Rename, Delete)
//  • "Create Role" CTA at the bottom of the list
//  • Search field (⌘F) to filter the list
//
// All mutations are delegated upwards via callbacks to keep this view
// free of direct repository access — the owning RolesEditorThreeColumnView
// wires the callbacks to RolesMatrixViewModel.

@MainActor
public struct RoleSidebar: View {

    // MARK: Dependencies

    @State private var viewModel: RolesMatrixViewModel
    @Binding var selectedRoleId: String?

    let onCreateRole: () -> Void
    let onDuplicate: (Role) -> Void
    let onRename: (Role) -> Void
    let onDelete: (Role) -> Void

    // MARK: Internal state

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    // MARK: Filtered list

    private var filteredRoles: [Role] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.roles }
        return viewModel.roles.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: Init

    public init(
        viewModel: RolesMatrixViewModel,
        selectedRoleId: Binding<String?>,
        onCreateRole: @escaping () -> Void,
        onDuplicate: @escaping (Role) -> Void,
        onRename: @escaping (Role) -> Void,
        onDelete: @escaping (Role) -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        _selectedRoleId = selectedRoleId
        self.onCreateRole = onCreateRole
        self.onDuplicate = onDuplicate
        self.onRename = onRename
        self.onDelete = onDelete
    }

    // MARK: Body

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.roles.isEmpty {
                loadingState
            } else if filteredRoles.isEmpty && !searchText.isEmpty {
                emptySearchState
            } else if viewModel.roles.isEmpty {
                emptyRolesState
            } else {
                rolesList
            }
        }
        .navigationTitle("Roles")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search roles")
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            createRoleCTA
        }
    }

    // MARK: Roles list

    @ViewBuilder
    private var rolesList: some View {
        List(filteredRoles, selection: $selectedRoleId) { role in
            roleRow(role)
                .tag(role.id)
                .hoverEffect(.highlight)
                .contextMenu {
                    RoleContextMenu(
                        role: role,
                        onDuplicate: onDuplicate,
                        onRename: onRename,
                        onDelete: onDelete
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onDelete(role) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { onRename(role) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
        }
        .listStyle(.sidebar)
        .animation(.easeInOut(duration: DesignTokens.Motion.quick), value: filteredRoles.map(\.id))
    }

    // MARK: Individual row

    @ViewBuilder
    private func roleRow(_ role: Role) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: role.preset != nil
                  ? "person.crop.circle.badge.checkmark"
                  : "person.crop.circle")
                .foregroundStyle(role.preset != nil ? .blue : .secondary)
                .font(.title3)
                .frame(width: DesignTokens.Touch.minTargetSide * 0.55,
                       height: DesignTokens.Touch.minTargetSide * 0.55)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(role.name)
                    .font(.body)
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text("\(role.capabilities.count) capabilities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Member-count badge — placeholder value until a /users?roleId= endpoint
            // is wired; shows capability count as a proxy today.
            BrandGlassBadge(
                "\(role.capabilities.count)",
                variant: .regular
            )
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.name), \(role.capabilities.count) capabilities")
        .accessibilityAddTraits(selectedRoleId == role.id ? .isSelected : [])
    }

    // MARK: Empty states

    @ViewBuilder
    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView()
            Text("Loading roles…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptySearchState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    @ViewBuilder
    private var emptyRolesState: some View {
        ContentUnavailableView(
            "No Roles Yet",
            systemImage: "person.badge.key",
            description: Text("Create your first role using the button below.")
        )
    }

    // MARK: Create CTA (bottom of sidebar)

    @ViewBuilder
    private var createRoleCTA: some View {
        Button(action: onCreateRole) {
            Label("Create Role", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.accentColor)
        .padding(DesignTokens.Spacing.lg)
        .accessibilityLabel("Create new role")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onCreateRole) {
                Label("New Role", systemImage: "plus")
            }
            .brandGlass(.regular, interactive: true)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Create new role (⌘N)")
        }
    }
}
