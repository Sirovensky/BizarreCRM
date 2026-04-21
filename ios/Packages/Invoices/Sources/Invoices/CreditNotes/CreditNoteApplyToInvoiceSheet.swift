#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.10 Apply existing credit note toward a new invoice

@MainActor
@Observable
final class CreditNoteApplyViewModel {
    var selectedCreditNoteId: Int64?
    var applyCents: Int = 0
    var applyString: String = ""

    var availableNotes: [CreditNote] = []
    var isLoadingNotes: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?
    var didApply: Bool = false

    @ObservationIgnored private let repo: CreditNoteRepository
    @ObservationIgnored private let customerId: Int64
    @ObservationIgnored private let targetInvoiceId: Int64
    @ObservationIgnored private let maxApplyCents: Int

    init(
        repo: CreditNoteRepository,
        customerId: Int64,
        targetInvoiceId: Int64,
        maxApplyCents: Int
    ) {
        self.repo = repo
        self.customerId = customerId
        self.targetInvoiceId = targetInvoiceId
        self.maxApplyCents = maxApplyCents
    }

    var selectedNote: CreditNote? {
        availableNotes.first { $0.id == selectedCreditNoteId }
    }

    var effectiveCap: Int {
        min(selectedNote?.amountCents ?? 0, maxApplyCents)
    }

    var isValid: Bool {
        selectedCreditNoteId != nil && applyCents > 0 && applyCents <= effectiveCap
    }

    func loadNotes() async {
        isLoadingNotes = true
        defer { isLoadingNotes = false }
        do {
            let notes = try await repo.list(customerId: customerId)
            availableNotes = notes.filter { $0.status == .open }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateApplyAmount(from string: String) {
        applyString = string
        if let dollars = Double(string.filter { $0.isNumber || $0 == "." }) {
            applyCents = Int((dollars * 100).rounded())
        }
    }

    func apply() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let req = ApplyCreditNoteRequest(
            creditNoteId: selectedCreditNoteId!,
            targetInvoiceId: targetInvoiceId,
            applyCents: applyCents
        )
        do {
            _ = try await repo.apply(req)
            didApply = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct CreditNoteApplyToInvoiceSheet: View {
    @State private var vm: CreditNoteApplyViewModel
    @Environment(\.dismiss) private var dismiss
    private let onApplied: () async -> Void

    public init(
        repo: CreditNoteRepository,
        customerId: Int64,
        targetInvoiceId: Int64,
        invoiceBalanceCents: Int,
        onApplied: @escaping () async -> Void
    ) {
        _vm = State(wrappedValue: CreditNoteApplyViewModel(
            repo: repo,
            customerId: customerId,
            targetInvoiceId: targetInvoiceId,
            maxApplyCents: invoiceBalanceCents
        ))
        self.onApplied = onApplied
    }

    public var body: some View {
        NavigationStack {
            Group {
                if vm.isLoadingNotes {
                    ProgressView("Loading credits…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.availableNotes.isEmpty {
                    emptyState
                } else {
                    form
                }
            }
            .navigationTitle("Apply Credit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task {
                            await vm.apply()
                            if vm.didApply {
                                await onApplied()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .task { await vm.loadNotes() }
        }
        .presentationDetents([.medium, .large])
    }

    private var form: some View {
        Form {
            Section("Select credit note") {
                Picker("Credit note", selection: $vm.selectedCreditNoteId) {
                    Text("Select…").tag(Optional<Int64>.none)
                    ForEach(vm.availableNotes) { note in
                        Text("\(note.referenceNumber ?? "CN-\(note.id)"): \(formatMoney(note.amountCents))")
                            .tag(Optional(note.id))
                    }
                }
                .accessibilityLabel("Credit note to apply")

                if let note = vm.selectedNote {
                    HStack {
                        Text("Available")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(formatMoney(note.amountCents))
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }

            if vm.selectedCreditNoteId != nil {
                Section("Amount to apply") {
                    HStack {
                        Text("Apply (USD)")
                        Spacer()
                        TextField("0.00", text: $vm.applyString)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: vm.applyString) { _, new in
                                vm.updateApplyAmount(from: new)
                            }
                            .accessibilityLabel("Amount to apply from credit note")
                    }
                    if vm.applyCents > vm.effectiveCap {
                        Text("Maximum applicable: \(formatMoney(vm.effectiveCap))")
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }

            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.bizarreError)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No open credit notes")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("This customer has no available credit notes.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func formatMoney(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
