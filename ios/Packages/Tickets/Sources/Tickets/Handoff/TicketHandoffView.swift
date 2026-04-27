#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.12 — Handoff modal: required reason + assignee picker.
// Transfer ticket to another technician. PUT /api/v1/tickets/:id.
//
// iPhone: bottom sheet (.large detent).
// iPad:   popover or medium detent sheet.

public struct TicketHandoffView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketHandoffViewModel
    let onSuccess: () -> Void

    public init(ticketId: Int64, api: APIClient, onSuccess: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: TicketHandoffViewModel(ticketId: ticketId, api: api))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle("Transfer Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.loadEmployees() }
        .onChange(of: vm.didSucceed) { _, succeeded in
            if succeeded {
                onSuccess()
                dismiss()
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            reasonSection
            assigneeSection

            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Reason

    private var reasonSection: some View {
        Section("Reason (required)") {
            Picker("Reason", selection: $vm.selectedReason) {
                ForEach(HandoffReason.allCases) { reason in
                    Text(reason.displayName).tag(reason)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Handoff reason")

            if vm.selectedReason == .other {
                TextField("Describe the reason…", text: $vm.otherReasonText, axis: .vertical)
                    .lineLimit(2...4)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Custom handoff reason")
            }
        }
    }

    // MARK: - Assignee

    private var assigneeSection: some View {
        Section("Assign to") {
            if vm.isLoadingEmployees {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading technicians…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else if vm.employees.isEmpty {
                Text("No technicians available.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(vm.employees) { employee in
                    Button {
                        vm.selectedEmployee = employee
                    } label: {
                        HStack(spacing: BrandSpacing.md) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(
                                    vm.selectedEmployee?.id == employee.id ? .bizarreOrange : .bizarreOnSurfaceMuted
                                )

                            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                Text(employee.displayName)
                                    .font(.brandBodyLarge())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let role = employee.role, !role.isEmpty {
                                    Text(role)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }

                            Spacer()

                            if vm.selectedEmployee?.id == employee.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.bizarreOrange)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Assign to \(employee.displayName)")
                    .accessibilityAddTraits(vm.selectedEmployee?.id == employee.id ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel handoff")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button {
                Task { await vm.submit() }
            } label: {
                if vm.isSubmitting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Transfer")
                        .fontWeight(.semibold)
                }
            }
            .disabled(!vm.canSubmit || vm.isSubmitting)
            .accessibilityLabel(vm.isSubmitting ? "Transferring…" : "Transfer ticket")
        }
    }
}

#Preview("Handoff Sheet") {
    Color.bizarreSurfaceBase
        .sheet(isPresented: .constant(true)) {
            TicketHandoffView(ticketId: 1, api: APIClient())
        }
}
#endif
