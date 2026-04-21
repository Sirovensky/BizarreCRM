#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §63 ext — InvoiceCreateView with draft recovery (Phase 2)

public struct InvoiceCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InvoiceCreateViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: InvoiceCreateViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §63 ext — draft recovery banner
                if let record = vm._draftRecord {
                    DraftRecoveryBanner(record: record) {
                        vm.restoreDraft()
                    } onDiscard: {
                        vm.discardDraft()
                    }
                }

                Form {
                    Section("Customer") {
                        if vm.customerDisplayName.isEmpty {
                            Text("No customer selected")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        } else {
                            Text(vm.customerDisplayName)
                                .foregroundStyle(.bizarreOnSurface)
                        }
                        // Customer picker integration: caller sets customerId / customerDisplayName.
                    }

                    Section("Details") {
                        TextField("Notes", text: $vm.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .onChange(of: vm.notes) { _, _ in vm.scheduleAutoSave() }

                        TextField("Due date (YYYY-MM-DD)", text: $vm.dueOn)
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: vm.dueOn) { _, _ in vm.scheduleAutoSave() }
                    }

                    if let err = vm.errorMessage {
                        Section { Text(err).foregroundStyle(.bizarreError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.queuedOffline || vm.createdId != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .task { await vm.onAppear() }
        }
    }
}
#endif
