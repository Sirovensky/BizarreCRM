/// CartLineEditSheet.swift — §16.22
///
/// Bottom sheet for editing a single cart line: qty, discount preset,
/// per-line note with dictation hook, and remove (audit-gated).
///
/// Presented via `.sheet(item: $editingLine)` from PosCartView.
/// Cart is dimmed behind sheet via parent's `allowsHitTesting(false)` + opacity.
///
/// UX spec: `../pos-phone-mockups.html` frame "4 · Edit line · qty · discount · note".

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - CartLineEditSheet

public struct CartLineEditSheet: View {

    @Bindable var vm: CartLineEditViewModel
    let cart: Cart
    let onSave: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var noteFocused: Bool

    public init(
        vm: CartLineEditViewModel,
        cart: Cart,
        onSave: @escaping () -> Void = {},
        onRemove: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self.cart = cart
        self.onSave = onSave
        self.onRemove = onRemove
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    // Qty stepper row
                    qtyStepper

                    Divider()

                    // Unit price (read-only)
                    unitPriceRow

                    Divider()

                    // Discount chip row
                    discountRow

                    Divider()

                    // Per-line note
                    noteField

                    Divider()

                    // Remove button
                    removeButton
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.lg)
                .padding(.bottom, BrandSpacing.xl)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(vm.itemName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!vm.canSave)
                        .fontWeight(.semibold)
                        .foregroundStyle(vm.canSave ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        .accessibilityIdentifier("pos.lineEdit.saveButton")
                        .accessibilityLabel("Save changes to \(vm.itemName)")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Qty stepper

    private var qtyStepper: some View {
        HStack {
            Text("Quantity")
                .font(.brandTitleMedium())
                .foregroundStyle(Color.bizarreOnSurface)
            Spacer()

            HStack(spacing: BrandSpacing.md) {
                Button {
                    BrandHaptics.tap()
                    vm.decrement()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .frame(width: 36, height: 36)
                        .background(Color.bizarreSurface2, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(vm.qty <= 1)
                .accessibilityLabel("Decrease quantity")

                Text("\(vm.qty)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.bizarreOnSurface)
                    .frame(minWidth: 32)
                    .monospacedDigit()
                    .accessibilityValue("Quantity: \(vm.qty)")

                Button {
                    BrandHaptics.tap()
                    vm.increment()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.bizarreOnSurface)
                        .frame(width: 36, height: 36)
                        .background(Color.bizarreOrange, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(vm.qty >= vm.maxQty)
                .accessibilityLabel("Increase quantity")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quantity stepper")
    }

    // MARK: - Unit price row

    private var unitPriceRow: some View {
        HStack {
            Text("Unit price")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(vm.unitPriceCents))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurface)
                .monospacedDigit()
        }
    }

    // MARK: - Discount chip row

    private var discountRow: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Discount")
                    .font(.brandTitleMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Spacer()
                if vm.derivedDiscountCents > 0 {
                    Text("− \(CartMath.formatCents(vm.derivedDiscountCents))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.bizarreSuccess)
                        .monospacedDigit()
                }
            }

            HStack(spacing: BrandSpacing.sm) {
                ForEach(CartLineDiscountMode.allCases, id: \.self) { mode in
                    discountChip(mode: mode)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Discount preset")

            // Custom amount field
            if vm.discountMode == .fixedCustom {
                HStack {
                    Text("$")
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    TextField("0.00", value: $vm.customDiscountCents, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Color.bizarreOnSurface)
                }
                .padding(.horizontal, BrandSpacing.md)
                .frame(height: 40)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func discountChip(mode: CartLineDiscountMode) -> some View {
        let isActive = vm.discountMode == mode
        return Button {
            BrandHaptics.tap()
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                vm.discountMode = vm.discountMode == mode ? .none : mode
            }
        } label: {
            Text(mode.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    isActive ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityValue(isActive ? "selected" : "not selected")
    }

    // MARK: - Note field

    private var noteField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundStyle(Color.bizarreTeal)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text("Line note")
                    .font(.brandTitleMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                Spacer()
                Text("\(vm.note.count) / \(vm.noteMaxLength)")
                    .font(.system(size: 11))
                    .foregroundStyle(vm.isNoteOverLimit ? Color.bizarreError : Color.bizarreOnSurfaceMuted)
            }

            TextEditor(text: $vm.note)
                .focused($noteFocused)
                .frame(minHeight: 80)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .strokeBorder(
                            vm.isNoteOverLimit ? Color.bizarreError : Color.bizarreOutline.opacity(0.5),
                            lineWidth: 0.5
                        )
                )
                .accessibilityLabel("Line note, optional")
                .accessibilityIdentifier("pos.lineEdit.noteField")
                .overlay(alignment: .topLeading) {
                    if vm.note.isEmpty {
                        Text("Optional note prints on receipt")
                            .font(.brandBodyMedium())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted.opacity(0.6))
                            .padding(BrandSpacing.md)
                            .allowsHitTesting(false)
                    }
                }

            if vm.isNoteOverLimit {
                Text("Note too long — max \(vm.noteMaxLength) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.bizarreError)
            }
        }
    }

    // MARK: - Remove button

    private var removeButton: some View {
        Button {
            BrandHaptics.warning()
            onRemove()
            dismiss()
        } label: {
            Label("Remove from cart", systemImage: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.bizarreError, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pos.lineEdit.removeButton")
    }

    // MARK: - Save

    private func save() {
        vm.applyToCart(cart)
        BrandHaptics.success()
        onSave()
        dismiss()
    }
}
#endif
