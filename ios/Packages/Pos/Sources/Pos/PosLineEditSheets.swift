#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Persistence

/// Edit the quantity of a cart row. Shown from the row's `.contextMenu`.
/// Shared form, tiny surface area — inc / dec / type-in.
struct PosEditQuantitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let current: Int
    let onSave: (Int) -> Void

    @State private var text: String = ""
    @State private var errorMessage: String?

    init(current: Int, onSave: @escaping (Int) -> Void) {
        self.current = current
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quantity") {
                    TextField("Quantity", text: $text)
                        .keyboardType(.numberPad)
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Edit quantity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                }
            }
            .onAppear { if text.isEmpty { text = String(current) } }
        }
    }

    private func commit() {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 1 else {
            errorMessage = "Enter a number ≥ 1."
            return
        }
        onSave(value)
        dismiss()
    }
}

/// §16.11 — Edit the price of a cart row with manager PIN gate.
///
/// If |newPrice − originalPrice| ≥ `PosTenantLimits.current().priceOverrideThresholdCents`,
/// a `ManagerPinSheet` is presented before the override is committed.  On
/// approval the event is logged to `PosAuditLogStore`.
struct PosEditPriceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentCents: Int
    let onSave: (Int) -> Void

    @State private var text: String = ""
    @State private var errorMessage: String?
    @State private var showingManagerPin: Bool = false
    @State private var pendingNewCents: Int? = nil

    init(currentCents: Int, onSave: @escaping (Int) -> Void) {
        self.currentCents = currentCents
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit price") {
                    TextField("Price", text: $text)
                        .keyboardType(.decimalPad)
                }
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Edit price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: commit)
                }
            }
            .onAppear {
                if text.isEmpty {
                    let dollars = Decimal(currentCents) / 100
                    text = NSDecimalNumber(decimal: dollars).stringValue
                }
            }
            // §16.11 — nested manager PIN sheet for large overrides.
            .sheet(isPresented: $showingManagerPin) {
                let limits = PosTenantLimits.current()
                let deltaDesc = CartMath.formatCents(abs((pendingNewCents ?? 0) - currentCents))
                ManagerPinSheet(
                    reason: "Price override \(deltaDesc) exceeds threshold of \(CartMath.formatCents(limits.priceOverrideThresholdCents))",
                    onApproved: { managerId in
                        if let newCents = pendingNewCents {
                            commitPriceOverride(newCents: newCents, managerId: managerId)
                        }
                        pendingNewCents = nil
                    },
                    onCancelled: {
                        pendingNewCents = nil
                    }
                )
            }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed), value >= 0 else {
            errorMessage = "Price must be a non-negative number."
            return
        }
        let newCents = CartMath.toCents(value)
        let delta = abs(newCents - currentCents)
        let limits = PosTenantLimits.current()

        if delta >= limits.priceOverrideThresholdCents && newCents < currentCents {
            // Reduction above the threshold needs manager sign-off.
            pendingNewCents = newCents
            showingManagerPin = true
            return
        }

        // Either an increase or a small reduction — no manager gate.
        commitPriceOverride(newCents: newCents, managerId: nil)
    }

    /// Apply the price and, when a manager approved, emit a `price_override` audit event.
    private func commitPriceOverride(newCents: Int, managerId: Int64?) {
        if let mId = managerId {
            Task {
                try? await PosAuditLogStore.shared.record(
                    event: PosAuditEntry.EventType.priceOverride,
                    cashierId: 0,
                    managerId: mId,
                    amountCents: abs(newCents - currentCents),
                    context: [
                        "originalPriceCents": currentCents,
                        "newPriceCents": newCents
                    ]
                )
            }
        }
        onSave(newCents)
        dismiss()
    }
}
#endif
