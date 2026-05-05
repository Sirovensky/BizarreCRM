#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// "Add custom line" sheet (§16.2 — untracked line). Shipped in Phase 2 as
/// a plain form; role-gating + tax-exempt toggle land when the permissions
/// layer arrives (§6.8).
struct PosCustomLineSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CartItem) -> Void

    @State private var name: String = ""
    @State private var priceText: String = ""
    @State private var quantityText: String = "1"
    @State private var taxRateText: String = ""
    @State private var notes: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Line") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                    TextField("Quantity", text: $quantityText)
                        .keyboardType(.numberPad)
                }
                Section("Optional") {
                    TextField("Tax rate (e.g. 0.07)", text: $taxRateText)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
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
            .navigationTitle("Custom line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: commit)
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && Decimal(string: priceText.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }
        let priceString = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let price = Decimal(string: priceString), price >= 0 else {
            errorMessage = "Price must be a number."
            return
        }
        let qty = max(1, Int(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
        let tax: Decimal?
        let taxString = taxRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if taxString.isEmpty {
            tax = nil
        } else {
            guard let parsed = Decimal(string: taxString), parsed >= 0 else {
                errorMessage = "Tax rate must be a non-negative number (e.g. 0.07)."
                return
            }
            tax = parsed
        }
        let noteValue = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CartItem(
            inventoryItemId: nil,
            name: trimmedName,
            sku: nil,
            quantity: qty,
            unitPrice: price,
            taxRate: tax,
            discountCents: 0,
            notes: noteValue.isEmpty ? nil : noteValue
        )
        BrandHaptics.success()
        onSave(item)
        dismiss()
    }
}
#endif
