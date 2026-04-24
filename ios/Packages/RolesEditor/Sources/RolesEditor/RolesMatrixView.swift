import SwiftUI
import Core
import DesignSystem

// MARK: - RolesMatrixView (iPad — capabilities-as-rows, roles-as-columns table)
//
// iPad layout per CLAUDE.md and §47 spec:
//   - NavigationSplitView: sidebar = role list, detail = full cross-tab matrix
//   - The matrix detail renders ALL roles as columns and ALL capabilities as rows
//     so admins can compare permissions across roles at a glance.
//   - iPhone uses RoleListView + RoleDetailView (vertical flow).
//
// Liquid Glass is applied to the toolbar chrome only (not to data table cells).

public struct RolesMatrixView: View {

    // MARK: State

    @State private var viewModel: RolesMatrixViewModel
    @State private var selectedRoleId: String?
    @State private var showCreateSheet = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteRole: Role?
    @State private var columnWidth: CGFloat = 120

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
            matrixTable
        }
        .task { await viewModel.load() }
        .onAppear {
            viewModel.onPreviewRoleChanged = onPreviewRoleChanged
            viewModel.subscribeToRolesChangedNotification()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateRoleSheet { name, description, preset in
                Task {
                    let caps = preset.map { RolePresets.preset(for: $0)?.capabilities ?? [] } ?? []
                    await viewModel.createRole(name: name, description: description, capabilities: caps)
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
                if selectedRoleId == role.id { selectedRoleId = nil }
                Task { await viewModel.deleteRole(role) }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .safeAreaInset(edge: .top) { previewBanner }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var rolesSidebar: some View {
        List(viewModel.roles, selection: $selectedRoleId) { role in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(role.name)
                        .font(.body)
                    Text("\(role.capabilities.count) capabilities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: role.preset != nil
                    ? "person.crop.circle.badge.checkmark"
                    : "person.crop.circle")
                .foregroundStyle(role.preset != nil ? .blue : .secondary)
            }
            .tag(role.id)
            .hoverEffect(.highlight)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    pendingDeleteRole = role
                    showDeleteConfirm = true
                }
            }
            .accessibilityLabel("\(role.name), \(role.capabilities.count) capabilities")
        }
        .navigationTitle("Roles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Add Role", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("Add new role")
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.roles.isEmpty {
                ProgressView()
            }
        }
    }

    // MARK: Matrix table (roles-as-columns, capabilities-as-rows)

    @ViewBuilder
    private var matrixTable: some View {
        if viewModel.roles.isEmpty {
            ContentUnavailableView(
                "No Roles",
                systemImage: "person.badge.key",
                description: Text("Create a role using the + button in the sidebar.")
            )
        } else {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Sticky column header row
                    matrixColumnHeader
                    // Domain sections
                    ForEach(viewModel.domains, id: \.domain) { group in
                        Section {
                            ForEach(group.capabilities) { cap in
                                matrixRow(cap: cap)
                                Divider()
                                    .padding(.leading, 260)
                            }
                        } header: {
                            domainSectionHeader(group.domain)
                        }
                    }
                }
            }
            .navigationTitle("Roles Matrix")
            .toolbar { matrixToolbarContent }
            .if(viewModel.errorMessage != nil) { view in
                view.overlay(alignment: .bottom) {
                    Text(viewModel.errorMessage ?? "")
                        .font(.footnote)
                        .padding()
                        .background(.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding()
                        .accessibilityLabel("Error: \(viewModel.errorMessage ?? "")")
                }
            }
        }
    }

    // MARK: Column header row

    @ViewBuilder
    private var matrixColumnHeader: some View {
        HStack(spacing: 0) {
            // Capability label column header
            Text("Capability")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 260, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Role column headers
            ForEach(viewModel.roles) { role in
                VStack(spacing: 2) {
                    Text(role.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text("\(role.capabilities.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: columnWidth)
                .padding(.vertical, 8)
                .accessibilityLabel("\(role.name), \(role.capabilities.count) capabilities enabled")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .brandGlass(.regular, in: Rectangle())
    }

    // MARK: Domain section header

    @ViewBuilder
    private func domainSectionHeader(_ domain: String) -> some View {
        Text(domain)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
    }

    // MARK: Matrix row (one capability, all roles)

    @ViewBuilder
    private func matrixRow(cap: Capability) -> some View {
        HStack(spacing: 0) {
            // Capability label
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.label)
                    .font(.subheadline)
                Text(cap.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Toggle per role
            ForEach(viewModel.roles) { role in
                let isOn = role.capabilities.contains(cap.id)
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { _ in Task { await viewModel.toggle(capability: cap.id, on: role) } }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .frame(width: columnWidth)
                .accessibilityLabel("\(cap.label) for \(role.name): \(isOn ? "on" : "off")")
                .accessibilityHint("Double-tap to toggle")
                .accessibilityValue(isOn ? "enabled" : "disabled")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }

    // MARK: Matrix toolbar

    @ToolbarContentBuilder
    private var matrixToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            if let previewRole = viewModel.activePreviewRole {
                Button("Exit Preview: \(previewRole.name)") {
                    viewModel.exitPreview()
                }
                .tint(.orange)
            }
        }
        if let selectedId = selectedRoleId,
           let role = viewModel.roles.first(where: { $0.id == selectedId }) {
            ToolbarItem(placement: .secondaryAction) {
                Menu("Selected: \(role.name)") {
                    if viewModel.activePreviewRoleId == role.id {
                        Button("Exit Preview") { viewModel.exitPreview() }
                    } else {
                        Button("Preview as this Role") { viewModel.startPreview(roleId: role.id) }
                    }
                    Divider()
                    Button("Delete Role", role: .destructive) {
                        pendingDeleteRole = role
                        showDeleteConfirm = true
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
