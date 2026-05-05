#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.14 — "Hold cart" sheet that snapshots the current cart to
/// `HeldCartStore` (local-first, no server round-trip in MVP).
///
/// On save: current cart is cleared and the snapshot is written to the store.
/// `onSaved(UUID)` fires so the caller can dismiss + show a toast.
public struct HoldCartSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cart: Cart
    let onSaved: (UUID) -> Void

    @State private var note:       String = ""
    @State private var isSaving:   Bool   = false
    @State private var errorMsg:   String? = nil

    public init(cart: Cart, onSaved: @escaping (UUID) -> Void) {
        self.cart    = cart
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Summary") {
                        LabeledContent("Items", value: "\(cart.lineCount)")
                        LabeledContent("Total") {
                            Text(CartMath.formatCents(cart.totalCents))
                                .monospacedDigit()
                                .font(.brandBodyLarge())
                        }
                        if let customer = cart.customer {
                            LabeledContent("Customer", value: customer.displayName)
                        }
                    }

                    Section {
                        TextField("Note (optional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("holdCart.note")
                    } header: {
                        Text("Note")
                    } footer: {
                        Text("Displayed in the held-carts list so staff can identify this cart.")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }

                    if let errorMsg {
                        Section {
                            Text(errorMsg)
                                .foregroundStyle(.bizarreError)
                                .font(.brandBodyMedium())
                                .accessibilityIdentifier("holdCart.error")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Hold Cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("holdCart.save")
                    }
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMsg = nil
        let snapshot  = await CartSnapshot.from(cart: cart)
        let trimmed   = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let held = HeldCart(
            cart:       snapshot,
            customerId: cart.customer?.id,
            note:       trimmed.isEmpty ? nil : trimmed
        )
        await HeldCartStore.shared.save(held)
        isSaving = false
        onSaved(held.id)
    }
}
#endif
