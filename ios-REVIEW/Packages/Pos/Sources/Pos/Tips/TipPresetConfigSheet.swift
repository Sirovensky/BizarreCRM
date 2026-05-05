#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - TipPresetConfigViewModel

/// §16 — Drives `TipPresetConfigSheet`. Loads presets from `TipPresetStore`,
/// lets the manager add / remove / edit up to `TipPresetStore.maxPresets`
/// entries, and persists on "Save".
///
/// Changes are staged in `draftPresets` so the cashier can cancel without
/// touching the live store. The `@Observable` macro keeps the sheet in sync
/// with every edit.
@Observable
@MainActor
public final class TipPresetConfigViewModel {

    // MARK: - Draft state

    /// Working copy. Bound to the form rows.
    public var draftPresets: [TipPreset] = []

    /// `true` while the async save is in flight.
    public private(set) var isSaving: Bool = false

    /// Inline validation error (e.g. duplicate percentage).
    public private(set) var validationError: String?

    // MARK: - Dependencies

    private let store: TipPresetStore

    // MARK: - Init

    public init(store: TipPresetStore = .shared) {
        self.store = store
    }

    // MARK: - Lifecycle

    public func load() async {
        draftPresets = await store.load()
    }

    // MARK: - Draft mutations

    /// Add a blank percentage preset (default 18 %) if under the cap.
    public func addPreset() {
        guard draftPresets.count < TipPresetStore.maxPresets else { return }
        let preset = TipPreset(displayName: "18%", value: .percentage(0.18))
        draftPresets.append(preset)
    }

    /// Remove the preset at the given offset (from a `ForEach` delete).
    public func removePreset(at offsets: IndexSet) {
        draftPresets.remove(atOffsets: offsets)
        validationError = nil
    }

    /// Update the percentage for a draft preset by index.
    /// `rawPercent` is an integer like 15, 18, 20, 25.
    /// Out-of-range input (< 1 or > 100) is silently clamped.
    public func setPercentage(_ rawPercent: Int, at index: Int) {
        guard draftPresets.indices.contains(index) else { return }
        let clamped = min(max(rawPercent, 1), 100)
        let fraction = Double(clamped) / 100.0
        let label = "\(clamped)%"
        let old = draftPresets[index]
        draftPresets[index] = TipPreset(id: old.id, displayName: label, value: .percentage(fraction))
        validate()
    }

    /// Update the fixed-cents amount for a draft preset by index.
    public func setFixedCents(_ cents: Int, at index: Int) {
        guard draftPresets.indices.contains(index) else { return }
        guard cents > 0 else { return }
        let label = CartMath.formatCents(cents)
        let old = draftPresets[index]
        draftPresets[index] = TipPreset(id: old.id, displayName: label, value: .fixedCents(cents))
        validate()
    }

    /// Move presets (drag-to-reorder).
    public func move(from source: IndexSet, to destination: Int) {
        draftPresets.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Validation

    private func validate() {
        // Reject duplicate percentage values (e.g. two 20% chips).
        let percents = draftPresets.compactMap { preset -> Double? in
            guard case .percentage(let f) = preset.value else { return nil }
            return f
        }
        let unique = Set(percents)
        if unique.count < percents.count {
            validationError = "Each percentage must be unique."
        } else {
            validationError = nil
        }
    }

    // MARK: - Persistence

    /// Save the draft to `TipPresetStore`. No-ops if validation fails.
    public func save() async {
        validate()
        guard validationError == nil else { return }
        isSaving = true
        defer { isSaving = false }
        await store.save(draftPresets)
    }

    /// Reset to factory defaults (does NOT auto-save — caller confirms).
    public func resetToDefaults() {
        draftPresets = TipPreset.defaults
        validationError = nil
    }
}

// MARK: - TipPresetConfigSheet

/// §16 — Manager-facing sheet for configuring the tip preset chips that
/// cashiers see during checkout.
///
/// ## Features
/// - Edit up to 4 tip presets (percentage or fixed-cent amounts).
/// - Drag-to-reorder.
/// - Inline validation: duplicate percentages surface an error banner.
/// - "Reset to defaults" action restores the built-in 15/18/20/25% row.
/// - "Save" persists via `TipPresetStore`; "Cancel" discards all changes.
///
/// ## Access control
/// This sheet should only be reachable from Settings → Payment → Tipping,
/// behind a manager-PIN gate (§16.11). The gate is enforced at the call site.
public struct TipPresetConfigSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var vm: TipPresetConfigViewModel
    @State private var showResetConfirm = false

    public init(store: TipPresetStore = .shared) {
        _vm = State(initialValue: TipPresetConfigViewModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    presetsSection
                    if let err = vm.validationError {
                        Section {
                            Text(err)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                                .accessibilityIdentifier("tipConfig.validationError")
                        }
                    }
                    actionsSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Tip Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("tipConfig.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            await vm.save()
                            if vm.validationError == nil { dismiss() }
                        }
                    }
                    .disabled(vm.isSaving || vm.validationError != nil)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("tipConfig.save")
                }
            }
            .task { await vm.load() }
            .confirmationDialog(
                "Reset to defaults?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) { vm.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces your current presets with 15%, 18%, 20%, and 25%.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var presetsSection: some View {
        Section {
            ForEach(vm.draftPresets.indices, id: \.self) { index in
                PresetEditRow(
                    preset: vm.draftPresets[index],
                    onPercentChange: { pct in vm.setPercentage(pct, at: index) },
                    onFixedChange: { cents in vm.setFixedCents(cents, at: index) }
                )
                .accessibilityIdentifier("tipConfig.presetRow.\(index)")
            }
            .onDelete { offsets in vm.removePreset(at: offsets) }
            .onMove { from, to in vm.move(from: from, to: to) }

            if vm.draftPresets.count < TipPresetStore.maxPresets {
                Button {
                    vm.addPreset()
                } label: {
                    Label("Add preset", systemImage: "plus.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .font(.brandBodyMedium())
                }
                .accessibilityIdentifier("tipConfig.addPreset")
            }
        } header: {
            HStack {
                Text("Presets (\(vm.draftPresets.count)/\(TipPresetStore.maxPresets))")
                Spacer()
                EditButton()
                    .font(.brandLabelSmall())
                    .tint(.bizarreOrange)
            }
        } footer: {
            Text("Drag to reorder. Swipe left to delete. Cashiers see these chips on the tip screen.")
                .font(.brandLabelSmall())
        }
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(.bizarreError)
            }
            .accessibilityIdentifier("tipConfig.resetDefaults")
        }
    }
}

// MARK: - PresetEditRow

/// A single editable row for one `TipPreset`. Adapts between percentage
/// and fixed-cents input modes via an inline segmented picker.
private struct PresetEditRow: View {
    let preset: TipPreset
    let onPercentChange: (Int) -> Void
    let onFixedChange: (Int) -> Void

    @State private var mode: Mode = .percentage
    @State private var percentText: String = ""
    @State private var centsText: String = ""

    private enum Mode: String, CaseIterable {
        case percentage = "%"
        case fixed = "$"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Picker("Type", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .accessibilityLabel("Tip preset type")

                if mode == .percentage {
                    HStack(spacing: 2) {
                        TextField("18", text: $percentText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .font(.brandBodyLarge())
                            .frame(width: 50)
                            .onChange(of: percentText) { _, newVal in
                                if let v = Int(newVal) { onPercentChange(v) }
                            }
                        Text("%")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                } else {
                    HStack(spacing: 2) {
                        Text("¢")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        TextField("200", text: $centsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .font(.brandBodyLarge())
                            .frame(width: 70)
                            .onChange(of: centsText) { _, newVal in
                                if let v = Int(newVal) { onFixedChange(v) }
                            }
                    }
                }

                Spacer(minLength: BrandSpacing.xs)

                // Preview chip
                Text(preset.displayName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs + 2)
                    .background(Color.bizarreOrange.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .onAppear { syncFromPreset() }
        .onChange(of: preset) { _, _ in syncFromPreset() }
    }

    private func syncFromPreset() {
        switch preset.value {
        case .percentage(let f):
            mode = .percentage
            percentText = "\(Int((f * 100).rounded()))"
        case .fixedCents(let c):
            mode = .fixed
            centsText = "\(c)"
        }
    }
}

#endif
