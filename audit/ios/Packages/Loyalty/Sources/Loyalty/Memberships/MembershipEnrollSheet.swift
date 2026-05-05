import SwiftUI
import DesignSystem
import Networking

// MARK: - MembershipEnrollViewModel

@MainActor
@Observable
public final class MembershipEnrollViewModel {

    public enum State: Equatable, Sendable {
        case idle
        case loadingPlans
        case plansLoaded
        case enrolling
        case enrolled(Membership)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var plans: [MembershipPlan] = []
    public var selectedPlanId: String? = nil

    private let manager: MembershipSubscriptionManager
    private let api: any APIClient
    private let customerId: String

    public init(api: any APIClient, manager: MembershipSubscriptionManager, customerId: String) {
        self.api = api
        self.manager = manager
        self.customerId = customerId
    }

    public var selectedPlan: MembershipPlan? {
        plans.first { $0.id == selectedPlanId }
    }

    public var canEnroll: Bool {
        selectedPlanId != nil && state != .enrolling
    }

    public func loadPlans() async {
        state = .loadingPlans
        do {
            // Server route: GET /api/v1/membership/tiers
            let tiers = try await api.listMembershipTiers()
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
            state = .plansLoaded
            if selectedPlanId == nil { selectedPlanId = plans.first?.id }
        } catch let t as APITransportError {
            if case .httpStatus(let c, _) = t, c == 404 || c == 402 || c == 501 {
                // Feature not enabled or endpoint not yet live — show demo plans.
                plans = [
                    MembershipPlan(
                        id: "demo-basic",
                        name: "Basic Monthly",
                        pricePerPeriodCents: 999,
                        periodDays: 30,
                        perks: [.percentageDiscount(5)],
                        signupBonusPoints: 50
                    ),
                    MembershipPlan(
                        id: "demo-gold",
                        name: "Gold Monthly",
                        pricePerPeriodCents: 1999,
                        periodDays: 30,
                        perks: [.percentageDiscount(10), .freeService(serviceId: "battery-test", displayName: "Battery Test")],
                        signupBonusPoints: 200
                    )
                ]
                selectedPlanId = plans.first?.id
                state = .plansLoaded
            } else {
                state = .failed(t.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    public func enroll() async -> Membership? {
        guard let plan = selectedPlan else { return nil }
        state = .enrolling
        let membership = await manager.enroll(customerId: customerId, plan: plan)
        state = .enrolled(membership)
        return membership
    }
}

// MARK: - MembershipEnrollSheet

/// §38 — POS / Customer-detail sheet for adding a membership to a customer.
///
/// Usage from POS checkout:
/// ```swift
/// .sheet(isPresented: $showEnroll) {
///     MembershipEnrollSheet(
///         api: api,
///         manager: manager,
///         customerId: customer.id,
///         onEnrolled: { membership in
///             cart.addMembershipLineItem(membership)
///         }
///     )
/// }
/// ```
///
/// iPhone: bottom sheet with `.presentationDetents`.
/// iPad: `.formSheet` popover (inherits from NavigationStack sheet sizing).
public struct MembershipEnrollSheet: View {

    @State private var vm: MembershipEnrollViewModel
    @Environment(\.dismiss) private var dismiss
    private let onEnrolled: ((Membership) -> Void)?

    public init(
        api: any APIClient,
        manager: MembershipSubscriptionManager,
        customerId: String,
        onEnrolled: ((Membership) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: MembershipEnrollViewModel(
            api: api,
            manager: manager,
            customerId: customerId
        ))
        self.onEnrolled = onEnrolled
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add Membership")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarItems }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await vm.loadPlans() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loadingPlans:
            ProgressView("Loading plans…")
                .accessibilityLabel("Loading membership plans")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .plansLoaded, .enrolling:
            planSelectionForm

        case .enrolled(let membership):
            enrolledConfirmation(membership)

        case .failed(let msg):
            ContentUnavailableView(
                "Error",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        }
    }

    // MARK: - Plan selection form

    private var planSelectionForm: some View {
        Form {
            planListSection
            perksSection
            signupBonusSection
        }
    }

    private var planListSection: some View {
        Section("Choose a Plan") {
            ForEach(vm.plans) { plan in
                enrollPlanRow(plan)
            }
        }
    }

    @ViewBuilder
    private func enrollPlanRow(_ plan: MembershipPlan) -> some View {
        let isSelected = vm.selectedPlanId == plan.id
        PlanRow(plan: plan, isSelected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture { vm.selectedPlanId = plan.id }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            #if canImport(UIKit)
            .hoverEffect(.highlight)
            #endif
    }

    @ViewBuilder
    private var perksSection: some View {
        if let plan = vm.selectedPlan, !plan.perks.isEmpty {
            Section("Perks Included") {
                ForEach(Array(plan.perks.enumerated()), id: \.offset) { _, perk in
                    Label(perk.displayName, systemImage: "checkmark.seal.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreSuccess)
                }
            }
        }
    }

    @ViewBuilder
    private var signupBonusSection: some View {
        if let bonus = vm.selectedPlan?.signupBonusPoints, bonus > 0 {
            Section {
                Label(
                    "Earn \(bonus) bonus points on sign-up",
                    systemImage: "star.circle.fill"
                )
                .foregroundStyle(.bizarreOrange)
            }
        }
    }

    // MARK: - Enrolled confirmation

    private func enrolledConfirmation(_ membership: Membership) -> some View {
        VStack(spacing: BrandSpacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("Membership Added!")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Text("Customer has been enrolled in \(vm.selectedPlan?.name ?? "the plan").")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }

            Button("Done") {
                onEnrolled?(membership)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Dismiss and confirm membership enrollment")
        }
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel membership enrollment")
        }
        ToolbarItem(placement: .confirmationAction) {
            if case .enrolling = vm.state {
                ProgressView()
            } else if case .enrolled = vm.state {
                EmptyView()
            } else {
                Button("Enroll") {
                    Task { await vm.enroll() }
                }
                .disabled(!vm.canEnroll)
                .accessibilityLabel("Confirm membership enrollment")
            }
        }
    }
}

// MARK: - PlanRow

private struct PlanRow: View {
    let plan: MembershipPlan
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(plan.name)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(plan.formattedPrice) / \(plan.periodDays) days")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}
