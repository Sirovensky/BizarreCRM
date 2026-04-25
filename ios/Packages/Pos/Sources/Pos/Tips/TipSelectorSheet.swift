#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - TipSelection

/// The value emitted when the cashier confirms a tip choice.
public enum TipSelection: Equatable, Sendable {
    /// One of the four preset chips was chosen.
    case preset(TipPreset)
    /// The cashier typed a custom amount (in cents).
    case custom(Int)
    /// No tip — the cashier dismissed without choosing.
    case none
}

// MARK: - TipSelectorViewModel

/// Drives `TipSelectorSheet`. All state is value-type-safe; mutations return
/// new instances via `@Observable`'s observation graph.
@MainActor
@Observable
public final class TipSelectorViewModel {

    // MARK: - Input

    /// Subtotal in cents — used for live percentage previews on chips.
    public let subtotalCents: Int
    /// Presets supplied by the parent view (loaded from `TipPresetStore`).
    public let presets: [TipPreset]

    // MARK: - Sheet state

    /// The currently highlighted preset chip, if any.
    public private(set) var selectedPreset: TipPreset?
    /// Raw string typed in the custom-amount field (interpreted as cents).
    public var customInput: String = ""
    /// When `true`, the round-up toggle is engaged and the final tip snaps to
    /// the next whole dollar.
    public var roundUpEnabled: Bool = false
    /// `true` while the custom text-field is the active entry mode.
    public var isCustomMode: Bool = false

    // MARK: - Computed

    /// Tip amount in cents that would be applied if confirmed right now.
    public var previewCents: Int {
        if isCustomMode {
            guard let raw = Int(customInput), raw > 0 else { return 0 }
            return TipCalculator.computeCustom(
                subtotalCents: subtotalCents,
                customCents: raw,
                roundUp: roundUpEnabled
            ).finalCents
        }
        guard let preset = selectedPreset else { return 0 }
        return TipCalculator.compute(
            subtotalCents: subtotalCents,
            preset: preset,
            roundUp: roundUpEnabled
        ).finalCents
    }

    /// Human-readable preview string, e.g. "$3.60".
    public var previewLabel: String {
        previewCents > 0
            ? CartMath.formatCents(previewCents)
            : "No tip"
    }

    /// `true` when the sheet has a confirmed selection ready.
    public var canConfirm: Bool {
        if isCustomMode {
            return (Int(customInput) ?? 0) > 0
        }
        return selectedPreset != nil
    }

    // MARK: - Init

    public init(subtotalCents: Int, presets: [TipPreset] = TipPreset.defaults) {
        self.subtotalCents = subtotalCents
        self.presets = Array(presets.prefix(TipPresetStore.maxPresets))
    }

    // MARK: - Actions

    /// Select a preset chip. Deselects on second tap (toggle behaviour).
    public func selectPreset(_ preset: TipPreset) {
        isCustomMode = false
        selectedPreset = selectedPreset?.id == preset.id ? nil : preset
    }

    /// Switch to custom-entry mode.
    public func activateCustomMode() {
        selectedPreset = nil
        isCustomMode = true
    }

    /// Build the final `TipSelection` to emit on confirm.
    public func buildSelection() -> TipSelection {
        if isCustomMode {
            guard let raw = Int(customInput), raw > 0 else { return .none }
            let result = TipCalculator.computeCustom(
                subtotalCents: subtotalCents,
                customCents: raw,
                roundUp: roundUpEnabled
            )
            return .custom(result.finalCents)
        }
        guard let preset = selectedPreset else { return .none }
        return .preset(preset)
    }

    /// Validate custom input: only digits, max 6 chars (≤ $9 999.99).
    public var customInputError: String? {
        guard isCustomMode, !customInput.isEmpty else { return nil }
        guard customInput.allSatisfy(\.isNumber) else {
            return "Enter a whole number of cents (e.g. 200 = $2.00)."
        }
        guard let v = Int(customInput), v > 0 else {
            return "Tip must be greater than zero."
        }
        guard v <= 999_999 else {
            return "Maximum tip is $9,999.99."
        }
        return nil
    }
}

// MARK: - TipSelectorSheet

/// §16 — Tip preset picker sheet.
///
/// ## Layout
/// - Header badge + subtitle showing the subtotal.
/// - 2×2 grid of preset chips (percentage or fixed-cents labels).
/// - "Custom" chip that opens an inline cent-amount text field.
/// - Round-up toggle row.
/// - Live preview footer showing the computed tip amount.
/// - "Apply tip" / "No tip" CTA pair.
///
/// ## Design
/// - `bizarreSurfaceBase` full-bleed background (matches all POS sheets).
/// - Liquid Glass chrome on sheet toolbar via `.brandGlass` button style.
/// - `.medium` + `.large` detent with drag indicator.
public struct TipSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var vm: TipSelectorViewModel

    public let subtotalCents: Int
    public let presets: [TipPreset]
    public let onSelected: @MainActor (TipSelection) -> Void

    public init(
        subtotalCents: Int,
        presets: [TipPreset] = TipPreset.defaults,
        onSelected: @escaping @MainActor (TipSelection) -> Void
    ) {
        self.subtotalCents = subtotalCents
        self.presets = presets
        self.onSelected = onSelected
        _vm = State(initialValue: TipSelectorViewModel(
            subtotalCents: subtotalCents,
            presets: presets
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.xl) {
                        headerSection
                        presetGrid
                        customSection
                        roundUpToggle
                        previewRow
                        actionButtons
                        Spacer(minLength: BrandSpacing.xxl)
                    }
                    .padding(.top, BrandSpacing.lg)
                    .padding(.horizontal, BrandSpacing.base)
                }
            }
            .navigationTitle("Add Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onSelected(.none)
                        dismiss()
                    }
                    .accessibilityIdentifier("tipSelector.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.xs) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Subtotal: \(CartMath.formatCents(subtotalCents))")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("Subtotal \(CartMath.formatCents(subtotalCents))")
        }
    }

    // 2-column grid for up to 4 chips
    private var presetGrid: some View {
        let columns = [GridItem(.flexible(), spacing: BrandSpacing.sm),
                       GridItem(.flexible(), spacing: BrandSpacing.sm)]
        return LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
            ForEach(vm.presets) { preset in
                presetChip(preset)
            }
            customChip
        }
        .accessibilityIdentifier("tipSelector.presetGrid")
    }

    private func presetChip(_ preset: TipPreset) -> some View {
        let isSelected = vm.selectedPreset?.id == preset.id && !vm.isCustomMode
        return Button {
            vm.selectPreset(preset)
        } label: {
            chipLabel(
                primary: preset.displayName,
                secondary: presetSecondary(preset),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipAccessibilityLabel(preset))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tipSelector.preset.\(preset.displayName)")
    }

    private var customChip: some View {
        let isSelected = vm.isCustomMode
        return Button {
            vm.activateCustomMode()
        } label: {
            chipLabel(primary: "Custom", secondary: nil, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom tip amount")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("tipSelector.customChip")
    }

    private func chipLabel(primary: String, secondary: String?, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text(primary)
                .font(.brandHeadlineMedium())
                .foregroundStyle(isSelected ? Color.bizarreOnPrimary : Color.bizarreOnSurface)
            if let sub = secondary {
                Text(sub)
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSelected ? Color.bizarreOnPrimary.opacity(0.8) : Color.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.md)
        .background(
            isSelected
                ? Color.bizarreOrange
                : Color.bizarreSurface1,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(
                    isSelected ? Color.clear : Color.bizarreOutline.opacity(0.4),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var customSection: some View {
        if vm.isCustomMode {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                HStack {
                    Text("¢")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("e.g. 300 = $3.00", text: $vm.customInput)
                        .keyboardType(.numberPad)
                        .font(.brandHeadlineMedium().monospacedDigit())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Custom tip in cents")
                        .accessibilityIdentifier("tipSelector.customField")
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(customFieldBorderColor, lineWidth: 1.5)
                )

                if let err = vm.customInputError {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityIdentifier("tipSelector.customError")
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var customFieldBorderColor: Color {
        vm.customInputError != nil
            ? Color.bizarreError.opacity(0.7)
            : Color.bizarreOutline.opacity(0.5)
    }

    private var roundUpToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Round up to next dollar")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Rounds the tip up to the nearest $1.00")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Toggle("Round up", isOn: $vm.roundUpEnabled)
                .labelsHidden()
                .tint(.bizarreOrange)
                .accessibilityIdentifier("tipSelector.roundUpToggle")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Round up to next dollar")
        .accessibilityValue(vm.roundUpEnabled ? "On" : "Off")
    }

    private var previewRow: some View {
        HStack {
            Text("Tip amount")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(vm.previewLabel)
                .font(.brandHeadlineMedium().monospacedDigit())
                .foregroundStyle(vm.previewCents > 0 ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: vm.previewCents)
                .accessibilityIdentifier("tipSelector.previewLabel")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip amount: \(vm.previewLabel)")
    }

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                let selection = vm.buildSelection()
                onSelected(selection)
                dismiss()
            } label: {
                Text("Apply tip")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
            }
            .buttonStyle(.brandGlassProminent)
            .disabled(!vm.canConfirm || vm.customInputError != nil)
            .accessibilityIdentifier("tipSelector.applyButton")

            Button {
                onSelected(.none)
                dismiss()
            } label: {
                Text("No tip")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tipSelector.noTipButton")
        }
    }

    // MARK: - Helpers

    private func presetSecondary(_ preset: TipPreset) -> String? {
        guard subtotalCents > 0 else { return nil }
        switch preset.value {
        case .percentage:
            let result = TipCalculator.compute(subtotalCents: subtotalCents, preset: preset)
            return CartMath.formatCents(result.rawCents)
        case .fixedCents:
            return nil
        }
    }

    private func chipAccessibilityLabel(_ preset: TipPreset) -> String {
        switch preset.value {
        case .percentage(let fraction):
            let pct = Int((fraction * 100).rounded())
            if subtotalCents > 0 {
                let result = TipCalculator.compute(subtotalCents: subtotalCents, preset: preset)
                return "\(pct)% tip, \(CartMath.formatCents(result.rawCents))"
            }
            return "\(pct)% tip"
        case .fixedCents(let cents):
            return "\(CartMath.formatCents(cents)) fixed tip"
        }
    }
}

#endif
