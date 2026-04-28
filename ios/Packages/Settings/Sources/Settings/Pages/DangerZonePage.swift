import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class DangerZoneViewModel: Sendable {

    var isSigning: Bool = false
    var isResetting: Bool = false
    var isDeleting: Bool = false

    var showSignOutEverywhereConfirm: Bool = false
    var showResetDemoConfirm: Bool = false
    var showDeleteTenantConfirm: Bool = false
    var showDeletePINEntry: Bool = false
    var managerPIN: String = ""

    var errorMessage: String?
    var successMessage: String?

    var isTrainingMode: Bool = false

    private let api: APIClient?

    public init(api: APIClient? = nil, isTrainingMode: Bool = false) {
        self.api = api
        self.isTrainingMode = isTrainingMode
    }

    func signOutEverywhere() async {
        isSigning = true
        defer { isSigning = false }
        guard let api else { return }
        do {
            try await api.revokeAllSessions()
            successMessage = "All other sessions signed out."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetDemoData() async {
        isResetting = true
        defer { isResetting = false }
        guard let api else { return }
        do {
            try await api.resetDemoData()
            successMessage = "Demo data reset."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTenant() async {
        guard !managerPIN.isEmpty else {
            errorMessage = "Enter manager PIN to confirm."
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        guard let api else { return }
        do {
            try await api.deleteTenant(managerPin: managerPIN)
            successMessage = "Tenant deletion initiated."
            errorMessage = nil
            managerPIN = ""
        } catch {
            errorMessage = error.localizedDescription
            managerPIN = ""
        }
    }
}

// MARK: - View

public struct DangerZonePage: View {
    @State private var vm: DangerZoneViewModel

    public init(api: APIClient? = nil, isTrainingMode: Bool = false) {
        _vm = State(initialValue: DangerZoneViewModel(api: api, isTrainingMode: isTrainingMode))
    }

    public var body: some View {
        Form {
            Section {
                NavigationLink("Export all data") {
                    // Routes to DataExport entry (Phase 8 / §19.19)
                    // Actual DataExportView is shipped by the Phase 8 agent.
                    Text("Data export will be available here.")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .navigationTitle("Export Data")
                }
                .accessibilityIdentifier("danger.exportData")
            } header: {
                Text("Data")
            } footer: {
                Text("Download a full backup of your tenant data.")
            }

            if vm.isTrainingMode {
                Section {
                    Button {
                        vm.showResetDemoConfirm = true
                    } label: {
                        Label("Reset demo data", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.bizarreWarning)
                    }
                    .accessibilityIdentifier("danger.resetDemo")
                } header: {
                    Text("Training mode")
                } footer: {
                    Text("Restores demo data to its original state. Irreversible.")
                }
                .confirmationDialog(
                    "Reset demo data?",
                    isPresented: $vm.showResetDemoConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset demo", role: .destructive) {
                        Task { await vm.resetDemoData() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will wipe all demo data and restore the defaults. This cannot be undone.")
                }
            }

            Section {
                Button {
                    vm.showSignOutEverywhereConfirm = true
                } label: {
                    Label("Sign out everywhere", systemImage: "rectangle.portrait.and.arrow.right.fill")
                        .foregroundStyle(.bizarreError)
                }
                .disabled(vm.isSigning)
                .accessibilityIdentifier("danger.signOutEverywhere")
            } header: {
                Text("Sessions")
            } footer: {
                Text("Revokes all active sessions on every device. You will remain signed in here.")
            }
            .confirmationDialog(
                "Sign out everywhere?",
                isPresented: $vm.showSignOutEverywhereConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign out all devices", role: .destructive) {
                    Task { await vm.signOutEverywhere() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This revokes all active sessions. All other signed-in devices will be signed out immediately.")
            }

            Section {
                Button {
                    vm.showDeleteTenantConfirm = true
                } label: {
                    Label("Delete tenant", systemImage: "trash.fill")
                        .foregroundStyle(.bizarreError)
                }
                .disabled(vm.isDeleting)
                .accessibilityIdentifier("danger.deleteTenant")
            } header: {
                Text("Delete account")
            } footer: {
                Text("Permanently deletes your tenant and all data. Requires manager PIN. Irreversible.")
            }
            .confirmationDialog(
                "Delete tenant permanently?",
                isPresented: $vm.showDeleteTenantConfirm,
                titleVisibility: .visible
            ) {
                Button("Enter PIN to confirm", role: .destructive) {
                    vm.showDeletePINEntry = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All tenant data will be permanently deleted. This cannot be undone.")
            }

            if let msg = vm.errorMessage {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(msg)")
                }
            }

            if let msg = vm.successMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel(msg)
                }
            }
        }
        .navigationTitle("Danger Zone")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $vm.showDeletePINEntry) {
            DeleteTenantPINSheet(vm: vm)
        }
    }
}

// MARK: - PIN confirmation sheet

struct DeleteTenantPINSheet: View {
    @Bindable var vm: DangerZoneViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Manager PIN", text: $vm.managerPIN)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityLabel("Manager PIN")
                        .accessibilityIdentifier("danger.managerPIN")
                } header: {
                    Text("Confirm deletion")
                } footer: {
                    Text("Enter the manager PIN to permanently delete this tenant and all its data.")
                        .foregroundStyle(.bizarreError)
                }
            }
            .navigationTitle("Enter Manager PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.managerPIN = ""
                        vm.showDeletePINEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await vm.deleteTenant()
                            if vm.errorMessage == nil {
                                vm.showDeletePINEntry = false
                            }
                        }
                    }
                    .disabled(vm.managerPIN.count < 4 || vm.isDeleting)
                    .accessibilityIdentifier("danger.confirmDelete")
                }
            }
        }
    }
}
