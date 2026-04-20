#if canImport(UIKit)
import SwiftUI
import DesignSystem

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

/// Edit the price of a cart row. Stores to cents via `CartMath`. Later
/// phases gate this behind a manager PIN for overrides beyond a threshold
/// (§16.11) — scaffold ships unguarded.
struct PosEditPriceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentCents: Int
    let onSave: (Int) -> Void

    @State private var text: String = ""
    @State private var errorMessage: String?

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
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: trimmed), value >= 0 else {
            errorMessage = "Price must be a non-negative number."
            return
        }
        onSave(CartMath.toCents(value))
        dismiss()
    }
}
#endif
