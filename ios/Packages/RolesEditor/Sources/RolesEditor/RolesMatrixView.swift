import SwiftUI
import Core
import DesignSystem

// MARK: - RolesMatrixView (iPad — full grid)

/// iPad layout: NavigationSplitView with roles sidebar + full capability matrix detail.
/// Each cell is a Toggle sized to 44pt min for a11y (§47.1).
public struct RolesMatrixView: View {

    // MARK: State

    @State private var viewModel: RolesMatrixViewModel
    @State private var selectedRoleId: String?
    @State private var showCloneSheet = false
    @State private var cloneSourceRole: Role?
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteRole: Role?

    // Callback for host app preview integration (§47.3)
    public var onPreviewRoleChanged: ((String?) -> Void)?

    // MARK: Init

    public init(viewModel: RolesMatrixViewModel, onPreviewRoleChanged: ((String?) -> Void)? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.onPreviewRoleChanged = onPreviewRoleChanged
    }

    // MARK: Body

    public var body: some View {
        NavigationSplitView {
            rolesSidebar
        } detail: {
            if let selectedId = selectedRoleId,
               let role = viewModel.roles.first(where: { $0.id == selectedId }) {
                matrixDetail(for: role)
            } else {
                ContentUnavailableView(
                    "Select a Role",
                    systemImage: "person.badge.key",
                    description: Text("Choose a role from the sidebar to edit its capabilities.")
                )
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            viewModel.onPreviewRoleChanged = onPreviewRoleChanged
            viewModel.subscribeToRolesChangedNotification()
        }
        .sheet(isPresented: $showCloneSheet) {
            if let source = cloneSourceRole {
                CloneRoleSheet(sourceRole: source) { newName in
                    Task { await viewModel.cloneRole(source, newName: newName) }
                }
            }
        }
        .confirmationDialog(
            "Delete role \"\(pendingDeleteRole?.name ?? "")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let role = pendingDeleteRole else { return }
                Task { await viewModel.deleteRole(role) }
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var rolesSidebar: some View {
        List(viewModel.roles, selection: $selectedRoleId) { role in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.body)
                    if let preset = role.preset {
                        Text(preset.replacingOccurrences(of: "preset.", with: "").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: role.preset != nil ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
            }
            .tag(role.id)
            .contextMenu {
                Button("Clone") {
                    cloneSourceRole = role
                    showCloneSheet = true
                }
                Button("Delete", role: .destructive) {
                    pendingDeleteRole = role
                    showDeleteConfirm = true
                }
            }
        }
        .navigationTitle("Roles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(RolePresets.all, id: \.id) { preset in
                        Button(preset.name) {
                            Task { await viewModel.createRole(name: preset.name, preset: preset.id, capabilities: preset.capabilities) }
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
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    // MARK: Matrix detail

    @ViewBuilder
    private func matrixDetail(for role: Role) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.domains, id: \.domain) { group in
                    Section {
                        ForEach(group.capabilities) { cap in
                            matrixCell(cap: cap, role: role)
                            Divider().padding(.leading)
                        }
                    } header: {
                        Text(group.domain)
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                    }
                }
            }
        }
        .navigationTitle(role.name)
        .toolbar {
            previewToolbarItems(for: role)
        }
        .safeAreaInset(edge: .top) {
            previewBanner
        }
        .if(viewModel.errorMessage != nil) { view in
            view.overlay(alignment: .bottom) {
                Text(viewModel.errorMessage ?? "")
                    .font(.footnote)
                    .padding()
                    .background(.red.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding()
            }
        }
    }

    // MARK: Matrix cell

    @ViewBuilder
    private func matrixCell(cap: Capability, role: Role) -> some View {
        let isOn = role.capabilities.contains(cap.id)
        let capLabel = cap.label
        let capDesc = cap.description
        let roleName = role.name
        let capId = cap.id
        HStack {
            capabilityLabelStack(label: capLabel, description: capDesc)
            Spacer()
            Toggle(isOn: Binding(
                get: { isOn },
                set: { _ in Task { await viewModel.toggle(capability: capId, on: role) } }
            )) {
                EmptyView()
            }
            .accessibilityLabel("\(capLabel) for \(roleName)")
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0))
    }

    @ViewBuilder
    private func capabilityLabelStack(label: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.subheadline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 240, alignment: .leading)
    }

    // MARK: Preview toolbar (§47.3)

    @ToolbarContentBuilder
    private func previewToolbarItems(for role: Role) -> some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            if viewModel.activePreviewRoleId == role.id {
                Button("Exit Preview") { viewModel.exitPreview() }
                    .tint(.orange)
            } else {
                Button("Preview as Role") { viewModel.startPreview(roleId: role.id) }
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu("Clone / Template") {
                Button("Clone this role") {
                    cloneSourceRole = role
                    showCloneSheet = true
                }
                Divider()
                ForEach(RolePresets.all, id: \.id) { preset in
                    Button("Apply \"\(preset.name)\" template") {
                        Task { await viewModel.setCapabilities(preset.capabilities, on: role) }
                    }
                }
            }
        }
    }

    // MARK: Preview banner

    @ViewBuilder
    private var previewBanner: some View {
        if let previewRole = viewModel.activePreviewRole {
            HStack {
                Image(systemName: "eye.fill")
                Text("Previewing as \(previewRole.name). ")
                    .bold()
                + Text("Exit")
                    .underline()
            }
            .font(.footnote)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.9))
            .foregroundStyle(.white)
            .brandGlass(.regular, in: Rectangle())
            .onTapGesture { viewModel.exitPreview() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Previewing as \(previewRole.name). Tap to exit.")
            .animation(.easeInOut, value: viewModel.activePreviewRoleId)
        }
    }
}

// MARK: - View extension helper

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

// MARK: - CloneRoleSheet

private struct CloneRoleSheet: View {
    let sourceRole: Role
    let onClone: (String) -> Void

    @State private var newName: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("New Role Name") {
                    TextField("Name", text: $newName)
                        .accessibilityLabel("New role name")
                }
                Section {
                    Text("Cloning capabilities from: **\(sourceRole.name)**")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Clone Role")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clone") {
                        onClone(newName.isEmpty ? "\(sourceRole.name) Copy" : newName)
                        dismiss()
                    }
                }
            }
        }
    }
}
