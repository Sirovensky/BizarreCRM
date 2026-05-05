#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.10 Credit Note Compose Sheet — issue credit note standalone or tied to invoice

@MainActor
@Observable
final class CreditNoteComposeViewModel {
    var customerId: Int64?
    var customerName: String = ""
    var originalInvoiceId: Int64?
    var amountString: String = ""
    var amountCents: Int = 0
    var reason: String = ""
    var issueDate: Date = .now

    var isSubmitting: Bool = false
    var errorMessage: String?
    var created: CreditNote?

    @ObservationIgnored private let repo: CreditNoteRepository

    init(
        repo: CreditNoteRepository,
        prefilledCustomerId: Int64? = nil,
        prefilledInvoiceId: Int64? = nil
    ) {
        self.repo = repo
        self.customerId = prefilledCustomerId
        self.originalInvoiceId = prefilledInvoiceId
    }

    var isValid: Bool {
        customerId != nil && amountCents > 0 && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func updateAmount(from string: String) {
        amountString = string
        if let dollars = Double(string.filter { $0.isNumber || $0 == "." }) {
            amountCents = Int((dollars * 100).rounded())
        }
    }

    func save() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let ymd = DateFormatter.yyyyMMdd
        let req = CreateCreditNoteRequest(
            customerId: customerId!,
            originalInvoiceId: originalInvoiceId,
            amountCents: amountCents,
            reason: reason.trimmingCharacters(in: .whitespaces),
            issueDate: ymd.string(from: issueDate)
        )

        do {
            created = try await repo.create(req)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

public struct CreditNoteComposeSheet: View {
    @State private var vm: CreditNoteComposeViewModel
    @Environment(\.dismiss) private var dismiss
    private let onCreated: (CreditNote) -> Void

    public init(
        repo: CreditNoteRepository,
        prefilledCustomerId: Int64? = nil,
        prefilledInvoiceId: Int64? = nil,
        onCreated: @escaping (CreditNote) -> Void
    ) {
        _vm = State(wrappedValue: CreditNoteComposeViewModel(
            repo: repo,
            prefilledCustomerId: prefilledCustomerId,
            prefilledInvoiceId: prefilledInvoiceId
        ))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Credit details") {
                    HStack {
                        Text("Amount (USD)")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        TextField("0.00", text: $vm.amountString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vm.amountString) { _, new in
                                vm.updateAmount(from: new)
                            }
                            .accessibilityLabel("Credit amount in dollars")
                    }

                    DatePicker("Issue date", selection: $vm.issueDate, displayedComponents: .date)
                        .accessibilityLabel("Credit note issue date")
                }

                Section("Reason") {
                    TextEditor(text: $vm.reason)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Reason for credit note")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .navigationTitle(vm.originalInvoiceId != nil ? "Credit Note for Invoice" : "Issue Credit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Issue") {
                        Task {
                            await vm.save()
                            if let note = vm.created {
                                onCreated(note)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .accessibilityLabel("Issue credit note")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
