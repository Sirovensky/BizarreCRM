#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §63 ext — EstimateCreateView with draft recovery (Phase 2)

public struct EstimateCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateCreateViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: EstimateCreateViewModel(api: api))
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
                    }

                    Section("Estimate details") {
                        TextField("Subject", text: $vm.subject)
                            .onChange(of: vm.subject) { _, _ in vm.scheduleAutoSave() }

                        TextField("Notes", text: $vm.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .onChange(of: vm.notes) { _, _ in vm.scheduleAutoSave() }

                        TextField("Valid until (YYYY-MM-DD)", text: $vm.validUntil)
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: vm.validUntil) { _, _ in vm.scheduleAutoSave() }
                    }

                    if let err = vm.errorMessage {
                        Section { Text(err).foregroundStyle(.bizarreError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New estimate")
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
