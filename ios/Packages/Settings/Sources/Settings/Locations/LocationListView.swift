import SwiftUI
import Core
import DesignSystem

// MARK: - §60.1 LocationListView

public struct LocationListView: View {
    @State private var vm: LocationListViewModel
    @State private var showEditor: Bool = false
    @State private var editingLocation: Location? = nil
    /// BUGHUNT-2026-05-18: location delete cascades through FK-bearing
    /// rows (tickets, invoices, customers assigned to this location).
    /// Stage the target into a confirmation dialog before firing DELETE.
    @State private var pendingDelete: Location? = nil

    private let repo: any LocationRepository

    public init(repo: any LocationRepository) {
        self.repo = repo
        _vm = State(initialValue: LocationListViewModel(repo: repo))
    }

    public var body: some View {
        content
            .navigationTitle("Locations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingLocation = nil
                        showEditor = true
                    } label: {
                        Label("Add Location", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("Add location")
                }
            }
            .sheet(isPresented: $showEditor) {
                LocationEditorView(
                    location: editingLocation,
                    repo: repo
                ) { _ in
                    Task { await vm.load() }
                    showEditor = false
                }
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .confirmationDialog(
                pendingDelete.map { "Delete \"\($0.name)\"?" } ?? "Delete location?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let target = pendingDelete {
                        Task { await vm.delete(id: target.id) }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Records (tickets, invoices, customers) assigned here may be affected. Consider deactivating the location instead.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if Platform.isCompact {
            iPhoneList
        } else {
            iPadTable
        }
    }

    // MARK: iPhone — List

    @ViewBuilder
    private var iPhoneList: some View {
        switch vm.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            List {
                ForEach(vm.sortedLocations) { loc in
                    LocationRow(location: loc) {
                        editingLocation = loc
                        showEditor = true
                    } onSetPrimary: {
                        Task { await vm.setPrimary(id: loc.id) }
                    } onToggleActive: {
                        Task { await vm.setActive(id: loc.id, active: !loc.active) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = loc
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: iPad — Table with sortable columns

    @ViewBuilder @MainActor
    private var iPadTable: some View {
        switch vm.loadState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")
        default:
            Table(vm.sortedLocations, sortOrder: $vm.sortOrder) {
                TableColumn("Name", value: \.name)
                TableColumn("City", value: \.city)
                TableColumn("Phone", value: \.phone)
                TableColumn("Timezone", value: \.timezone)
                TableColumn("Primary") { loc in
                    if loc.isPrimary {
                        StatusPill("Primary", hue: .completed)
                    } else {
                        StatusPill("—", hue: .archived)
                    }
                }
                TableColumn("Active") { loc in
                    StatusPill(
                        loc.active ? "Active" : "Inactive",
                        hue: loc.active ? .ready : .archived
                    )
                }
                TableColumn("Actions") { loc in
                    LocationActionBar(
                        location: loc,
                        onEdit: {
                            editingLocation = loc
                            showEditor = true
                        },
                        onSetPrimary: {
                            Task { await vm.setPrimary(id: loc.id) }
                        },
                        onToggleActive: {
                            Task { await vm.setActive(id: loc.id, active: !loc.active) }
                        }
                    )
                }
            }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - LocationActionBar (extracted to avoid generic inference issues in Table)

private struct LocationActionBar: View {
    let location: Location
    let onEdit: () -> Void
    let onSetPrimary: () -> Void
    let onToggleActive: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Button("Edit", action: onEdit)
                .buttonStyle(.borderless)
                .brandHover()

            if !location.isPrimary {
                Button("Set Primary", action: onSetPrimary)
                    .buttonStyle(.borderless)
                    .brandHover()
            }

            Button(location.active ? "Deactivate" : "Activate", action: onToggleActive)
                .buttonStyle(.borderless)
                .brandHover()
        }
    }
}

// MARK: - LocationRow (iPhone)

private struct LocationRow: View {
    let location: Location
    let onEdit: () -> Void
    let onSetPrimary: () -> Void
    let onToggleActive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(location.name)
                    .font(.headline)
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if location.isPrimary {
                    StatusPill("Primary", hue: .completed)
                }
                StatusPill(
                    location.active ? "Active" : "Inactive",
                    hue: location.active ? .ready : .archived
                )
            }
            Text("\(location.city), \(location.region)")
                .font(.subheadline)
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
            if !location.isPrimary {
                Button("Set as Primary", action: onSetPrimary)
            }
            Button(location.active ? "Deactivate" : "Activate", action: onToggleActive)
        }
        .accessibilityLabel("\(location.name), \(location.city)")
        .accessibilityHint("Tap to edit")
    }
}
