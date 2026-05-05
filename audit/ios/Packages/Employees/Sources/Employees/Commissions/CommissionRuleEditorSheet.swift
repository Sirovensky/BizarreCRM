import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - CommissionRuleEditorViewModel

@MainActor
@Observable
public final class CommissionRuleEditorViewModel {
    public var role: String = ""
    public var serviceCategory: String = ""
    public var productCategory: String = ""
    public var ruleType: CommissionRuleType = .percentage
    public var value: Double = 10.0
    public var capAmount: String = ""   // empty = no cap
    public var minTicketValue: String = ""
    public var tenureMonths: String = ""

    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var savedRule: CommissionRule?

    public var isValid: Bool { value > 0 }

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let existingId: Int64?
    @ObservationIgnored private let onSave: (CommissionRule) -> Void

    public init(rule: CommissionRule? = nil, api: APIClient, onSave: @escaping (CommissionRule) -> Void) {
        self.api = api
        self.existingId = rule?.id
        self.onSave = onSave
        if let r = rule {
            role = r.role ?? ""
            serviceCategory = r.serviceCategory ?? ""
            productCategory = r.productCategory ?? ""
            ruleType = r.ruleType
            value = r.value
            capAmount = r.capAmount.map { String($0) } ?? ""
            minTicketValue = r.condition?.minTicketValue.map { String($0) } ?? ""
            tenureMonths = r.condition?.tenureMonths.map { String($0) } ?? ""
        }
    }

    public func save() async {
        guard isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let cap = Double(capAmount)
        let req = CreateCommissionRuleRequest(
            role: role.isEmpty ? nil : role,
            serviceCategory: serviceCategory.isEmpty ? nil : serviceCategory,
            productCategory: productCategory.isEmpty ? nil : productCategory,
            ruleType: ruleType,
            value: value,
            capAmount: cap
        )
        do {
            let saved: CommissionRule
            if let id = existingId {
                saved = try await api.updateCommissionRule(
                    id: id,
                    UpdateCommissionRuleRequest(
                        role: req.role,
                        serviceCategory: req.serviceCategory,
                        productCategory: req.productCategory,
                        ruleType: req.ruleType,
                        value: req.value,
                        capAmount: req.capAmount
                    )
                )
            } else {
                saved = try await api.createCommissionRule(req)
            }
            savedRule = saved
            onSave(saved)
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.errorDescription
            AppLog.ui.error("Commission rule save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - CommissionRuleEditorSheet

public struct CommissionRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CommissionRuleEditorViewModel

    public init(
        rule: CommissionRule? = nil,
        api: APIClient,
        onSave: @escaping (CommissionRule) -> Void
    ) {
        _vm = State(wrappedValue: CommissionRuleEditorViewModel(rule: rule, api: api, onSave: onSave))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    scopeSection
                    ruleSection
                    conditionsSection
                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError)
                                .accessibilityLabel("Error: \(err)")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.isEditing ? "Edit Rule" : "New Rule")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") { Task { await vm.save() } }
                        .disabled(!vm.isValid || vm.isSaving)
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: vm.savedRule) { _, r in if r != nil { dismiss() } }
    }

    // MARK: - Sections

    private var scopeSection: some View {
        Section("Scope (leave blank for all)") {
            TextField("Role (e.g. technician)", text: $vm.role)
                .accessibilityLabel("Role scope")
            TextField("Service category", text: $vm.serviceCategory)
                .accessibilityLabel("Service category scope")
            TextField("Product category", text: $vm.productCategory)
                .accessibilityLabel("Product category scope")
        }
    }

    private var ruleSection: some View {
        Section("Commission") {
            Picker("Type", selection: $vm.ruleType) {
                Text("Percentage").tag(CommissionRuleType.percentage)
                Text("Flat amount").tag(CommissionRuleType.flat)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Commission type")

            HStack {
                Text(vm.ruleType == .percentage ? "Percent" : "Amount ($)")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField(vm.ruleType == .percentage ? "10" : "25.00", value: $vm.value, format: .number)
#if !os(macOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
#endif
                    .frame(width: 80)
                    .accessibilityLabel(vm.ruleType == .percentage ? "Commission percentage" : "Commission flat amount")
            }

            HStack {
                Text("Cap (optional)")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("No cap", text: $vm.capAmount)
#if !os(macOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
#endif
                    .frame(width: 100)
                    .accessibilityLabel("Maximum commission cap")
            }
        }
    }

    private var conditionsSection: some View {
        Section("Conditions (optional)") {
            HStack {
                Text("Min ticket value ($)")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("Any", text: $vm.minTicketValue)
#if !os(macOS)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
#endif
                    .frame(width: 80)
                    .accessibilityLabel("Minimum ticket value")
            }
            HStack {
                Text("Min tenure (months)")
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                TextField("Any", text: $vm.tenureMonths)
#if !os(macOS)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
#endif
                    .frame(width: 80)
                    .accessibilityLabel("Minimum tenure in months")
            }
        }
    }
}

extension CommissionRuleEditorViewModel {
    var isEditing: Bool { existingId != nil }
}
