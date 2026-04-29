#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Persistence

// MARK: - §16.11 Unified line-edit bottom sheet (mockup screen 4)
//
// Mockup spec: .presentationDetents([.height(320), .medium])
// Layout:  handle · title · SKU sub · Qty stepper row · price row ·
//          discount row · note row · [Remove | Save · $x.xx] buttons
//
// Replaces the old NavigationStack+Form approach which was inconsistent
// with the mockup's compact bottom-sheet detent.

struct PosLineEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let item: CartItem
    let onSave: (Int, Int, String?) -> Void     // qty, discountCents, note
    let onRemove: () -> Void

    // Local working copies
    @State private var qty: Int
    @State private var discountText: String
    @State private var note: String
    @State private var showingDiscountField: Bool
    @State private var showingNoteField: Bool

    init(
        item: CartItem,
        onSave: @escaping (Int, Int, String?) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.item = item
        self.onSave = onSave
        self.onRemove = onRemove
        _qty = State(initialValue: item.quantity)
        let discCents = item.discountCents
        _discountText = State(initialValue: discCents > 0 ? String(format: "%.2f", Double(discCents) / 100) : "")
        _note = State(initialValue: item.notes ?? "")
        _showingDiscountField = State(initialValue: item.discountCents > 0)
        _showingNoteField = State(initialValue: !(item.notes ?? "").isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle — 40×5 pt, matches mockup rgba(255,255,255,0.22)
            Capsule()
                .fill(Color.bizarreOnSurface.opacity(0.22))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Title + SKU
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(sku)
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Text("Qty \(item.quantity)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider().background(.bizarreOutline)

            // Qty stepper row — mockup: circle buttons 36×36, val in Barlow 22/700, + fills orange
            lineRow(label: "Qty") {
                LineEditStepper(
                    quantity: qty,
                    onIncrement: { BrandHaptics.tap(); qty += 1 },
                    onDecrement: { BrandHaptics.tap(); if qty > 1 { qty -= 1 } }
                )
            }

            Divider().background(.bizarreOutline)

            // Unit price (display-only) — mockup: var(--font-display) 18px/700
            lineRow(label: "Unit price") {
                Text(CartMath.formatCents(CartMath.toCents(item.unitPrice)))
                    .font(.custom("BarlowCondensed-Bold", size: 18))
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            Divider().background(.bizarreOutline)

            // Line discount row
            if showingDiscountField {
                lineRow(label: "Line discount") {
                    HStack(spacing: 6) {
                        Text("$")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("0.00", text: $discountText)
                            .keyboardType(.decimalPad)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("pos.lineEdit.discount")
                    }
                }
                Divider().background(.bizarreOutline)
            } else {
                lineRow(label: "Line discount") {
                    Button {
                        BrandHaptics.tap()
                        withAnimation(.spring(response: 0.25)) {
                            showingDiscountField = true
                        }
                    } label: {
                        Text("+ Apply")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.bizarreTeal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply line discount")
                }
                Divider().background(.bizarreOutline)
            }

            // Note row
            if showingNoteField {
                lineRow(label: "Note") {
                    TextField("Receipt note…", text: $note)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(maxWidth: 180)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("pos.lineEdit.note")
                }
                Divider().background(.bizarreOutline)
            } else {
                lineRow(label: "Note") {
                    Button {
                        BrandHaptics.tap()
                        withAnimation(.spring(response: 0.25)) {
                            showingNoteField = true
                        }
                    } label: {
                        Text("+ Add")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.bizarreTeal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add receipt note")
                }
                Divider().background(.bizarreOutline)
            }

            // Action buttons: [Remove] [Save · $x.xx]
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    BrandHaptics.tap()
                    onRemove()
                    dismiss()
                } label: {
                    Text("Remove")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.bizarreError)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.bizarreError.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.bizarreError.opacity(0.35), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.lineEdit.remove")

                Button {
                    BrandHaptics.success()
                    let discCents = discountCentsFromText()
                    let noteVal = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(qty, discCents, noteVal.isEmpty ? nil : noteVal)
                    dismiss()
                } label: {
                    Text("Save · \(lineTotalString)")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.bizarreOnOrange)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.bizarreOrangeContainer, Color.bizarreOrange],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pos.lineEdit.save")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.hidden) // we draw our own handle above
        .presentationBackground(Color.bizarreSurface1)
        .accessibilityIdentifier("pos.lineEditSheet")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func lineRow<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
    }

    private var lineTotalString: String {
        let discCents = discountCentsFromText()
        let subtotal = CartMath.toCents(item.unitPrice * Decimal(qty))
        let final = max(0, subtotal - discCents)
        return CartMath.formatCents(final)
    }

    private func discountCentsFromText() -> Int {
        guard showingDiscountField,
              let v = Double(discountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              v > 0 else { return 0 }
        return Int((v * 100).rounded())
    }
}

// MARK: - §16.11 Qty-only edit (context menu shortcut)

/// Compact qty-only edit. Used when the caller wants only the qty stepper
/// without the full line-edit surface (e.g. context-menu "Edit quantity").
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
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
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

// MARK: - §16.11 Price-only edit with manager PIN gate

/// Edit the price of a cart row with manager PIN gate.
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
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
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

// MARK: - LineEditStepper (private, sheet-only)
//
// Inline stepper matching mockup screen 4:
//  − button: 36×36 circle, muted surface bg + faint border
//  value:    Barlow Condensed 22/700, tabular nums, min-width 26
//  + button: 36×36 circle, orange fill, orange shadow

private struct LineEditStepper: View {
    let quantity: Int
    let onIncrement: () -> Void
    let onDecrement: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Minus — muted circle
            Button(action: onDecrement) {
                Text("−")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.bizarreOnSurface.opacity(0.05))
                            .overlay(Circle().strokeBorder(Color.bizarreOnSurface.opacity(0.12), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease quantity")
            .accessibilityIdentifier("pos.lineEdit.qty.decrease")

            // Value — read out as the live stepper value so a screen-reader
            // sweep over the three controls says "Decrease quantity, Quantity 3,
            // Increase quantity" instead of an unlabeled middle node.
            Text("\(quantity)")
                .font(.custom("BarlowCondensed-Bold", size: 22))
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .frame(minWidth: 26, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Quantity")
                .accessibilityValue("\(quantity)")
                .accessibilityIdentifier("pos.lineEdit.qty.value")

            // Plus — orange circle
            Button(action: onIncrement) {
                Text("+")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.bizarreOnOrange)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.bizarreOrange)
                            .shadow(color: Color.bizarreOrange.opacity(0.30), radius: 8, x: 0, y: 6)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase quantity")
            .accessibilityIdentifier("pos.lineEdit.qty.increase")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quantity stepper")
    }
}
#endif
