import SwiftUI
import Core
import DesignSystem

// MARK: - RoleListView (iPhone — NavigationStack list of roles)

/// iPhone layout: roles list → tap → RoleDetailView.
/// iPad layout is handled by RolesMatrixView (columns-as-roles table).
/// Gate on Platform.isCompact at the host's root.
public struct RoleListView: View {

    @State private var viewModel: RolesMatrixViewModel
    @State private var showCreateSheet = false

    public var onPreviewRoleChanged: ((String?) -> Void)?

    public init(viewModel: RolesMatrixViewModel, onPreviewRoleChanged: ((String?) -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onPreviewRoleChanged = onPreviewRoleChanged
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.roles.isEmpty {
                    ProgressView("Loading roles…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.roles.isEmpty {
                    ContentUnavailableView(
                        "No Roles",
                        systemImage: "person.badge.key",
                        description: Text("Add your first role using the + button.")
                    )
                } else {
                    rolesList
                }
            }
            .navigationTitle("Roles")
            .toolbar { toolbarContent }
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
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            viewModel.onPreviewRoleChanged = onPreviewRoleChanged
            viewModel.subscribeToRolesChangedNotification()
        }
        .safeAreaInset(edge: .top) { previewBanner }
    }

    // MARK: Roles list

    @ViewBuilder
    private var rolesList: some View {
        List {
            ForEach(viewModel.roles) { role in
                NavigationLink {
                    RoleDetailView(
                        viewModel: RoleDetailViewModel(
                            role: role,
                            repository: viewModel.repository
                        )
                    )
                    .task { await viewModel.loadRole(id: role.id) }
                } label: {
                    roleRow(role)
                }
                .hoverEffect(.highlight)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteRole(role) }
                    }
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteRole(role) }
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showCreateSheet = true
            } label: {
                Label("Add Role", systemImage: "plus")
            }
            .brandGlass(.regular, interactive: true)
            .accessibilityLabel("Add new role")
        }
    }

    // MARK: Role row

    @ViewBuilder
    private func roleRow(_ role: Role) -> some View {
        HStack {
            Image(systemName: role.preset != nil ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .foregroundStyle(role.preset != nil ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(role.name)
                    .font(.body)
                Text("\(role.capabilities.count) capabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.name), \(role.capabilities.count) capabilities")
    }

    // MARK: Preview banner

    @ViewBuilder
    private var previewBanner: some View {
        if let previewRole = viewModel.activePreviewRole {
            HStack {
                Image(systemName: "eye.fill")
                Text("Previewing as \(previewRole.name). Exit")
                    .bold()
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.9))
            .foregroundStyle(.white)
            .brandGlass(.regular, in: Rectangle())
            .onTapGesture { viewModel.exitPreview() }
            .accessibilityLabel("Previewing as \(previewRole.name). Tap to exit.")
            .accessibilityAddTraits(.isButton)
        }
    }
}
