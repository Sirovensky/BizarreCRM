import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §3.5 Getting-started / onboarding checklist

// MARK: - Model

/// A single step in the getting-started checklist shown on the dashboard.
public struct OnboardingStep: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isCompleted: Bool
    /// Deep-link or action route for the CTA tap.
    public let deepLink: String

    public init(id: String, title: String, systemImage: String, isCompleted: Bool, deepLink: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isCompleted = isCompleted
        self.deepLink = deepLink
    }
}

/// ViewModel for the §3.5 onboarding checklist card.
/// Loaded from `GET /api/v1/onboarding/state` + `GET /api/v1/settings/setup-status`.
@MainActor
@Observable
public final class OnboardingChecklistViewModel {

    public enum LoadState: Sendable {
        case idle, loading, loaded, failed(String)
    }

    public var loadState: LoadState = .idle
    public var steps: [OnboardingStep] = []
    public var isDismissed: Bool = false
    public var showCelebration: Bool = false

    private let api: APIClient
    @ObservationIgnored private var celebrationReason: String = ""

    public init(api: APIClient) {
        self.api = api
    }

    public var completedCount: Int { steps.filter(\.isCompleted).count }
    public var totalCount: Int { steps.count }
    public var isAllComplete: Bool { completedCount == totalCount && totalCount > 0 }
    public var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public func load() async {
        guard case .idle = loadState else { return }
        loadState = .loading
        do {
            let state = try await api.fetchOnboardingState()
            let setup = try await api.fetchSetupStatus()
            steps = buildSteps(state: state, setup: setup)
            isDismissed = state.checklistDismissed
            loadState = .loaded
            // Show celebration if all complete and not yet dismissed
            if isAllComplete && !isDismissed {
                celebrationReason = "setup complete"
                showCelebration = true
            }
        } catch {
            AppLog.ui.error("OnboardingChecklist load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    public func dismiss() async {
        isDismissed = true
        do {
            _ = try await api.patchOnboardingDismissed()
        } catch {
            AppLog.ui.error("OnboardingChecklist dismiss failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func buildSteps(state: OnboardingState, setup: SetupStatusData) -> [OnboardingStep] {
        [
            OnboardingStep(
                id: "first_customer",
                title: "Add your first customer",
                systemImage: "person.crop.circle.badge.plus",
                isCompleted: state.firstCustomerAt != nil,
                deepLink: "bizarrecrm://customers/new"
            ),
            OnboardingStep(
                id: "first_ticket",
                title: "Create your first ticket",
                systemImage: "wrench.and.screwdriver",
                isCompleted: state.firstTicketAt != nil,
                deepLink: "bizarrecrm://tickets/new"
            ),
            OnboardingStep(
                id: "configure_sms",
                title: "Configure SMS provider",
                systemImage: "message.badge.filled.fill",
                isCompleted: false, // TODO: wire to settings endpoint once available
                deepLink: "bizarrecrm://settings/sms"
            ),
            OnboardingStep(
                id: "invite_employee",
                title: "Invite an employee",
                systemImage: "person.badge.plus",
                isCompleted: false, // TODO: wire to employee count endpoint
                deepLink: "bizarrecrm://settings/employees"
            ),
            OnboardingStep(
                id: "print_receipt",
                title: "Print your first receipt",
                systemImage: "printer",
                isCompleted: false, // TODO: wire to printer event
                deepLink: "bizarrecrm://settings/printers"
            ),
        ]
    }
}

// MARK: - API extension for dismiss

public extension APIClient {
    /// PATCH /api/v1/onboarding/state — marks checklist as dismissed.
    func patchOnboardingDismissed() async throws -> OnboardingState {
        return try await patch("onboarding/state", body: OnboardingDismissBody(checklistDismissed: true), as: OnboardingState.self)
    }
}

private struct OnboardingDismissBody: Encodable, Sendable {
    let checklistDismissed: Bool
    enum CodingKeys: String, CodingKey { case checklistDismissed = "checklist_dismissed" }
}

// MARK: - Card View

/// §3.5 — Collapsible glass card at top of dashboard.
/// Hidden once `isDismissed == true` and progress == 100%.
public struct OnboardingChecklistCard: View {
    @State private var vm: OnboardingChecklistViewModel
    @State private var isExpanded: Bool = true
    var onStepTap: ((String) -> Void)?   // deepLink string → caller handles navigation

    public init(api: APIClient, onStepTap: ((String) -> Void)? = nil) {
        _vm = State(wrappedValue: OnboardingChecklistViewModel(api: api))
        self.onStepTap = onStepTap
    }

    public var body: some View {
        Group {
            if vm.isDismissed && vm.isAllComplete { EmptyView() }
            else { cardBody }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showCelebration) {
            CelebratoryModal(reason: "Setup complete!", onDismiss: { vm.showCelebration = false })
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().overlay(Color.bizarreOutline.opacity(0.2))
                stepsBody
            }
        }
        .background(.brandGlass(radius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5))
        .animation(.spring(duration: 0.28), value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Get started")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.bizarreOutline.opacity(0.2))
                            .frame(height: 4)
                        Capsule().fill(Color.bizarreOrange)
                            .frame(width: geo.size.width * vm.progressFraction, height: 4)
                    }
                }
                .frame(height: 4)
                Text("\(vm.completedCount) of \(vm.totalCount) steps")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            // Chevron toggle
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse checklist" : "Expand checklist")

            if vm.isAllComplete {
                Button("Dismiss") { Task { await vm.dismiss() } }
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .buttonStyle(.plain)
            }
        }
        .padding(BrandSpacing.md)
    }

    @ViewBuilder
    private var stepsBody: some View {
        VStack(spacing: 0) {
            ForEach(vm.steps) { step in
                ChecklistRow(step: step) {
                    onStepTap?(step.deepLink)
                }
                if step.id != vm.steps.last?.id {
                    Divider().overlay(Color.bizarreOutline.opacity(0.15)).padding(.leading, 44)
                }
            }
        }
        .padding(.bottom, BrandSpacing.sm)
    }
}

// MARK: - Row

private struct ChecklistRow: View {
    let step: OnboardingStep
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(step.isCompleted ? Color.bizarreOrange : Color.bizarreOutline.opacity(0.2))
                        .frame(width: 28, height: 28)
                    if step.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: step.systemImage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityHidden(true)

                Text(step.title)
                    .font(.brandBodyMedium())
                    .foregroundStyle(step.isCompleted ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                    .strikethrough(step.isCompleted, color: .bizarreOnSurfaceMuted)
                Spacer()
                if !step.isCompleted {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(step.title)
        .accessibilityValue(step.isCompleted ? "Complete" : "Incomplete")
        .accessibilityAddTraits(step.isCompleted ? [] : .isButton)
    }
}

// MARK: - Celebratory Modal

/// §3.5 — "Setup complete" celebratory modal with confetti Symbol animation.
private struct CelebratoryModal: View {
    let reason: String
    let onDismiss: () -> Void
    @State private var animationPhase: Bool = false

    var body: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()
            Image(systemName: "party.popper.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.bizarreOrange)
                .symbolEffect(.bounce, value: animationPhase)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text(reason)
                    .font(.brandDisplaySmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Text("Your shop is all set. Time to take on customers!")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            Spacer()

            Button("Let's go!", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .font(.brandTitleSmall())
                .padding(.bottom, BrandSpacing.xl)
        }
        .background(.brandGlass(radius: 0))
        .presentationDetents([.medium])
        .onAppear { animationPhase = true }
        .accessibilityLabel("\(reason). Your shop is all set.")
    }
}
