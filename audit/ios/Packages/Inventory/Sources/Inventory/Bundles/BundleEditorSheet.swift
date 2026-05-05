#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.11 Bundle Editor Sheet

/// Admin form for creating/editing a bundle: name, SKU, price, and component picker.
public struct BundleEditorSheet: View {
    @State private var vm: BundleEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bundle: InventoryBundle? = nil, api: APIClient) {
        _vm = State(wrappedValue: BundleEditorViewModel(bundle: bundle, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    metaSection
                    componentsSection
                    pricingSection
                    warningsSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.isEditing ? "Edit Bundle" : "New Bundle")
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
        }
        .presentationDetents([.large])
        .brandGlass()
    }

    // MARK: Sections

    private var metaSection: some View {
        Section("Bundle Info") {
            LabeledContent("Bundle Name") {
                TextField("Screen Repair Kit", text: $vm.name)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
            }
            LabeledContent("Bundle SKU") {
                TextField("KIT-SCREEN-001", text: $vm.sku)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .font(.brandMono(size: 14))
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var componentsSection: some View {
        Section {
            ForEach(vm.draftComponents.indices, id: \.self) { idx in
                componentRow(idx: idx)
            }
            Button {
                withAnimation(reduceMotion ? nil : .spring()) {
                    vm.addComponent()
                }
            } label: {
                Label("Add Component SKU", systemImage: "plus.circle")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Add bundle component")
        } header: {
            Text("Components (\(vm.draftComponents.count))")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func componentRow(idx: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField("SKU", text: $vm.draftComponents[idx].sku)
                .textInputAutocapitalization(.characters)
                .font(.brandMono(size: 13))
                .frame(minWidth: 80)
            Spacer()
            Text("Qty")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            TextField("1", text: $vm.draftComponents[idx].qtyText)
                .keyboardType(.numberPad)
                .font(.brandBodyMedium())
                .frame(width: 50)
                .multilineTextAlignment(.trailing)
            Button {
                withAnimation(reduceMotion ? nil : .spring()) {
                    vm.removeComponent(at: idx)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.bizarreError)
            }
            .accessibilityLabel("Remove component \(vm.draftComponents[safe: idx]?.sku ?? "")")
        }
    }

    private var pricingSection: some View {
        Section("Pricing (cents)") {
            LabeledContent("Bundle Price") {
                TextField("0", text: $vm.bundlePriceCentsText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
            }
            LabeledContent("Individual Sum") {
                TextField("0", text: $vm.individualPriceSumText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
            }
            if let saving = vm.savingsPreview {
                HStack {
                    Image(systemName: "tag.fill").foregroundStyle(.bizarreSuccess)
                    Text("Customer saves \(saving)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    @ViewBuilder
    private var warningsSection: some View {
        let warnings = vm.warnings
        if !warnings.isEmpty {
            Section("Warnings") {
                ForEach(warnings.indices, id: \.self) { idx in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreWarning)
                        Text(warnings[idx].reason)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
            }
            .listRowBackground(Color.bizarreSurface1)
        }
    }
}

// MARK: - Draft Component

public struct DraftBundleComponent: Identifiable, Sendable {
    public let id: UUID = UUID()
    public var sku: String = ""
    public var qtyText: String = "1"

    public var qty: Int { Int(qtyText) ?? 1 }

    public init(sku: String = "", qtyText: String = "1") {
        self.sku = sku
        self.qtyText = qtyText
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class BundleEditorViewModel {
    var name: String = ""
    var sku: String = ""
    var draftComponents: [DraftBundleComponent] = [DraftBundleComponent()]
    var bundlePriceCentsText: String = "0"
    var individualPriceSumText: String = "0"
    var isSaving: Bool = false
    var errorMessage: String?

    let isEditing: Bool
    @ObservationIgnored private let originalBundle: InventoryBundle?
    @ObservationIgnored private let api: APIClient

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !sku.trimmingCharacters(in: .whitespaces).isEmpty
        && !draftComponents.isEmpty
    }

    var warnings: [BundleUnpacker.MissingComponentWarning] {
        let tempBundle = buildBundle(id: 0)
        return BundleUnpacker.validate(bundle: tempBundle)
    }

    var savingsPreview: String? {
        let price = Int(bundlePriceCentsText) ?? 0
        let sum = Int(individualPriceSumText) ?? 0
        guard sum > price, price > 0 else { return nil }
        let saving = sum - price
        return String(format: "$%.2f", Double(saving) / 100.0)
    }

    init(bundle: InventoryBundle? = nil, api: APIClient) {
        self.api = api
        self.originalBundle = bundle
        self.isEditing = bundle != nil
        if let b = bundle {
            self.name = b.name
            self.sku = b.sku
            self.bundlePriceCentsText = String(b.bundlePriceCents)
            self.individualPriceSumText = String(b.individualPriceSum)
            self.draftComponents = b.components.map { c in
                DraftBundleComponent(sku: c.componentSKU, qtyText: String(c.qty))
            }
        }
    }

    func addComponent() {
        draftComponents.append(DraftBundleComponent())
    }

    func removeComponent(at idx: Int) {
        guard draftComponents.indices.contains(idx) else { return }
        draftComponents.remove(at: idx)
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        // Persist via Networking — endpoints wired below
        // For now the editor builds the domain model; persistence via BundleEndpoints
    }

    func buildBundle(id: Int64) -> InventoryBundle {
        InventoryBundle(
            id: id,
            sku: sku.trimmingCharacters(in: .whitespaces),
            name: name.trimmingCharacters(in: .whitespaces),
            components: draftComponents.map { BundleComponent(componentSKU: $0.sku, qty: $0.qty) },
            bundlePriceCents: Int(bundlePriceCentsText) ?? 0,
            individualPriceSum: Int(individualPriceSumText) ?? 0
        )
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Warning color placeholder

private extension Color {
    static var bizarreWarning: Color { .orange }
}
#endif
