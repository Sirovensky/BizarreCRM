#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.10 Variant Editor Sheet (admin)

/// Admin sheet for adding/removing variant attributes and auto-generating combinations.
public struct VariantEditorSheet: View {
    @State private var vm: VariantEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(parentSKU: String, api: APIClient) {
        _vm = State(wrappedValue: VariantEditorViewModel(parentSKU: parentSKU, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Manage Variants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOnSurface)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await vm.save(); dismiss() } }
                            .foregroundStyle(.bizarreOrange)
                            .disabled(!vm.isValid)
                    }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
        .brandGlass()
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                attributeSection
                combinationsSection
                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Attribute section

    private var attributeSection: some View {
        Section {
            ForEach(vm.attributeKeys.indices, id: \.self) { idx in
                attributeRow(idx: idx)
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring()) {
                    vm.addAttributeKey()
                }
            } label: {
                Label("Add attribute (color, size, storage…)", systemImage: "plus.circle")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Add new variant attribute")
        } header: {
            Text("Attribute Axes")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func attributeRow(idx: Int) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                TextField("Attribute name (e.g. color)", text: $vm.attributeKeys[idx])
                    .font(.brandBodyMedium())
                    .textInputAutocapitalization(.never)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .spring()) {
                        vm.removeAttributeKey(at: idx)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Remove attribute \(vm.attributeKeys[idx])")
            }

            let valuesBinding = Binding(
                get: { vm.attributeValues[safe: idx] ?? "" },
                set: { vm.setAttributeValues($0, at: idx) }
            )
            TextField("Values, comma-separated (e.g. Red, Blue, Green)", text: valuesBinding)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textInputAutocapitalization(.never)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: Combinations section

    private var combinationsSection: some View {
        Section {
            if vm.generatedCombinations.isEmpty {
                Text("Enter attributes above to preview combinations.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(Array(vm.generatedCombinations.enumerated()), id: \.offset) { _, combo in
                    HStack {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(combo.displayLabel)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("SKU: \(vm.parentSKU)-\(combo.displayLabel.uppercased().replacingOccurrences(of: ", ", with: "-"))")
                                .font(.brandMono(size: 11))
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreSuccess)
                            .imageScale(.small)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Variant: \(combo.displayLabel)")
                }
                Button("Generate \(vm.generatedCombinations.count) Variant SKUs") {
                    Task { await vm.generateVariants() }
                }
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOrange)
                .frame(maxWidth: .infinity, alignment: .center)
                .disabled(vm.isSaving)
                .accessibilityLabel("Generate \(vm.generatedCombinations.count) variant SKUs")
            }
        } header: {
            Text("Generated Combinations (\(vm.generatedCombinations.count))")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class VariantEditorViewModel {
    let parentSKU: String
    var attributeKeys: [String] = ["color"]
    var attributeValues: [String] = [""]
    var generatedCombinations: [InventoryVariant] = []
    var existingVariants: [InventoryVariant] = []
    var isLoading: Bool = false
    var isSaving: Bool = false
    var errorMessage: String?

    var isValid: Bool { !attributeKeys.allSatisfy(\.isEmpty) }

    @ObservationIgnored private let api: APIClient

    init(parentSKU: String, api: APIClient) {
        self.parentSKU = parentSKU
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            existingVariants = try await api.listVariants(parentSKU: parentSKU)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAttributeKey() {
        attributeKeys.append("")
        attributeValues.append("")
    }

    func removeAttributeKey(at idx: Int) {
        guard attributeKeys.indices.contains(idx) else { return }
        attributeKeys.remove(at: idx)
        if attributeValues.indices.contains(idx) {
            attributeValues.remove(at: idx)
        }
        refreshCombinations()
    }

    func setAttributeValues(_ values: String, at idx: Int) {
        guard attributeValues.indices.contains(idx) else { return }
        attributeValues[idx] = values
        refreshCombinations()
    }

    /// Auto-generate cartesian product of all attribute value combinations.
    func refreshCombinations() {
        var axes: [(String, [String])] = []
        for (key, valuesStr) in zip(attributeKeys, attributeValues) {
            let trimmedKey = key.trimmingCharacters(in: .whitespaces)
            guard !trimmedKey.isEmpty else { continue }
            let vals = valuesStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !vals.isEmpty else { continue }
            axes.append((trimmedKey, vals))
        }
        guard !axes.isEmpty else {
            generatedCombinations = []
            return
        }
        let combos = cartesian(axes: axes)
        generatedCombinations = combos.enumerated().map { idx, attributes in
            let label = attributes.sorted(by: { $0.key < $1.key }).map(\.value).joined(separator: "-")
            return InventoryVariant(
                id: Int64(idx),
                parentSKU: parentSKU,
                attributes: attributes,
                sku: "\(parentSKU)-\(label.uppercased())",
                stock: 0,
                retailCents: 0,
                costCents: 0,
                imageURL: nil
            )
        }
    }

    func generateVariants() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        for combo in generatedCombinations {
            let req = CreateVariantRequest(
                parentSKU: parentSKU,
                attributes: combo.attributes,
                sku: combo.sku,
                stock: 0,
                retailCents: 0,
                costCents: 0
            )
            do {
                _ = try await api.createVariant(req)
            } catch {
                errorMessage = "Failed to create \(combo.displayLabel): \(error.localizedDescription)"
                return
            }
        }
        await load()
        generatedCombinations = []
    }

    func save() async {
        await generateVariants()
    }

    // MARK: Helpers

    private func cartesian(axes: [(String, [String])]) -> [[String: String]] {
        axes.reduce([[String: String]()]){ existing, axis -> [[String: String]] in
            existing.flatMap { combo in
                axis.1.map { value in
                    var updated = combo
                    updated[axis.0] = value
                    return updated
                }
            }
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
