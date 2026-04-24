import SwiftUI
import DesignSystem
import Networking

// MARK: - LoyaltyPlanSettingsViewModel

@MainActor
@Observable
public final class LoyaltyPlanSettingsViewModel {

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var plans: [MembershipPlan] = []
    public private(set) var rule: LoyaltyRule = .default

    // Edit state
    public var editingPlan: MembershipPlan? = nil
    public var showPlanEditor: Bool = false
    public var showRuleEditor: Bool = false
    public var isSaving: Bool = false
    public var errorMessage: String = ""
    public var showError: Bool = false

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func load() async {
        state = .loading
        do {
            // Server routes:
            //   GET /api/v1/membership/tiers  → active tier list
            //   GET /api/v1/settings/loyalty/rule  → earn rule (if endpoint exists)
            async let tiersTask = api.listMembershipTiers()
            async let ruleTask  = api.get("/settings/loyalty/rule", as: LoyaltyRule.self)
            let (tiers, fetchedRule) = try await (tiersTask, ruleTask)
            // Map MembershipTierDTO → MembershipPlan for the shared form
            plans = tiers.map { tier in
                MembershipPlan(
                    id: String(tier.id),
                    name: tier.name,
                    pricePerPeriodCents: Int(tier.monthlyPrice * 100),
                    periodDays: 30,
                    perks: tier.discountPct > 0 ? [.percentageDiscount(tier.discountPct)] : [],
                    signupBonusPoints: 0
                )
            }
            rule = fetchedRule
            state = .loaded
        } catch let t as APITransportError {
            if case .httpStatus(let c, _) = t, c == 404 || c == 402 || c == 501 {
                // Feature not enabled or endpoint not yet live — show stubs.
                plans = LoyaltyPlanSettingsViewModel.stubPlans
                rule = .default
                state = .loaded
            } else {
                state = .failed(t.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - CRUD on plans

    public func startCreate() {
        editingPlan = nil
        showPlanEditor = true
    }

    public func startEdit(_ plan: MembershipPlan) {
        editingPlan = plan
        showPlanEditor = true
    }

    public func delete(_ plan: MembershipPlan) async {
        isSaving = true
        defer { isSaving = false }
        do {
            // Server route: DELETE /api/v1/membership/tiers/:id (soft-delete)
            try await api.delete("/membership/tiers/\(plan.id)")
            plans.removeAll { $0.id == plan.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    public func savePlan(_ plan: MembershipPlan) async {
        isSaving = true
        defer { isSaving = false }
        do {
            if plans.contains(where: { $0.id == plan.id }) {
                // Server route: PUT /api/v1/membership/tiers/:id
                let dto = try await api.put(
                    "/membership/tiers/\(plan.id)",
                    body: MembershipPlanRequest(plan),
                    as: MembershipTierDTO.self
                )
                let updated = MembershipPlan(
                    id: String(dto.id),
                    name: dto.name,
                    pricePerPeriodCents: Int(dto.monthlyPrice * 100),
                    periodDays: 30,
                    perks: dto.discountPct > 0 ? [.percentageDiscount(dto.discountPct)] : [],
                    signupBonusPoints: 0
                )
                plans = plans.map { $0.id == plan.id ? updated : $0 }
            } else {
                // Server route: POST /api/v1/membership/tiers
                let dto = try await api.post(
                    "/membership/tiers",
                    body: MembershipPlanRequest(plan),
                    as: MembershipTierDTO.self
                )
                let created = MembershipPlan(
                    id: String(dto.id),
                    name: dto.name,
                    pricePerPeriodCents: Int(dto.monthlyPrice * 100),
                    periodDays: 30,
                    perks: dto.discountPct > 0 ? [.percentageDiscount(dto.discountPct)] : [],
                    signupBonusPoints: 0
                )
                plans.append(created)
            }
            showPlanEditor = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    public func saveRule(_ newRule: LoyaltyRule) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await api.put(
                "/settings/loyalty/rule",
                body: newRule,
                as: LoyaltyRule.self
            )
            rule = saved
            showRuleEditor = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Stub data

    private static let stubPlans: [MembershipPlan] = [
        MembershipPlan(
            id: "plan-basic",
            name: "Basic Monthly",
            pricePerPeriodCents: 999,
            periodDays: 30,
            perks: [.percentageDiscount(5)],
            signupBonusPoints: 50
        ),
        MembershipPlan(
            id: "plan-gold",
            name: "Gold Monthly",
            pricePerPeriodCents: 1999,
            periodDays: 30,
            perks: [
                .percentageDiscount(10),
                .freeService(serviceId: "battery-test", displayName: "Battery Test")
            ],
            signupBonusPoints: 200
        ),
        MembershipPlan(
            id: "plan-annual",
            name: "Annual Premium",
            pricePerPeriodCents: 14_999,
            periodDays: 365,
            perks: [
                .percentageDiscount(15),
                .freeService(serviceId: "diagnostics", displayName: "Diagnostics"),
                .exclusiveAccess("VIP Customer Support Line")
            ],
            signupBonusPoints: 1_000
        )
    ]
}

// MARK: - LoyaltyPlanSettingsView

/// §38 — Admin settings: list of membership plans + loyalty rule editor.
///
/// iPhone: `NavigationStack` + `List` with row-tap → edit sheet.
/// iPad: `NavigationSplitView` with plan list on left, editor on right.
public struct LoyaltyPlanSettingsView: View {

    @State private var vm: LoyaltyPlanSettingsViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(api: any APIClient) {
        _vm = State(wrappedValue: LoyaltyPlanSettingsViewModel(api: api))
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .navigationTitle("Loyalty & Memberships")
        .task { await vm.load() }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage)
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            stateContent
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .toolbar { addPlanButton; ruleEditorButton }
        .sheet(isPresented: $vm.showPlanEditor) {
            PlanEditorSheet(existing: vm.editingPlan) { plan in
                Task { await vm.savePlan(plan) }
            }
        }
        .sheet(isPresented: $vm.showRuleEditor) {
            RuleEditorSheet(rule: vm.rule) { rule in
                Task { await vm.saveRule(rule) }
            }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            List {
                stateContent
            }
            .listStyle(.sidebar)
            .frame(maxWidth: 340)
            .toolbar { addPlanButton; ruleEditorButton }

            Divider()

            // Detail panel — show rule editor by default
            if vm.showRuleEditor {
                RuleEditorSheet(rule: vm.rule) { rule in
                    Task { await vm.saveRule(rule) }
                }
            } else if vm.showPlanEditor {
                PlanEditorSheet(existing: vm.editingPlan) { plan in
                    Task { await vm.savePlan(plan) }
                }
            } else {
                ContentUnavailableView(
                    "Select an item",
                    systemImage: "sidebar.left",
                    description: Text("Choose a plan to edit, or tap + to create one.")
                )
            }
        }
    }

    // MARK: - State content (shared)

    @ViewBuilder
    private var stateContent: some View {
        switch vm.state {
        case .loading:
            Section {
                ProgressView("Loading…").accessibilityLabel("Loading loyalty settings")
            }
        case .failed(let msg):
            Section {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.bizarreError)
            }
        case .loaded:
            ruleSection
            plansSection
        }
    }

    private var ruleSection: some View {
        Section("Earn Rules") {
            LabeledContent("Points per $1") {
                Text("\(vm.rule.pointsPerDollar)")
                    .foregroundStyle(.bizarreOrange)
            }
            LabeledContent("Tuesday multiplier") {
                Text("\(vm.rule.tuesdayMultiplier)×")
                    .foregroundStyle(.bizarreOrange)
            }
            LabeledContent("Birthday multiplier") {
                Text("\(vm.rule.birthdayMultiplier)×")
                    .foregroundStyle(.bizarreOrange)
            }
            LabeledContent("Sign-up bonus") {
                Text("\(vm.rule.signupBonusPoints) pts")
                    .foregroundStyle(.bizarreOrange)
            }
            LabeledContent("Expiry") {
                Text(vm.rule.expiryDays > 0 ? "\(vm.rule.expiryDays) days" : "Never")
                    .foregroundStyle(vm.rule.expiryDays > 0 ? .bizarreOnSurface : .bizarreOnSurfaceMuted)
            }
            Button("Edit Rules") { vm.showRuleEditor = true }
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Edit loyalty earn rules")
        }
    }

    private var plansSection: some View {
        Section("Membership Plans") {
            if vm.plans.isEmpty {
                Text("No plans configured yet.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.brandBodyMedium())
            }
            ForEach(vm.plans) { plan in
                PlanSummaryRow(plan: plan)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.startEdit(plan) }
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    .accessibilityAddTraits(.isButton)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(plan) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button { vm.startEdit(plan) } label: {
                            Label("Edit Plan", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) { Task { await vm.delete(plan) } } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    }
            }
        }
    }

    // MARK: - Toolbar items

    @ToolbarContentBuilder
    private var addPlanButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { vm.startCreate() } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add membership plan")
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    @ToolbarContentBuilder
    private var ruleEditorButton: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button("Edit Rules") { vm.showRuleEditor = true }
                .accessibilityLabel("Edit loyalty earn rules")
        }
    }
}

// MARK: - PlanSummaryRow

private struct PlanSummaryRow: View {
    let plan: MembershipPlan

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(plan.name)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(plan.formattedPrice) / \(plan.periodDays)d · \(plan.perks.count) perks")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

// MARK: - PlanEditorSheet

struct PlanEditorSheet: View {
    let existing: MembershipPlan?
    let onSave: (MembershipPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var priceStr: String
    @State private var periodStr: String
    @State private var signupBonusStr: String
    @State private var percentageDiscountStr: String

    init(existing: MembershipPlan?, onSave: @escaping (MembershipPlan) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _priceStr = State(initialValue: existing.map { String($0.pricePerPeriodCents) } ?? "")
        _periodStr = State(initialValue: existing.map { String($0.periodDays) } ?? "30")
        _signupBonusStr = State(initialValue: existing.map { String($0.signupBonusPoints) } ?? "0")
        // Pre-populate first percentage perk if present
        if let pct = existing?.perks.compactMap({ if case .percentageDiscount(let v) = $0 { return v } else { return nil } }).first {
            _percentageDiscountStr = State(initialValue: String(pct))
        } else {
            _percentageDiscountStr = State(initialValue: "0")
        }
    }

    private var isValid: Bool {
        !name.isEmpty
        && Int(priceStr) != nil
        && Int(periodStr) != nil
        && Int(signupBonusStr) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan Details") {
                    LabeledContent("Name") {
                        TextField("e.g. Gold Monthly", text: $name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Plan name")
                    }
                    LabeledContent("Price (cents)") {
                        TextField("e.g. 999", text: $priceStr)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Price per period in cents")
#if canImport(UIKit)
                            .keyboardType(.numberPad)
#endif
                    }
                    LabeledContent("Period (days)") {
                        TextField("30", text: $periodStr)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Billing period in days")
#if canImport(UIKit)
                            .keyboardType(.numberPad)
#endif
                    }
                }
                Section("Perks") {
                    LabeledContent("% Discount") {
                        TextField("0", text: $percentageDiscountStr)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Percentage discount for members")
#if canImport(UIKit)
                            .keyboardType(.numberPad)
#endif
                    }
                    LabeledContent("Sign-up Bonus (pts)") {
                        TextField("0", text: $signupBonusStr)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Sign-up bonus points")
#if canImport(UIKit)
                            .keyboardType(.numberPad)
#endif
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Plan" : "Edit Plan")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .accessibilityLabel("Save membership plan")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard
            let price = Int(priceStr),
            let period = Int(periodStr),
            let bonus = Int(signupBonusStr)
        else { return }

        var perks: [MembershipPerk] = []
        if let pct = Int(percentageDiscountStr), pct > 0 {
            perks.append(.percentageDiscount(pct))
        }

        let plan = MembershipPlan(
            id: existing?.id ?? UUID().uuidString,
            name: name,
            pricePerPeriodCents: price,
            periodDays: period,
            perks: perks,
            signupBonusPoints: bonus
        )
        onSave(plan)
        dismiss()
    }
}

// MARK: - RuleEditorSheet

struct RuleEditorSheet: View {
    let rule: LoyaltyRule
    let onSave: (LoyaltyRule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pointsPerDollarStr: String
    @State private var tuesdayMultStr: String
    @State private var birthdayMultStr: String
    @State private var signupBonusStr: String
    @State private var expiryDaysStr: String

    init(rule: LoyaltyRule, onSave: @escaping (LoyaltyRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _pointsPerDollarStr = State(initialValue: String(rule.pointsPerDollar))
        _tuesdayMultStr     = State(initialValue: String(rule.tuesdayMultiplier))
        _birthdayMultStr    = State(initialValue: String(rule.birthdayMultiplier))
        _signupBonusStr     = State(initialValue: String(rule.signupBonusPoints))
        _expiryDaysStr      = State(initialValue: String(rule.expiryDays))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Earn") {
                    ruleField("Points per $1", text: $pointsPerDollarStr, a11yLabel: "Points earned per dollar spent")
                    ruleField("Tuesday multiplier", text: $tuesdayMultStr, a11yLabel: "Tuesday points multiplier")
                    ruleField("Birthday multiplier", text: $birthdayMultStr, a11yLabel: "Birthday points multiplier")
                    ruleField("Sign-up bonus pts", text: $signupBonusStr, a11yLabel: "Sign-up bonus points")
                }
                Section("Expiry") {
                    ruleField("Expiry days (0 = never)", text: $expiryDaysStr, a11yLabel: "Points expiry in days, 0 for never")
                }
            }
            .navigationTitle("Loyalty Rules")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityLabel("Save loyalty earn rules")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func ruleField(_ label: String, text: Binding<String>, a11yLabel: String) -> some View {
        LabeledContent(label) {
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(a11yLabel)
#if canImport(UIKit)
                .keyboardType(.numberPad)
#endif
        }
    }

    private func save() {
        let newRule = LoyaltyRule(
            pointsPerDollar: Int(pointsPerDollarStr) ?? rule.pointsPerDollar,
            tuesdayMultiplier: Int(tuesdayMultStr) ?? rule.tuesdayMultiplier,
            signupBonusPoints: Int(signupBonusStr) ?? rule.signupBonusPoints,
            birthdayMultiplier: Int(birthdayMultStr) ?? rule.birthdayMultiplier,
            expiryDays: Int(expiryDaysStr) ?? rule.expiryDays
        )
        onSave(newRule)
        dismiss()
    }
}

// MARK: - Request DTO

private struct MembershipPlanRequest: Encodable, Sendable {
    let id: String
    let name: String
    let pricePerPeriodCents: Int
    let periodDays: Int
    let perks: [MembershipPerk]
    let signupBonusPoints: Int

    init(_ plan: MembershipPlan) {
        self.id = plan.id
        self.name = plan.name
        self.pricePerPeriodCents = plan.pricePerPeriodCents
        self.periodDays = plan.periodDays
        self.perks = plan.perks
        self.signupBonusPoints = plan.signupBonusPoints
    }

    enum CodingKeys: String, CodingKey {
        case id, name, perks
        case pricePerPeriodCents = "price_per_period_cents"
        case periodDays          = "period_days"
        case signupBonusPoints   = "signup_bonus_points"
    }
}
