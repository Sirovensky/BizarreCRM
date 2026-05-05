import SwiftUI
import Networking
import Factory
import DesignSystem

// MARK: - RoleUsersAPIClient
//
// Minimal protocol over the two APIClient operations this inspector needs.
// Keeps the view-model testable without requiring a full APIClient stub.

public protocol RoleUsersAPIClient: Sendable {
    func listAllUsers() async throws -> [Employee]
    func assignEmployeeRole(userId: Int64, roleId: Int) async throws
}

// MARK: - RoleUsersInspector
//
// Trailing column of the iPad three-column layout (§22).
// Lists all users that have this role assigned. Supports:
//   • Assign a user to the role (pick from unassigned users)
//   • Unassign a user from the role
//
// Server routes used:
//   GET  /api/v1/settings/users       → all users (listAllUsers)
//   PUT  /api/v1/roles/users/:id/role → assign role to user (assignEmployeeRole)
//
// Users with the role are identified by `employee.role == role.name` or
// `employee.role == String(roleId)`. The server stores the custom role name
// in the `role` string field; we match on role.name until a proper
// role_id column is available.

@MainActor
public struct RoleUsersInspector: View {

    // MARK: State

    @State private var viewModel: RoleUsersInspectorViewModel

    // MARK: Init

    public init(role: Role, repository: any RolesRepository) {
        let api = Container.shared.apiClient()
        _viewModel = State(initialValue: RoleUsersInspectorViewModel(
            role: role,
            api: RoleUsersAPIClientAdapter(api: api)
        ))
    }

    /// Testable init accepting any RoleUsersAPIClient.
    public init(role: Role, api: any RoleUsersAPIClient) {
        _viewModel = State(initialValue: RoleUsersInspectorViewModel(role: role, api: api))
    }

    // MARK: Body

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.members.isEmpty {
                loadingView
            } else {
                inspectorContent
            }
        }
        .navigationTitle("Members")
        .inlineNavigationTitle()
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showAssignSheet) {
            AssignUserSheet(
                candidates: viewModel.unassignedUsers,
                onAssign: { user in
                    Task { await viewModel.assign(user: user) }
                }
            )
        }
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
        .task { await viewModel.load() }
    }

    // MARK: Loading

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            ProgressView()
            Text("Loading members…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Inspector content

    @ViewBuilder
    private var inspectorContent: some View {
        List {
            // Members section
            Section {
                if viewModel.members.isEmpty {
                    emptyMembersRow
                } else {
                    ForEach(viewModel.members) { user in
                        memberRow(user)
                            .hoverEffect(.highlight)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) {
                                    Task { await viewModel.unassign(user: user) }
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Current Members")
                    Spacer()
                    BrandGlassBadge(
                        "\(viewModel.members.count)",
                        variant: .regular
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Member row

    @ViewBuilder
    private func memberRow(_ user: Employee) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Avatar initials circle
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(
                        width: DesignTokens.Touch.minTargetSide * 0.8,
                        height: DesignTokens.Touch.minTargetSide * 0.8
                    )
                Text(user.initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(user.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .textSelection(.enabled)
                if let email = user.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            if !user.active {
                BrandGlassBadge("Inactive", variant: .regular, tint: .orange)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(user.displayName)\(user.active ? "" : ", inactive")"
        )
    }

    // MARK: Empty state

    @ViewBuilder
    private var emptyMembersRow: some View {
        HStack {
            Spacer()
            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "person.2.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No members assigned")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, DesignTokens.Spacing.xxl)
            Spacer()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.showAssignSheet = true
            } label: {
                Label("Assign User", systemImage: "person.badge.plus")
            }
            .brandGlass(.regular, interactive: true)
            .disabled(viewModel.unassignedUsers.isEmpty)
            .accessibilityLabel("Assign user to this role")
        }
    }
}

// MARK: - RoleUsersAPIClientAdapter
//
// Bridges the full `any APIClient` (from the DI container) to the
// narrow `RoleUsersAPIClient` protocol this inspector requires.

struct RoleUsersAPIClientAdapter: RoleUsersAPIClient {
    private let api: any APIClient

    init(api: any APIClient) { self.api = api }

    func listAllUsers() async throws -> [Employee] {
        try await api.listAllUsers()
    }

    func assignEmployeeRole(userId: Int64, roleId: Int) async throws {
        try await api.assignEmployeeRole(userId: userId, roleId: roleId)
    }
}

// MARK: - RoleUsersInspectorViewModel

@Observable
@MainActor
final class RoleUsersInspectorViewModel {

    // MARK: State

    var allUsers: [Employee] = []
    var isLoading = false
    var errorMessage: String?
    var showAssignSheet = false

    // MARK: Optimistic membership overlay
    //
    // Since `Employee` is a Decodable-only struct from Networking (no public
    // init), we track membership changes as a delta set rather than
    // constructing new Employee values in-place.
    // assignedOverrides  — user IDs force-added to this role
    // unassignedOverrides — user IDs force-removed from this role

    private var assignedOverrides: Set<Int64> = []
    private var unassignedOverrides: Set<Int64> = []

    // MARK: Derived

    /// Users currently assigned to this role.
    var members: [Employee] {
        allUsers.filter { isAssigned($0) }
    }

    /// Active users not yet in this role (candidates for assignment).
    var unassignedUsers: [Employee] {
        allUsers.filter { $0.active && !isAssigned($0) }
    }

    // MARK: Dependencies

    private let role: Role
    private let api: any RoleUsersAPIClient

    // MARK: Init

    init(role: Role, api: any RoleUsersAPIClient) {
        self.role = role
        self.api = api
    }

    // MARK: Load

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            allUsers = try await api.listAllUsers()
            // Clear overrides — fresh data from server is authoritative.
            assignedOverrides.removeAll()
            unassignedOverrides.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: Assign

    func assign(user: Employee) async {
        guard let roleIdInt = Int(role.id) else {
            errorMessage = "Invalid role id: \(role.id)"
            return
        }
        errorMessage = nil
        do {
            try await api.assignEmployeeRole(userId: user.id, roleId: roleIdInt)
            // Optimistic overlay: mark this user as assigned.
            unassignedOverrides.remove(user.id)
            assignedOverrides.insert(user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        showAssignSheet = false
    }

    // MARK: Unassign
    //
    // The server does not have a dedicated "remove role" endpoint; assigning
    // role_id = 0 is the convention (employee becomes role-less).

    func unassign(user: Employee) async {
        errorMessage = nil
        do {
            try await api.assignEmployeeRole(userId: user.id, roleId: 0)
            // Optimistic overlay: mark this user as no longer assigned.
            assignedOverrides.remove(user.id)
            unassignedOverrides.insert(user.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private helpers

    private func isAssigned(_ user: Employee) -> Bool {
        // Override layer takes precedence over server-provided role field.
        if unassignedOverrides.contains(user.id) { return false }
        if assignedOverrides.contains(user.id) { return true }

        // Server stores the custom_role name in employee.role; match by name.
        // Fallback: also match if role string equals the role id directly.
        guard let userRole = user.role, !userRole.isEmpty else { return false }
        return userRole.lowercased() == role.name.lowercased()
            || userRole == role.id
    }
}

// MARK: - AssignUserSheet

@MainActor
private struct AssignUserSheet: View {

    let candidates: [Employee]
    let onAssign: (Employee) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [Employee] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.email ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "All Users Assigned",
                        systemImage: "person.2.badge.gearshape",
                        description: Text("Every active user already has this role.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filtered) { user in
                        Button {
                            onAssign(user)
                            dismiss()
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.md) {
                                ZStack {
                                    Circle()
                                        .fill(.teal.opacity(0.15))
                                        .frame(
                                            width: DesignTokens.Touch.minTargetSide * 0.8,
                                            height: DesignTokens.Touch.minTargetSide * 0.8
                                        )
                                    Text(user.initials)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.teal)
                                }
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(user.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if let email = user.email, !email.isEmpty {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, DesignTokens.Spacing.xs)
                        }
                        .hoverEffect(.highlight)
                        .accessibilityLabel("Assign \(user.displayName) to this role")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search users")
            .navigationTitle("Assign User")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
