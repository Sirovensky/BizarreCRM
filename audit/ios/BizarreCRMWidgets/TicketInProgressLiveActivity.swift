import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - §24.3 Live Activity: Ticket in progress

/// Live Activity shown when a technician clicks "Start work" on a ticket.
///
/// Shows on Lock Screen + Dynamic Island: timer, customer name, service, repair phase.
/// Ends when the ticket is marked Done — lingers 12 s with "Ticket done" dismissal copy.
///
/// Start from the Tickets feature ViewModel:
/// ```swift
/// let coordinator = LiveActivityCoordinator()
/// try await coordinator.startTicketActivity(
///     ticketId: ticket.id,
///     orderId: ticket.orderId,
///     customerName: ticket.customerName,
///     service: ticket.service
/// )
/// // Update phase as work progresses:
/// try await coordinator.updateTicketActivity(elapsedMinutes: 30, phase: .repairing)
/// // End when done:
/// await coordinator.endTicketActivity(resolved: true)
/// ```
struct TicketInProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TicketInProgressAttributes.self) { context in
            LockScreenTicketView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.customerName ?? "Ticket \(context.attributes.orderId)")
                            .font(.caption)
                            .lineLimit(1)
                            .accessibilityLabel("Customer: \(context.attributes.customerName ?? context.attributes.orderId)")
                    } icon: {
                        Image(systemName: phaseIcon(context.state.phase))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedText(minutes: context.state.elapsedMinutes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .monospacedDigit()
                        .accessibilityLabel("Work time: \(elapsedText(minutes: context.state.elapsedMinutes))")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        // Phase badge
                        Text(context.state.phase.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .accessibilityLabel("Phase: \(context.state.phase.rawValue)")
                        Text(context.attributes.service ?? "#\(context.attributes.orderId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "timer")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
            } compactLeading: {
                // Compact leading: phase-specific icon for richer at-a-glance info
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } compactTrailing: {
                // Compact trailing: elapsed time + phase initial (e.g. "30m R")
                HStack(spacing: 2) {
                    Text(elapsedText(minutes: context.state.elapsedMinutes))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                    Text(phaseInitial(context.state.phase))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Ticket: \(elapsedText(minutes: context.state.elapsedMinutes)), \(context.state.phase.rawValue)")
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Ticket \(context.state.phase.rawValue)")
            }
        }
    }

    private func elapsedText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        return hours > 0
            ? String(format: "%dh %02dm", hours, mins)
            : String(format: "%dm", mins)
    }

    /// SF Symbol name representing the current repair phase.
    private func phaseIcon(_ phase: TicketPhase) -> String {
        switch phase {
        case .diagnosing:   return "stethoscope"
        case .repairing:    return "wrench.and.screwdriver.fill"
        case .testing:      return "checkmark.shield"
        case .waitingParts: return "shippingbox"
        case .done:         return "checkmark.circle.fill"
        }
    }

    /// Single-character phase abbreviation for the compact-trailing slot.
    private func phaseInitial(_ phase: TicketPhase) -> String {
        switch phase {
        case .diagnosing:   return "D"
        case .repairing:    return "R"
        case .testing:      return "T"
        case .waitingParts: return "W"
        case .done:         return "✓"
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenTicketView: View {
    let context: ActivityViewContext<TicketInProgressAttributes>

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: phaseIcon(context.state.phase))
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                // Animate icon change when phase transitions
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                // Row 1: Customer name + phase badge
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(context.attributes.customerName ?? "Ticket #\(context.attributes.orderId)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .accessibilityLabel("Customer: \(context.attributes.customerName ?? context.attributes.orderId)")

                    // Phase chip — hidden when done (uses icon instead)
                    if context.state.phase != .done {
                        Text(context.state.phase.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.tint.opacity(0.15), in: Capsule())
                            .accessibilityLabel(context.state.phase.rawValue)
                    }
                }

                // Row 2: Service + elapsed (shows "Ticket done" when finished)
                if context.state.phase == .done {
                    Text("Ticket done · \(elapsedText(minutes: context.state.elapsedMinutes))")
                        .font(.caption)
                        .foregroundStyle(.bizarreSuccess)
                        .monospacedDigit()
                        .accessibilityLabel("Ticket complete, total time \(elapsedText(minutes: context.state.elapsedMinutes))")
                } else {
                    Text("\(context.attributes.service ?? "#\(context.attributes.orderId)") · \(elapsedText(minutes: context.state.elapsedMinutes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel("\(context.attributes.service ?? context.attributes.orderId), in progress for \(elapsedText(minutes: context.state.elapsedMinutes))")
                }
            }

            Spacer()

            Link(destination: URL(string: "bizarrecrm://tickets/\(context.attributes.ticketId)")!) {
                Text("View")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("View ticket")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }

    private func elapsedText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins  = minutes % 60
        return hours > 0
            ? String(format: "%dh %02dm", hours, mins)
            : String(format: "%dm", mins)
    }

    private func phaseIcon(_ phase: TicketPhase) -> String {
        switch phase {
        case .diagnosing:   return "stethoscope"
        case .repairing:    return "wrench.and.screwdriver.fill"
        case .testing:      return "checkmark.shield"
        case .waitingParts: return "shippingbox"
        case .done:         return "checkmark.circle.fill"
        }
    }
}
