#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PricingRuleEditorViewModel

@MainActor
@Observable
public final class PricingRuleEditorViewModel {

    public enum Mode: Equatable { case create; case edit(PricingRule) }

    // MARK: - State

    public private(set) var mode: Mode
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String? = nil

    // MARK: - Form fields

    public var name: String = ""
    public var type: PricingRuleType = .tieredVolume
    public var targetSku: String = ""
    public var targetCategory: String = ""
    public var targetSegment: String = ""
    public var enabled: Bool = true

    // bulkBundle
    public var bundleQuantityInput: String = ""
    public var bundlePriceInput: String = ""     // dollars

    // bogo
    public var triggerQtyInput: String = ""
    public var freeQtyInput: String = ""

    // tieredVolume
    public var tiers: [PricingTier] = []
    public var newTierMinQty: String = ""
    public var newTierMaxQty: String = ""
    public var newTierUnitPrice: String = ""     // dollars

    // segmentPrice
    public var segmentPercentInput: String = ""  // 0–100

    // locationOverride
    public var locationSlugInput: String = ""
    public var locationDiscountPercentInput: String = ""  // 0–100

    // promotionWindow
    public var promotionLabelInput: String = ""
    public var promotionDiscountPercentInput: String = ""  // 0–100
    public var promotionActive: Bool = false

    public var validFrom: Date? = nil
    public var validTo: Date? = nil

    // MARK: - Init

    public init(mode: Mode = .create) {
        self.mode = mode
        if case .edit(let rule) = mode { populate(from: rule) }
    }

    // MARK: - Computed

    public var title: String {
        switch mode { case .create: "New Pricing Rule"; case .edit: "Edit Rule" }
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    // MARK: - Tier helpers

    public func addTier() {
        guard let min = Int(newTierMinQty), min > 0,
              let price = Double(newTierUnitPrice), price > 0 else { return }
        let priceCents = Int((price * 100).rounded())
        let max = Int(newTierMaxQty)
        tiers = (tiers + [PricingTier(minQty: min, maxQty: max, unitPriceCents: priceCents)])
            .sorted { $0.minQty < $1.minQty }
        newTierMinQty = ""
        newTierMaxQty = ""
        newTierUnitPrice = ""
    }

    public func removeTier(at offsets: IndexSet) {
        tiers.remove(atOffsets: offsets)
    }

    // MARK: - Save

    public func save(onSave: @MainActor (PricingRule) -> Void) {
        let ruleId: String
        if case .edit(let existing) = mode { ruleId = existing.id }
        else { ruleId = UUID().uuidString }

        let rule = PricingRule(
            id: ruleId,
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            targetSku: targetSku.isEmpty ? nil : targetSku,
            targetCategory: targetCategory.isEmpty ? nil : targetCategory,
            targetSegment: targetSegment.isEmpty ? nil : targetSegment,
            bundleQuantity: Int(bundleQuantityInput),
            bundlePriceCents: Double(bundlePriceInput).map { Int(($0 * 100).rounded()) },
            triggerQuantity: Int(triggerQtyInput),
            freeQuantity: Int(freeQtyInput),
            tiers: tiers.isEmpty ? nil : tiers,
            segmentDiscountPercent: Double(segmentPercentInput).map { $0 / 100 },
            targetLocationSlug: locationSlugInput.isEmpty ? nil : locationSlugInput,
            locationDiscountPercent: Double(locationDiscountPercentInput).map { $0 / 100 },
            promotionActive: promotionActive,
            promotionLabel: promotionLabelInput.isEmpty ? nil : promotionLabelInput,
            promotionDiscountPercent: Double(promotionDiscountPercentInput).map { $0 / 100 },
            validFrom: validFrom,
            validTo: validTo,
            enabled: enabled
        )
        onSave(rule)
    }

    // MARK: - Private

    private func populate(from rule: PricingRule) {
        name = rule.name
        type = rule.type
        targetSku = rule.targetSku ?? ""
        targetCategory = rule.targetCategory ?? ""
        targetSegment = rule.targetSegment ?? ""
        enabled = rule.enabled
        validFrom = rule.validFrom
        validTo = rule.validTo
        bundleQuantityInput = rule.bundleQuantity.map { String($0) } ?? ""
        bundlePriceInput = rule.bundlePriceCents.map { String(format: "%.2f", Double($0) / 100) } ?? ""
        triggerQtyInput = rule.triggerQuantity.map { String($0) } ?? ""
        freeQtyInput = rule.freeQuantity.map { String($0) } ?? ""
        tiers = rule.tiers ?? []
        segmentPercentInput = rule.segmentDiscountPercent.map { String(format: "%.1f", $0 * 100) } ?? ""
        locationSlugInput = rule.targetLocationSlug ?? ""
        locationDiscountPercentInput = rule.locationDiscountPercent.map { String(format: "%.1f", $0 * 100) } ?? ""
        promotionActive = rule.promotionActive
        promotionLabelInput = rule.promotionLabel ?? ""
        promotionDiscountPercentInput = rule.promotionDiscountPercent.map { String(format: "%.1f", $0 * 100) } ?? ""
    }
}

// MARK: - PricingRuleEditorView

/// Admin editor for `PricingRule` — supports all four types with a
/// type-specific form section.  Designed for both iPhone (sheet) and iPad
/// (popover/inspector panel).
public struct PricingRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PricingRuleEditorViewModel

    public let onSave: @MainActor (PricingRule) -> Void

    public init(mode: PricingRuleEditorViewModel.Mode = .create,
                onSave: @escaping @MainActor (PricingRule) -> Void) {
        _vm = State(initialValue: PricingRuleEditorViewModel(mode: mode))
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    nameSection
                    typeSection
                    targetSection
                    typeSpecificSection
                    validitySection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("pricingRuleEditor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vm.save { rule in
                            onSave(rule)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!vm.canSave)
                    .accessibilityIdentifier("pricingRuleEditor.save")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Rule Name") {
            TextField("e.g. 3-for-$10 Widget Bundle", text: $vm.name)
                .accessibilityLabel("Pricing rule name")
                .accessibilityIdentifier("pricingRuleEditor.name")
            Toggle("Enabled", isOn: $vm.enabled)
                .accessibilityIdentifier("pricingRuleEditor.enabled")
        }
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Rule type", selection: $vm.type) {
                ForEach(PricingRuleType.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("pricingRuleEditor.type")
        }
    }

    private var targetSection: some View {
        Section("Scope") {
            TextField("Target SKU (optional)", text: $vm.targetSku)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("pricingRuleEditor.targetSku")
            TextField("Target category (optional)", text: $vm.targetCategory)
                .accessibilityIdentifier("pricingRuleEditor.targetCategory")
            if vm.type == .segmentPrice {
                TextField("Customer segment", text: $vm.targetSegment)
                    .accessibilityIdentifier("pricingRuleEditor.targetSegment")
            }
        }
    }

    @ViewBuilder
    private var typeSpecificSection: some View {
        switch vm.type {
        case .bulkBundle:
            Section("Bundle") {
                HStack {
                    Text("Bundle quantity")
                    Spacer()
                    TextField("e.g. 3", text: $vm.bundleQuantityInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.bundleQty")
                }
                HStack {
                    Text("Bundle price ($)")
                    Spacer()
                    TextField("e.g. 10.00", text: $vm.bundlePriceInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.bundlePrice")
                }
            }

        case .bogo:
            Section("BOGO") {
                HStack {
                    Text("Buy (trigger qty)")
                    Spacer()
                    TextField("e.g. 1", text: $vm.triggerQtyInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.triggerQty")
                }
                HStack {
                    Text("Get free (qty)")
                    Spacer()
                    TextField("e.g. 1", text: $vm.freeQtyInput)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.freeQty")
                }
            }

        case .tieredVolume:
            Section("Volume Tiers") {
                ForEach(vm.tiers, id: \.self) { tier in
                    HStack {
                        Text("Qty \(tier.minQty)\(tier.maxQty.map { "–\($0)" } ?? "+")")
                            .font(.brandBodyMedium())
                        Spacer()
                        Text(CartMath.formatCents(tier.unitPriceCents) + "/unit")
                            .font(.brandBodyMedium().monospacedDigit())
                    }
                }
                .onDelete { offsets in vm.removeTier(at: offsets) }

                // Add-tier row
                VStack(spacing: BrandSpacing.sm) {
                    HStack(spacing: BrandSpacing.sm) {
                        TextField("Min qty", text: $vm.newTierMinQty)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                            .accessibilityIdentifier("pricingRuleEditor.tierMinQty")
                        TextField("Max qty", text: $vm.newTierMaxQty)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                            .accessibilityIdentifier("pricingRuleEditor.tierMaxQty")
                        TextField("$/unit", text: $vm.newTierUnitPrice)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                            .accessibilityIdentifier("pricingRuleEditor.tierUnitPrice")
                        Button("Add") { vm.addTier() }
                            .accessibilityIdentifier("pricingRuleEditor.addTier")
                    }
                }
            }

        case .segmentPrice:
            Section("Segment Discount") {
                HStack {
                    Text("Discount %")
                    Spacer()
                    TextField("e.g. 15", text: $vm.segmentPercentInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.segmentPercent")
                    Text("%")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

        case .locationOverride:
            Section("Location Override") {
                TextField("Location slug (e.g. metro-nyc)", text: $vm.locationSlugInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("pricingRuleEditor.locationSlug")
                HStack {
                    Text("Discount %")
                    Spacer()
                    TextField("e.g. 5", text: $vm.locationDiscountPercentInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.locationDiscountPercent")
                    Text("%")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

        case .promotionWindow:
            Section("Promotion Window") {
                TextField("Flash sale label (optional)", text: $vm.promotionLabelInput)
                    .accessibilityIdentifier("pricingRuleEditor.promotionLabel")
                HStack {
                    Text("Discount %")
                    Spacer()
                    TextField("e.g. 20", text: $vm.promotionDiscountPercentInput)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .accessibilityIdentifier("pricingRuleEditor.promotionDiscountPercent")
                    Text("%")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Toggle("Promotion active", isOn: $vm.promotionActive)
                    .accessibilityIdentifier("pricingRuleEditor.promotionActive")
            }
        }
    }

    private var validitySection: some View {
        Section("Validity") {
            DatePicker("Active from",
                       selection: Binding(get: { vm.validFrom ?? .now }, set: { vm.validFrom = $0 }),
                       displayedComponents: .date)
                .accessibilityIdentifier("pricingRuleEditor.validFrom")
            DatePicker("Active until",
                       selection: Binding(get: { vm.validTo ?? .now }, set: { vm.validTo = $0 }),
                       displayedComponents: .date)
                .accessibilityIdentifier("pricingRuleEditor.validTo")
        }
    }
}

// (PricingRuleType.displayName lives in PricingRulesListView.swift)
private extension PricingRuleType {
    var legacyEditorLabel: String {
        switch self {
        case .bulkBundle:       return "Bulk Bundle (N for $X)"
        case .bogo:             return "BOGO (Buy X Get Y Free)"
        case .tieredVolume:     return "Tiered Volume Pricing"
        case .segmentPrice:     return "Customer Segment Price"
        case .locationOverride: return "Location Override"
        case .promotionWindow:  return "Promotion Window"
        }
    }
}
#endif
