#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct TicketEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketEditViewModel
    @State private var pendingBanner: String?
    private let onSaved: () -> Void

    public init(api: APIClient, ticket: TicketDetail, onSaved: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: TicketEditViewModel(api: api, ticket: ticket))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Adjustments") {
                    LabeledField("Discount (USD)", text: $vm.discountText, keyboard: .decimalPad)
                    LabeledField("Discount reason", text: $vm.discountReason)
                }

                Section("Attribution") {
                    LabeledField("Source", text: $vm.source)
                    LabeledField("Referral source", text: $vm.referralSource)
                }

                Section("Scheduling") {
                    LabeledField("Due on (YYYY-MM-DD)", text: $vm.dueOn, keyboard: .numbersAndPunctuation, autocapitalize: .never)
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Edit ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            guard vm.didSave else { return }
                            onSaved()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                try? await Task.sleep(nanoseconds: 900_000_000)
                            }
                            dismiss()
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .overlay(alignment: .top) {
                if let banner = pendingBanner {
                    TicketPendingSyncBanner(text: banner)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                }
            }
        }
    }
}

// MARK: - Labeled field helper

/// Shared inline-label text field for ticket edit form. Separate from
/// `LabeledTextField` (Customers package) so Tickets doesn't import
/// Customers just for a UI helper.
private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences

    init(
        _ label: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        autocapitalize: TextInputAutocapitalization = .sentences
    ) {
        self.label = label
        self._text = text
        self.keyboard = keyboard
        self.autocapitalize = autocapitalize
    }

    var body: some View {
        TextField(label, text: $text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocapitalize)
    }
}
#endif
