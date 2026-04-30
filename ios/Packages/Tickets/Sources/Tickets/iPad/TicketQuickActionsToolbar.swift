import Foundation
import Networking

// §22 — iPad toolbar quick-assign sheet
//
// `TicketQuickActionsToolbar` is a toolbar item that presents an inline
// popover/sheet for the currently-selected ticket. It contains:
//   - Assign to… (opens TicketAssignSheet)
//   - Mark Complete  (fires the nearest completion transition)
//   - Archive
//
// The toolbar item is disabled when no ticket is selected.
// It is used by TicketsThreeColumnView in the content-column toolbar.

// MARK: - Assign sheet view model (platform-independent)

/// Lightweight state holder for the quick-assign sheet.
/// Pure value type — immutable once created.
public struct TicketQuickAssignState: Sendable, Equatable {
    /// ID of the ticket being acted on.
    public let ticketId: Int64
    /// Currently available assignees (populated from a directory endpoint).
    public let assignees: [TicketAssignee]

    public init(ticketId: Int64, assignees: [TicketAssignee]) {
        self.ticketId = ticketId
        self.assignees = assignees
    }
}

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - Quick-actions toolbar item

/// Secondary toolbar item for the iPad three-column view.
///
/// Renders as an ellipsis-circle button.  Tapping opens a `.sheet` with
/// quick-assign and status-advance actions for the currently selected ticket.
///
/// Pass `selectedTicketId: nil` when no row is selected — the button disables.
public struct TicketQuickActionsToolbar: View {

    public let handlers: TicketQuickActionHandlers
    public let selectedTicketId: Int64?
    public let tickets: [TicketSummary]

    @State private var showingSheet: Bool = false

    public init(
        handlers: TicketQuickActionHandlers,
        selectedTicketId: Int64?,
        tickets: [TicketSummary]
    ) {
        self.handlers = handlers
        self.selectedTicketId = selectedTicketId
        self.tickets = tickets
    }

    public var body: some View {
        Button {
            showingSheet = true
        } label: {
            Label("Quick Actions", systemImage: "ellipsis.circle")
        }
        .disabled(selectedTicketId == nil)
        .accessibilityLabel("Quick actions for selected ticket")
        .accessibilityHint(selectedTicketId == nil
            ? "Select a ticket first"
            : "Opens quick-action sheet for the selected ticket")
        .brandGlass(.clear, in: Capsule())
        .sheet(isPresented: $showingSheet) {
            if let id = selectedTicketId,
               let ticket = tickets.first(where: { $0.id == id }) {
                TicketQuickAssignSheet(
                    ticket: ticket,
                    handlers: handlers,
                    onDismiss: { showingSheet = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Quick-assign sheet

/// Popover/sheet content for quick actions on a single ticket.
///
/// Shows:
///   1. Assign to… (submenu of assignees, or placeholder if none loaded)
///   2. Mark Complete shortcut
///   3. Archive
///
/// This is the "quick-assign sheet" specified in §22 Task 4.
struct TicketQuickAssignSheet: View {

    let ticket: TicketSummary
    let handlers: TicketQuickActionHandlers
    let onDismiss: () -> Void

    // For the MVP the assignee list is empty; the host can extend this
    // once the /employees endpoint is wired.
    @State private var assignees: [TicketAssignee] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    ticketHeaderSection
                    assignSection
                    actionsSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .accessibilityLabel("Dismiss quick-actions sheet")
                }
            }
        }
    }

    // MARK: - Sections

    private var ticketHeaderSection: some View {
        Section {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(ticket.customer?.displayName ?? ticket.orderId)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(ticket.orderId)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
                Spacer()
                if let status = ticket.status {
                    StatusPill(status.name, hue: groupHue(status.group))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ticket \(ticket.orderId) for \(ticket.customer?.displayName ?? "unknown")")
        } header: {
            Text("Ticket")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var assignSection: some View {
        Section {
            if assignees.isEmpty {
                HStack {
                    Label("No assignees available", systemImage: "person.slash")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                }
                .accessibilityLabel("No assignees available — connect to load the employee directory")
            } else {
                ForEach(assignees) { assignee in
                    Button {
                        handlers.onAssign(ticket, assignee.id)
                        onDismiss()
                    } label: {
                        Label(assignee.displayName, systemImage: "person")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Assign to \(assignee.displayName)")
                }
            }
        } header: {
            Text("Assign to\u{2026}")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var actionsSection: some View {
        Section {
            // Mark Complete
            Button {
                if let transition = markCompleteTransition {
                    handlers.onAdvanceStatus(ticket, transition)
                }
                onDismiss()
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(markCompleteTransition == nil ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
            }
            .buttonStyle(.plain)
            .disabled(markCompleteTransition == nil)
            .accessibilityLabel("Mark ticket as complete")
            .accessibilityHint(markCompleteTransition == nil
                ? "Not available for this ticket's current status"
                : "Advances the ticket toward completion")

            // Archive
            Button {
                handlers.onArchive(ticket)
                onDismiss()
            } label: {
                Label("Archive", systemImage: "archivebox")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive ticket")
        } header: {
            Text("Actions")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Helpers

    private var currentStatus: TicketStatus? {
        TicketStatus(rawValue: ticket.status?.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "") ?? "")
    }

    private var markCompleteTransition: TicketTransition? {
        guard let status = currentStatus, !status.isTerminal else { return nil }
        let allowed = TicketStateMachine.allowedTransitions(from: status)
        return allowed.first(where: { $0 == .finishRepair })
            ?? allowed.first(where: { $0 == .pickup })
            ?? allowed.first(where: { $0 != .cancel && $0 != .hold })
    }

    private func groupHue(_ group: TicketSummary.Status.Group) -> StatusPill.Hue {
        switch group {
        case .inProgress: return .inProgress
        case .waiting:    return .awaiting
        case .complete:   return .completed
        case .cancelled:  return .archived
        }
    }
}

#endif
