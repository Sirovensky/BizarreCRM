#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Persistence

/// §16.10 — Mid-shift cash-drop sheet.
///
/// A "cash drop" removes excess cash from the open drawer and moves it to the
/// safe. The cashier enters the drop amount and an optional reason; the sheet
/// posts to `POST /api/v1/pos/cash-out` via `CashSessionRepositoryImpl` (or
/// logs locally when no API is configured). The audit entry is also written to
/// `PosAuditLogStore` so the Z-report variance card can surface it.
///
/// Glass is used only on the nav-bar chrome, not on the card itself
/// (per GlassKit / CLAUDE.md rule: glass = chrome role only).
public struct PosCashDropSheet: View {

    public let onDropRecorded: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: PosCashDropViewModel

    public init(
        cashSessionId: Int64?,
        cashSessionRepo: (any CashSessionRepository)? = nil,
        onDropRecorded: @escaping (Int) -> Void
    ) {
        self.onDropRecorded = onDropRecorded
        _vm = State(wrappedValue: PosCashDropViewModel(
            cashSessionId: cashSessionId,
            repo: cashSessionRepo
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Cash drop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Record drop") {
                            Task { await commitDrop() }
                        }
                        .disabled(!vm.canSubmit)
                        .accessibilityIdentifier("pos.cashDrop.submit")
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    private var contentBody: some View {
        Form {
            Section {
                HStack(spacing: BrandSpacing.sm) {
                    Text("Drop amount")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer(minLength: BrandSpacing.md)
                    Text("$")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .font(.brandHeadlineMedium())
                        .frame(minWidth: 80)
                        .accessibilityIdentifier("pos.cashDrop.amountField")
                }
            } header: {
                Text("Amount to remove from drawer")
            } footer: {
                if let err = vm.amountValidationError {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }

            Section("Reason (optional)") {
                TextField("e.g. Manager drop to safe", text: $vm.reason, axis: .vertical)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("pos.cashDrop.reason")
            }

            if let result = vm.result {
                Section {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                        Text(result)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreSuccess)
                    }
                    .accessibilityIdentifier("pos.cashDrop.success")
                }
            }

            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityIdentifier("pos.cashDrop.error")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Commit

    private func commitDrop() async {
        await vm.submit()
        if let dropCents = vm.recordedCents {
            // Small pause so the success state is visible before auto-dismiss.
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
            onDropRecorded(dropCents)
        }
    }
}

// MARK: - PosCashDropViewModel

@MainActor
@Observable
final class PosCashDropViewModel {

    var amountText: String = ""
    var reason: String = ""
    private(set) var isSubmitting: Bool = false
    private(set) var result: String? = nil
    private(set) var errorMessage: String? = nil
    /// Set after a successful drop so the host can be notified.
    private(set) var recordedCents: Int? = nil

    @ObservationIgnored private let cashSessionId: Int64?
    @ObservationIgnored private let repo: (any CashSessionRepository)?

    init(cashSessionId: Int64?, repo: (any CashSessionRepository)?) {
        self.cashSessionId = cashSessionId
        self.repo = repo
    }

    // MARK: - Derived

    var dropCents: Int {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed), value > 0 else { return 0 }
        return CartMath.toCents(value)
    }

    var amountValidationError: String? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Decimal(string: trimmed), value > 0 else {
            return "Amount must be a positive number."
        }
        if dropCents > 5_000_000 { return "Amount cannot exceed $50,000." }
        return nil
    }

    var canSubmit: Bool {
        !isSubmitting && dropCents > 0 && amountValidationError == nil && result == nil
    }

    // MARK: - Submit

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let cents = dropCents
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let repo {
                _ = try await repo.postCashOut(amountCents: cents, reason: trimmedReason.isEmpty ? nil : trimmedReason)
            }
            // Audit log — fire-and-forget so a log failure never blocks the cashier.
            Task {
                try? await PosAuditLogStore.shared.record(
                    event: PosAuditEntry.EventType.cashDrop,
                    cashierId: 0,
                    reason: trimmedReason.isEmpty ? "Cash drop \(CartMath.formatCents(cents))" : trimmedReason
                )
            }
            let formatted = CartMath.formatCents(cents)
            result = "\(formatted) removed from drawer"
            recordedCents = cents
        } catch {
            errorMessage = error.localizedDescription
        }

        isSubmitting = false
    }
}
#endif
