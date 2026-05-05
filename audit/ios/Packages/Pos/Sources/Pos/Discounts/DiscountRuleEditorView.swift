#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - DiscountRuleEditorViewModel

@MainActor
@Observable
public final class DiscountRuleEditorViewModel {

    // MARK: - State

    public enum Mode: Equatable { case create; case edit(DiscountRule) }

    public private(set) var mode: Mode
    public private(set) var isSaving: Bool = false
    public var errorMessage: String? = nil
    public private(set) var savedRule: DiscountRule? = nil

    // MARK: - Form fields

    public var name: String = ""
    public var scope: DiscountScope = .whole
    public var matcher: String = ""
    public var usePercent: Bool = true
    public var discountPercentInput: String = ""
    public var discountFlatInput: String = ""
    public var minQtyInput: String = ""
    public var minCartTotalInput: String = ""
    public var validFrom: Date? = nil
    public var validTo: Date? = nil
    public var maxUsesInput: String = ""
    public var stackable: Bool = true
    public var managerApprovalRequired: Bool = false

    // MARK: - Init

    public init(mode: Mode = .create) {
        self.mode = mode
        if case .edit(let rule) = mode { populate(from: rule) }
    }

    // MARK: - Computed

    public var title: String {
        switch mode { case .create: "New Discount Rule"; case .edit: "Edit Rule" }
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedDiscount != nil
            && !isSaving
    }

    private var parsedDiscount: (percent: Double?, flat: Int?)? {
        if usePercent {
            guard let v = Double(discountPercentInput), v > 0, v <= 100 else { return nil }
            return (v / 100, nil)
        } else {
            guard let v = Int(discountFlatInput), v > 0 else { return nil }
            return (nil, v)
        }
    }

    // MARK: - Actions

    /// Synchronously builds the rule and calls `onSave`.
    public func save(onSave: @MainActor (DiscountRule) -> Void) {
        guard let discount = parsedDiscount else {
            errorMessage = "Enter a valid discount value."
            return
        }
        let ruleId: String
        if case .edit(let existing) = mode { ruleId = existing.id }
        else { ruleId = UUID().uuidString }

        let rule = DiscountRule(
            id: ruleId,
            name: name.trimmingCharacters(in: .whitespaces),
            scope: scope,
            matcher: matcher,
            discountPercent: discount.percent,
            discountFlatCents: discount.flat,
            minQuantity: Int(minQtyInput),
            minCartTotalCents: Int(minCartTotalInput).map { $0 * 100 }, // input is dollars
            validFrom: validFrom,
            validTo: validTo,
            maxUsesPerCustomer: Int(maxUsesInput),
            stackable: stackable,
            managerApprovalRequired: managerApprovalRequired
        )
        savedRule = rule
        onSave(rule)
    }

    // MARK: - Private

    private func populate(from rule: DiscountRule) {
        name = rule.name
        scope = rule.scope
        matcher = rule.matcher
        stackable = rule.stackable
        managerApprovalRequired = rule.managerApprovalRequired
        validFrom = rule.validFrom
        validTo = rule.validTo
        if let pct = rule.discountPercent {
            usePercent = true
            discountPercentInput = String(format: "%.1f", pct * 100)
        } else if let flat = rule.discountFlatCents {
            usePercent = false
            discountFlatInput = String(flat)
        }
        minQtyInput = rule.minQuantity.map { String($0) } ?? ""
        minCartTotalInput = rule.minCartTotalCents.map { String($0 / 100) } ?? ""
        maxUsesInput = rule.maxUsesPerCustomer.map { String($0) } ?? ""
    }
}

// MARK: - DiscountRuleEditorView

/// Admin UI to create or edit a `DiscountRule`.
/// Presented from `DiscountRuleListView` or the Settings → Pricing rules page.
public struct DiscountRuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: DiscountRuleEditorViewModel

    public let onSave: @MainActor (DiscountRule) -> Void

    public init(mode: DiscountRuleEditorViewModel.Mode = .create,
                onSave: @escaping @MainActor (DiscountRule) -> Void) {
        _vm = State(initialValue: DiscountRuleEditorViewModel(mode: mode))
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    nameSection
                    scopeSection
                    discountSection
                    conditionsSection
                    behaviorSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("discountRuleEditor.cancel")
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
                    .accessibilityIdentifier("discountRuleEditor.save")
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Form sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Rule name", text: $vm.name)
                .accessibilityLabel("Discount rule name")
                .accessibilityIdentifier("discountRuleEditor.name")
        }
    }

    private var scopeSection: some View {
        Section("Scope") {
            Picker("Scope", selection: $vm.scope) {
                ForEach(DiscountScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue.capitalized).tag(scope)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("discountRuleEditor.scope")

            if vm.scope == .category || vm.scope == .sku {
                TextField(vm.scope == .category ? "Category name" : "SKU regex", text: $vm.matcher)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(vm.scope == .category ? "Category matcher" : "SKU regex")
                    .accessibilityIdentifier("discountRuleEditor.matcher")
            }
        }
    }

    private var discountSection: some View {
        Section("Discount") {
            Toggle("Use percentage", isOn: $vm.usePercent)
                .accessibilityIdentifier("discountRuleEditor.usePercent")
            if vm.usePercent {
                HStack {
                    TextField("e.g. 10", text: $vm.discountPercentInput)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Discount percent")
                        .accessibilityIdentifier("discountRuleEditor.discountPercent")
                    Text("%")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                HStack {
                    Text("$")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("Amount in cents", text: $vm.discountFlatInput)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Discount flat cents")
                        .accessibilityIdentifier("discountRuleEditor.discountFlat")
                }
            }
        }
    }

    private var conditionsSection: some View {
        Section("Conditions") {
            HStack {
                Text("Min quantity")
                Spacer()
                TextField("None", text: $vm.minQtyInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Minimum quantity")
                    .accessibilityIdentifier("discountRuleEditor.minQty")
            }
            HStack {
                Text("Min cart total ($)")
                Spacer()
                TextField("None", text: $vm.minCartTotalInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Minimum cart total in dollars")
                    .accessibilityIdentifier("discountRuleEditor.minCartTotal")
            }
            HStack {
                Text("Max uses / customer")
                Spacer()
                TextField("Unlimited", text: $vm.maxUsesInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityLabel("Max uses per customer")
                    .accessibilityIdentifier("discountRuleEditor.maxUses")
            }
            DatePicker("Valid from",
                       selection: Binding(get: { vm.validFrom ?? .now },
                                          set: { vm.validFrom = $0 }),
                       displayedComponents: .date)
                .accessibilityIdentifier("discountRuleEditor.validFrom")
            DatePicker("Valid to",
                       selection: Binding(get: { vm.validTo ?? .now },
                                          set: { vm.validTo = $0 }),
                       displayedComponents: .date)
                .accessibilityIdentifier("discountRuleEditor.validTo")
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Stackable with other discounts", isOn: $vm.stackable)
                .accessibilityIdentifier("discountRuleEditor.stackable")
            Toggle("Manager approval required", isOn: $vm.managerApprovalRequired)
                .accessibilityIdentifier("discountRuleEditor.managerApproval")
        }
    }
}
#endif
