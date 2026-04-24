import SwiftUI
import DesignSystem

// MARK: - ABTestConfigSheetViewModel

/// View-model for the A/B test configuration sheet.
/// Pure Swift value mutations; no API calls — all data is client-side.
@Observable
@MainActor
public final class ABTestConfigSheetViewModel {

    // MARK: - Split presets

    public enum SplitPreset: String, CaseIterable, Sendable {
        case fiftyFifty  = "50 / 50"
        case sixtyForty  = "60 / 40"
        case custom      = "Custom"
    }

    // MARK: - State

    public var selectedPreset: SplitPreset = .fiftyFifty {
        didSet { applyPreset() }
    }

    public var variants: [ABTestVariant] = ABTestVariant.fiftyFifty()

    public var validationError: SplitRatioValidator.ValidationError? {
        SplitRatioValidator.validate(variants)
    }

    public var isValid: Bool { validationError == nil }

    public var totalPercent: Int { SplitRatioValidator.total(variants) }

    // MARK: - Init

    public init(initial: [ABTestVariant]? = nil) {
        if let initial, !initial.isEmpty {
            variants = initial
            selectedPreset = preset(for: initial)
        }
    }

    // MARK: - Mutations (immutable-style: always replace, never mutate in-place)

    /// Updates the label of variant at `index`. Returns without effect if index is out of range.
    public func updateLabel(_ label: String, at index: Int) {
        guard variants.indices.contains(index) else { return }
        var updated = variants[index]
        updated.label = label
        variants = variants.enumerated().map { $0.offset == index ? updated : $0.element }
    }

    /// Updates the message of variant at `index`. Returns without effect if index is out of range.
    public func updateMessage(_ message: String, at index: Int) {
        guard variants.indices.contains(index) else { return }
        var updated = variants[index]
        updated.message = message
        variants = variants.enumerated().map { $0.offset == index ? updated : $0.element }
    }

    /// Updates the split percent of variant at `index`. Clamps the raw string to 0…100.
    public func updateSplitPercent(_ rawValue: String, at index: Int) {
        guard variants.indices.contains(index),
              let parsed = Int(rawValue.trimmingCharacters(in: .whitespaces))
        else { return }
        let clamped = max(0, min(100, parsed))
        var updated = variants[index]
        updated.splitPercent = clamped
        variants = variants.enumerated().map { $0.offset == index ? updated : $0.element }
        selectedPreset = preset(for: variants)
    }

    /// Adds a new blank variant with 0% split (user must adjust to make valid).
    public func addVariant() {
        let next = ABTestVariant(
            label: "Variant \(variantLetter(variants.count))",
            message: "",
            splitPercent: 0
        )
        variants = variants + [next]
        selectedPreset = .custom
    }

    /// Removes the variant at `index`. Requires at least 3 variants (keeps minimum 2).
    public func removeVariant(at index: Int) {
        guard variants.count > 2, variants.indices.contains(index) else { return }
        variants = variants.enumerated().compactMap { $0.offset == index ? nil : $0.element }
        selectedPreset = preset(for: variants)
    }

    // MARK: - Private helpers

    private func applyPreset() {
        switch selectedPreset {
        case .fiftyFifty:
            let msgs = variantMessages()
            variants = [
                ABTestVariant(id: variants[safe: 0]?.id ?? UUID().uuidString, label: "Variant A", message: msgs.0, splitPercent: 50),
                ABTestVariant(id: variants[safe: 1]?.id ?? UUID().uuidString, label: "Variant B", message: msgs.1, splitPercent: 50),
            ]
        case .sixtyForty:
            let msgs = variantMessages()
            variants = [
                ABTestVariant(id: variants[safe: 0]?.id ?? UUID().uuidString, label: "Variant A", message: msgs.0, splitPercent: 60),
                ABTestVariant(id: variants[safe: 1]?.id ?? UUID().uuidString, label: "Variant B", message: msgs.1, splitPercent: 40),
            ]
        case .custom:
            break // User edits individual fields; no forced reset.
        }
    }

    private func variantMessages() -> (String, String) {
        (variants[safe: 0]?.message ?? "", variants[safe: 1]?.message ?? "")
    }

    private func preset(for vs: [ABTestVariant]) -> SplitPreset {
        guard vs.count == 2 else { return .custom }
        let splits = vs.map(\.splitPercent)
        if splits == [50, 50] { return .fiftyFifty }
        if splits == [60, 40] { return .sixtyForty }
        return .custom
    }

    private func variantLetter(_ index: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        guard index < letters.count else { return String(index + 1) }
        return String(letters[letters.index(letters.startIndex, offsetBy: index)])
    }
}

// MARK: - Private Collection helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - ABTestConfigSheet

/// Sheet that lets a marketer configure A/B split variants for a campaign.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showingABTest) {
///     ABTestConfigSheet(initial: campaign.abVariants) { variants in
///         campaign.abVariants = variants
///     }
/// }
/// ```
public struct ABTestConfigSheet: View {
    @State private var vm: ABTestConfigSheetViewModel
    @Environment(\.dismiss) private var dismiss

    private let onSave: ([ABTestVariant]) -> Void

    public init(
        initial: [ABTestVariant]? = nil,
        onSave: @escaping ([ABTestVariant]) -> Void
    ) {
        _vm = State(initialValue: ABTestConfigSheetViewModel(initial: initial))
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                presetSection
                variantsSection
                summarySection
            }
            .navigationTitle("A/B Test Setup")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(vm.variants)
                        dismiss()
                    }
                    .disabled(!vm.isValid)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var presetSection: some View {
        Section("Split Preset") {
            Picker("Preset", selection: $vm.selectedPreset) {
                ForEach(ABTestConfigSheetViewModel.SplitPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Split preset selector")
        }
    }

    @ViewBuilder
    private var variantsSection: some View {
        Section {
            ForEach(Array(vm.variants.enumerated()), id: \.element.id) { index, variant in
                variantRow(index: index, variant: variant)
            }

            Button {
                vm.addVariant()
            } label: {
                Label("Add Variant", systemImage: "plus.circle")
            }
            .accessibilityLabel("Add variant")
        } header: {
            HStack {
                Text("Variants")
                Spacer()
                Text("Total: \(vm.totalPercent)%")
                    .foregroundStyle(vm.totalPercent == 100 ? Color.green : Color.bizarreError)
                    .font(.brandLabelSmall())
                    .accessibilityLabel("Total split: \(vm.totalPercent) percent")
            }
        }
    }

    @ViewBuilder
    private func variantRow(index: Int, variant: ABTestVariant) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                TextField("Label", text: Binding(
                    get: { variant.label },
                    set: { vm.updateLabel($0, at: index) }
                ))
                .font(.brandBodyMedium().bold())
                .accessibilityLabel("Variant \(index + 1) label")

                Spacer()

                HStack(spacing: 4) {
                    TextField("0", text: Binding(
                        get: { String(variant.splitPercent) },
                        set: { vm.updateSplitPercent($0, at: index) }
                    ))
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .accessibilityLabel("Variant \(index + 1) split percent")

                    Text("%")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if vm.variants.count > 2 {
                    Button(role: .destructive) {
                        vm.removeVariant(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.bizarreError)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove variant \(index + 1)")
                }
            }

            TextField("Message for this variant", text: Binding(
                get: { variant.message },
                set: { vm.updateMessage($0, at: index) }
            ), axis: .vertical)
            .lineLimit(2...4)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .accessibilityLabel("Variant \(index + 1) message")
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    @ViewBuilder
    private var summarySection: some View {
        if let error = vm.validationError {
            Section {
                Label(error.localizedDescription ?? "Invalid configuration", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Validation error: \(error.localizedDescription ?? "")")
            }
        } else {
            Section("Preview") {
                ForEach(vm.variants) { variant in
                    LabeledContent(variant.label) {
                        Text("\(variant.splitPercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
    }
}
