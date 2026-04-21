import SwiftUI
import Core
import DesignSystem

// MARK: - RoleListView (iPhone — NavigationStack list of roles)

/// iPhone layout: roles list → tap → RoleDetailView.
public struct RoleListView: View {

    @State private var viewModel: RolesMatrixViewModel

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
                    List {
                        ForEach(viewModel.roles) { role in
                            NavigationLink {
                                RoleDetailView(
                                    viewModel: RoleDetailViewModel(role: role, repository: MockRepository())
                                )
                            } label: {
                                roleRow(role)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task { await viewModel.deleteRole(role) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Roles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(RolePresets.all, id: \.id) { preset in
                            Button(preset.name) {
                                Task {
                                    await viewModel.createRole(
                                        name: preset.name,
                                        preset: preset.id,
                                        capabilities: preset.capabilities
                                    )
                                }
                            }
                        }
                        Divider()
                        Button("Custom Role") {
                            Task { await viewModel.createRole(name: "New Role") }
                        }
                    } label: {
                        Label("Add Role", systemImage: "plus")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            viewModel.onPreviewRoleChanged = onPreviewRoleChanged
            viewModel.subscribeToRolesChangedNotification()
        }
        .safeAreaInset(edge: .top) {
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
                .onTapGesture { viewModel.exitPreview() }
                .accessibilityLabel("Previewing as \(previewRole.name). Tap to exit.")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

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
}

// MARK: - Temporary mock for NavigationLink (host wires real repo)

/// Placeholder repository used when building standalone previews.
/// The host app replaces this via Factory DI injection.
private struct MockRepository: RolesRepository {
    func fetchAll() async throws -> [Role] { [] }
    func create(name: String, preset: String?, capabilities: Set<String>) async throws -> Role {
        Role(id: UUID().uuidString, name: name, preset: preset, capabilities: capabilities)
    }
    func update(role: Role, newCapabilities: Set<String>) async throws -> Role {
        Role(id: role.id, name: role.name, preset: role.preset, capabilities: newCapabilities)
    }
    func delete(roleId: String) async throws {}
    func refresh() async throws -> [Role] { [] }
}
