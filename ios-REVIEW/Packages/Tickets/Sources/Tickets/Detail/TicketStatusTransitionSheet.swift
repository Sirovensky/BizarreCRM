#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// §4.6 — Ticket status transition sheet.
//
// Shows the current status chip + list of allowed TicketTransitions for
// the current local status. The state machine filters the list so the
// Confirm button is only enabled when a valid transition is selected.
//
// On confirm → calls TicketRepository.updateStatus (PATCH /tickets/:id/status).
// The status id is resolved from the server's status list (GET /settings/statuses)
// by matching the transition's target displayName.

// MARK: — View model

@MainActor
@Observable
final class TicketStatusTransitionViewModel {

    // MARK: — Inputs
    let ticketId: Int64
    /// The current status from the ticket detail (server-assigned id + name).
    let currentStatus: TicketDetail.Status?

    // MARK: — Derived from state machine
    let allowedTransitions: [TicketTransition]

    // MARK: — Mutable state
    var selectedTransition: TicketTransition?
    var serverStatuses: [TicketStatusRow] = []
    var isLoading: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?
    var committedTransition: TicketTransition?

    // MARK: — §4.6 Prerequisite state
    /// Set of prerequisite IDs that are currently met on this ticket.
    /// The host view populates this from the ticket detail (photos count, checklist, notes count).
    var metPrerequisites: Set<String> = []

    /// §4.6 — Returns the first unmet prerequisite message for the currently selected transition.
    /// Nil when all prerequisites are met or no transition is selected.
    var unmetPrerequisiteMessage: String? {
        guard let transition = selectedTransition else { return nil }
        if case .failure(let err) = TicketStateMachine.checkPrerequisites(transition, met: metPrerequisites) {
            return err.errorDescription
        }
        return nil
    }

    @ObservationIgnored private let api: APIClient

    init(ticketId: Int64, currentStatus: TicketDetail.Status?, api: APIClient) {
        self.ticketId = ticketId
        self.currentStatus = currentStatus
        self.api = api

        // Derive allowed transitions from the local state machine.
        // Try to match the server status name to a TicketStatus enum value.
        let matched: TicketStatus? = {
            guard let name = currentStatus?.name else { return nil }
            return TicketStatus.allCases.first {
                $0.rawValue.lowercased() == name.lowercased() ||
                $0.displayName.lowercased() == name.lowercased()
            }
        }()
        self.allowedTransitions = matched.map(TicketStateMachine.allowedTransitions(from:)) ?? []
    }

    // MARK: — Load server status list (for id resolution)

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            serverStatuses = try await api.listTicketStatuses()
        } catch {
            AppLog.ui.error("Status list failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: — Confirm transition

    var canConfirm: Bool {
        guard let transition = selectedTransition else { return false }
        guard allowedTransitions.contains(transition) else { return false }
        guard resolveTargetStatusId(for: transition) != nil else { return false }
        // §4.6 — Block if prerequisites unmet
        return unmetPrerequisiteMessage == nil
    }

    func confirm() async {
        guard let transition = selectedTransition else { return }
        // §4.6 — Check prerequisites before calling server
        if let msg = unmetPrerequisiteMessage {
            errorMessage = msg
            return
        }
        // Validate with state machine (belt-and-suspenders).
        if let name = currentStatus?.name {
            let matched = TicketStatus.allCases.first {
                $0.displayName.lowercased() == name.lowercased() ||
                $0.rawValue.lowercased() == name.lowercased()
            }
            if let matched {
                let result = TicketStateMachine.apply(transition, to: matched)
                if case .failure(let err) = result {
                    errorMessage = err.errorDescription
                    return
                }
            }
        }

        guard let statusId = resolveTargetStatusId(for: transition) else {
            errorMessage = "Couldn't find matching status on server for \(transition.displayName)."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        do {
            _ = try await api.changeTicketStatus(id: ticketId, statusId: statusId)
            committedTransition = transition
        } catch {
            AppLog.ui.error("Status transition failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: — Notification helpers

    /// Returns true if the target status row for the given transition has
    /// `notify_customer = 1`. Used to show the notification badge in the
    /// transition row and the confirmation alert before confirming.
    func transitionNotifiesCustomer(_ transition: TicketTransition) -> Bool {
        guard let targetId = resolveTargetStatusId(for: transition) else { return false }
        return (serverStatuses.first { $0.id == targetId }?.notifyCustomer ?? 0) != 0
    }

    /// Optional SMS/email template text for the target status row.
    func transitionNotificationTemplate(_ transition: TicketTransition) -> String? {
        // Server stores template in notification_template column — TicketStatusRow
        // does not yet decode it (added below). Fall back to status name.
        guard let targetId = resolveTargetStatusId(for: transition) else { return nil }
        let row = serverStatuses.first { $0.id == targetId }
        return row.flatMap { _ in nil } // template field not yet in TicketStatusRow
    }

    // MARK: — Private

    /// Look up the server-side status id that corresponds to the target
    /// TicketStatus after applying `transition`. Returns nil if no server
    /// status matches (e.g. tenant deleted that status row).
    private func resolveTargetStatusId(for transition: TicketTransition) -> Int64? {
        guard let currentName = currentStatus?.name else { return nil }
        let currentMatched = TicketStatus.allCases.first {
            $0.displayName.lowercased() == currentName.lowercased() ||
            $0.rawValue.lowercased() == currentName.lowercased()
        }
        guard let currentMatched else { return nil }

        switch TicketStateMachine.apply(transition, to: currentMatched) {
        case .success(let target):
            // Find the server row whose name matches the target display name.
            return serverStatuses.first {
                $0.name.lowercased() == target.displayName.lowercased() ||
                $0.name.lowercased() == target.rawValue.lowercased()
            }?.id
        case .failure:
            return nil
        }
    }
}

// MARK: — View

struct TicketStatusTransitionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketStatusTransitionViewModel
    @State private var showingNotifyAlert: Bool = false
    let onCommitted: () -> Void

    init(
        ticketId: Int64,
        currentStatus: TicketDetail.Status?,
        api: APIClient,
        /// §4.6 — Prerequisite IDs that are met on this ticket.
        /// Pass `.checklistSigned`, `.photoTaken`, etc. from the detail.
        metPrerequisites: Set<String> = [],
        onCommitted: @escaping () -> Void
    ) {
        var vmInstance = TicketStatusTransitionViewModel(
            ticketId: ticketId,
            currentStatus: currentStatus,
            api: api
        )
        vmInstance.metPrerequisites = metPrerequisites
        _vm = State(wrappedValue: vmInstance)
        self.onCommitted = onCommitted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Advance Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Advancing…" : "Confirm") {
                        guard let transition = vm.selectedTransition else { return }
                        if vm.transitionNotifiesCustomer(transition) {
                            showingNotifyAlert = true
                        } else {
                            Task { await confirmAndDismiss() }
                        }
                    }
                    .disabled(!vm.canConfirm || vm.isSubmitting)
                    .accessibilityLabel("Confirm status transition")
                    .accessibilityHint(vm.canConfirm ? "Advances ticket to selected status" : "Select a transition to enable")
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.committedTransition) { _, new in
                guard new != nil else { return }
                onCommitted()
                dismiss()
            }
            // §4.7 — Notify customer confirmation alert.
            // Server auto-sends the notification when notify_customer=1;
            // this alert is advisory — it informs the user before confirming.
            .alert(
                "A notification will be sent",
                isPresented: $showingNotifyAlert,
                presenting: vm.selectedTransition
            ) { transition in
                Button("Advance") {
                    Task { await confirmAndDismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { transition in
                Text("Advancing to \"\(transition.displayName)\" is configured to send an SMS or email to the customer.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading statuses")
        } else {
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    // Current status chip
                    currentStatusHeader

                    if vm.allowedTransitions.isEmpty {
                        emptyState
                    } else {
                        transitionList
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.base)
                            .accessibilityLabel("Error: \(err)")
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
    }

    // MARK: — Sub-views

    private var currentStatusHeader: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Current status")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            Text(vm.currentStatus?.name ?? "Unknown")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .brandGlass(.clear, in: Capsule())
                .accessibilityLabel("Current status: \(vm.currentStatus?.name ?? "Unknown")")
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var transitionList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Available transitions")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ForEach(vm.allowedTransitions, id: \.self) { transition in
                transitionRow(transition)
            }
        }
    }

    private func transitionRow(_ transition: TicketTransition) -> some View {
        let isSelected = vm.selectedTransition == transition
        let isEnabled = !vm.isSubmitting
        let notifies = vm.transitionNotifiesCustomer(transition)

        return Button {
            vm.selectedTransition = isSelected ? nil : transition
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: transition.systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(transition.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if notifies {
                        Label("Notifies customer", systemImage: "bell.fill")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Selected")
                }
            }
            .padding(BrandSpacing.base)
            .background(
                isSelected
                    ? Color.bizarreOrange.opacity(0.12)
                    : Color.bizarreSurface1,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(notifies
            ? "Transition: \(transition.displayName). Notifies customer."
            : "Transition: \(transition.displayName)")
        .accessibilityHint(isSelected ? "Selected" : "Tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "lock.circle")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No transitions available")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("This ticket is in a terminal state or the current status has no allowed transitions.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No transitions available. This ticket is in a terminal state.")
    }

    // MARK: — Actions

    private func confirmAndDismiss() async {
        await vm.confirm()
    }
}
#endif
