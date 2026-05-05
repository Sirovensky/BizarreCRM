import SwiftUI
import DesignSystem

// MARK: - RolesEditorThreeColumnView
//
// iPad §22 — three-column roles editor:
//   Leading sidebar  : RoleSidebar (role list + member counts + Create CTA)
//   Content column   : RoleDetailView (capability list for selected role)
//   Trailing column  : RoleUsersInspector (users in role + assign/unassign)
//
// Keyboard shortcuts and context-menu actions are provided by
// RolesKeyboardShortcuts and RoleContextMenu respectively.
// Gate with `Platform.isCompact` at the host entry point — this view is
// iPad-only.

@MainActor
public struct RolesEditorThreeColumnView: View {

    // MARK: State

    @State private var viewModel: RolesMatrixViewModel
    @State private var selectedRoleId: String?
    @State private var showCreateSheet = false
    @State private var renameTarget: Role?
    @State private var renameText: String = ""
    @State private var duplicateTarget: Role?
    @State private var deleteTarget: Role?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // MARK: Derived

    private var selectedRole: Role? {
        guard let id = selectedRoleId else { return nil }
        return viewModel.roles.first { $0.id == id }
    }

    // MARK: Init

    public init(viewModel: RolesMatrixViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Leading: role list sidebar
            RoleSidebar(
                viewModel: viewModel,
                selectedRoleId: $selectedRoleId,
                onCreateRole: { showCreateSheet = true },
                onDuplicate: { duplicateTarget = $0 },
                onRename: { renameTarget = $0 },
                onDelete: { deleteTarget = $0 }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            // Content: capability list for selected role
            if let role = selectedRole {
                RoleDetailView(
                    viewModel: RoleDetailViewModel(
                        role: role,
                        repository: viewModel.repository
                    )
                )
                .task { await viewModel.loadRole(id: role.id) }
            } else {
                ContentUnavailableView(
                    "Select a Role",
                    systemImage: "person.badge.key",
                    description: Text("Choose a role from the sidebar to view and edit its capabilities.")
                )
            }
        } detail: {
            // Trailing: users inspector for selected role
            if let role = selectedRole {
                RoleUsersInspector(
                    role: role,
                    repository: viewModel.repository
                )
            } else {
                ContentUnavailableView(
                    "No Role Selected",
                    systemImage: "person.2",
                    description: Text("Select a role to manage its members.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Role", systemImage: "plus")
                }
                .brandGlass(.regular, interactive: true)
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Create new role (⌘N)")
            }
        }
        // Keyboard shortcuts overlay
        .background(
            RolesKeyboardShortcuts(
                selectedRole: selectedRole,
                onNew: { showCreateSheet = true },
                onDuplicate: { if let r = selectedRole { duplicateTarget = r } },
                onRename: { if let r = selectedRole { renameTarget = r } }
            )
        )
        // Create sheet
        .sheet(isPresented: $showCreateSheet) {
            CreateRoleSheet { name, description, preset in
                Task {
                    let caps = preset.map { RolePresets.preset(for: $0)?.capabilities ?? [] } ?? []
                    await viewModel.createRole(
                        name: name,
                        description: description,
                        preset: preset,
                        capabilities: caps
                    )
                    // Auto-select the newly created role
                    if let newRole = viewModel.roles.last {
                        selectedRoleId = newRole.id
                    }
                }
            }
        }
        // Rename alert
        .alert("Rename Role", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Role name", text: $renameText)
            Button("Rename") {
                guard let role = renameTarget else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    Task { await viewModel.renameRole(role, newName: trimmed) }
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Enter a new name for this role.")
        }
        .onChange(of: renameTarget) { _, target in
            renameText = target?.name ?? ""
        }
        // Delete confirmation
        .confirmationDialog(
            "Delete \"\(deleteTarget?.name ?? "")\"?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Role", role: .destructive) {
                if let role = deleteTarget {
                    if selectedRoleId == role.id { selectedRoleId = nil }
                    Task { await viewModel.deleteRole(role) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This will permanently delete the role and cannot be undone.")
        }
        // Duplicate — auto-generates a name and clones
        .onChange(of: duplicateTarget) { _, target in
            guard let role = target else { return }
            Task {
                let newName = role.name + " Copy"
                await viewModel.cloneRole(role, newName: newName)
                if let cloned = viewModel.roles.last {
                    selectedRoleId = cloned.id
                }
            }
            duplicateTarget = nil
        }
        .task { await viewModel.load() }
        .onAppear { viewModel.subscribeToRolesChangedNotification() }
        // Error toast
        .overlay(alignment: .bottom) {
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.footnote)
                    .padding(DesignTokens.Spacing.md)
                    .background(.red.opacity(0.88))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, DesignTokens.Spacing.xxl)
                    .accessibilityLabel("Error: \(err)")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: DesignTokens.Motion.snappy), value: viewModel.errorMessage)
    }
}

// MARK: - RolesMatrixViewModel rename helper (additive extension)

extension RolesMatrixViewModel {
    /// Renames a role locally and persists the change by creating a fresh role
    /// with the same capabilities under the new name (server lacks a PATCH-name
    /// endpoint, so we create + delete).
    ///
    /// If a lightweight PATCH /api/v1/roles/:id becomes available later, swap
    /// the implementation here without touching any view code.
    func renameRole(_ role: Role, newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != role.name else { return }
        // Optimistic local update
        if let idx = roles.firstIndex(where: { $0.id == role.id }) {
            roles[idx] = Role(id: role.id, name: trimmed, preset: role.preset, capabilities: role.capabilities)
        }
        // Server: create under new name, then delete old
        isLoading = true
        errorMessage = nil
        do {
            let created = try await repository.create(
                name: trimmed,
                description: nil,
                capabilities: role.capabilities
            )
            try await repository.delete(roleId: role.id)
            // Replace stub entry with the real server-assigned one
            roles.removeAll { $0.id == role.id || $0.id == created.id }
            roles.append(created)
        } catch {
            // Rollback optimistic update
            if let idx = roles.firstIndex(where: { $0.id == role.id }) {
                roles[idx] = role
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
