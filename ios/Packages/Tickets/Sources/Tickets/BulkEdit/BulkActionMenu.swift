#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - BulkActionMenuViewModel

/// Drives `BulkActionMenu`. Fetches statuses and employees for picker
/// sub-sheets, then delegates to the coordinator.
@MainActor
@Observable
final class BulkActionMenuViewModel {

    // MARK: - State

    var statuses: [TicketStatusRow] = []
    var employees: [Employee] = []
    var isLoadingStatuses: Bool = false
    var isLoadingEmployees: Bool = false
    var errorMessage: String?

    // MARK: - Picked values

    var pickedStatusId: Int64?
    var pickedEmployeeId: Int64?

    // MARK: - Private

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    func loadStatuses() async {
        isLoadingStatuses = true
        defer { isLoadingStatuses = false }
        do {
            statuses = try await api.listTicketStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadEmployees() async {
        isLoadingEmployees = true
        defer { isLoadingEmployees = false }
        do {
            employees = try await api.listEmployees()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - BulkActionMenu

/// Sheet presenting bulk actions: Change Status / Reassign / Archive.
///
/// Presented over the ticket list when `selection.hasSelection == true`.
/// Calls `onCommit` with the chosen `BulkAction` — the caller is
/// responsible for invoking the coordinator and dismissing the sheet.
struct BulkActionMenu: View {
    @Environment(\.dismiss) private var dismiss

    let selection: BulkEditSelection
    let api: APIClient
    let onCommit: (BulkAction) -> Void

    @State private var vm: BulkActionMenuViewModel
    @State private var showStatusPicker: Bool = false
    @State private var showReassignPicker: Bool = false
    @State private var showArchiveConfirm: Bool = false

    init(selection: BulkEditSelection, api: APIClient, onCommit: @escaping (BulkAction) -> Void) {
        self.selection = selection
        self.api = api
        self.onCommit = onCommit
        _vm = State(wrappedValue: BulkActionMenuViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle(selectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeButton }
            .sheet(isPresented: $showStatusPicker) { statusPickerSheet }
            .sheet(isPresented: $showReassignPicker) { reassignPickerSheet }
            .confirmationDialog(
                "Archive \(selection.count) ticket\(selection.count == 1 ? "" : "s")?",
                isPresented: $showArchiveConfirm,
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    dismiss()
                    onCommit(.archive)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the selected tickets. Inventory stock will be restored.")
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    private var content: some View {
        List {
            Section {
                actionRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: "Change Status",
                    color: .blue
                ) {
                    Task { await vm.loadStatuses() }
                    showStatusPicker = true
                }

                actionRow(
                    icon: "person.badge.key",
                    label: "Reassign",
                    color: .orange
                ) {
                    Task { await vm.loadEmployees() }
                    showReassignPicker = true
                }

                actionRow(
                    icon: "archivebox",
                    label: "Archive",
                    color: .red
                ) {
                    showArchiveConfirm = true
                }
            } header: {
                Text("ACTIONS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func actionRow(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Status picker sheet

    private var statusPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if vm.isLoadingStatuses {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(vm.statuses) { status in
                            Button {
                                showStatusPicker = false
                                dismiss()
                                onCommit(.changeStatus(statusId: status.id))
                            } label: {
                                HStack {
                                    Text(status.name)
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if vm.pickedStatusId == status.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .listRowBackground(Color.bizarreSurface1)
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Select Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStatusPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Reassign picker sheet

    private var reassignPickerSheet: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if vm.isLoadingEmployees {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            Section {
                                Button {
                                    showReassignPicker = false
                                    dismiss()
                                    onCommit(.reassign(userId: nil))
                                } label: {
                                    Label("Unassign", systemImage: "person.slash")
                                        .foregroundStyle(Color.primary)
                                }
                                .listRowBackground(Color.bizarreSurface1)
                            }

                            Section("Employees") {
                                ForEach(vm.employees) { employee in
                                    Button {
                                        showReassignPicker = false
                                        dismiss()
                                        onCommit(.reassign(userId: employee.id))
                                    } label: {
                                        HStack {
                                            Text(employee.displayName)
                                                .foregroundStyle(Color.primary)
                                            Spacer()
                                            if vm.pickedEmployeeId == employee.id {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                    }
                                    .listRowBackground(Color.bizarreSurface1)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Reassign To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showReassignPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Toolbar

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    // MARK: - Helpers

    private var selectionTitle: String {
        let n = selection.count
        return "\(n) Ticket\(n == 1 ? "" : "s") Selected"
    }
}

#endif
