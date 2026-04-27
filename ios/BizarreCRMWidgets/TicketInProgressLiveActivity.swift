import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - §24.3 Live Activity: Ticket in progress

/// Live Activity shown when a technician clicks "Start work" on a ticket.
///
/// Shows on Lock Screen + Dynamic Island: timer, customer name, service.
/// Ends when the ticket is marked Done.
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
                        Image(systemName: "wrench.and.screwdriver.fill")
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
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(elapsedText(minutes: context.state.elapsedMinutes))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Ticket time: \(elapsedText(minutes: context.state.elapsedMinutes))")
            } minimal: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Ticket in progress")
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
}

// MARK: - Lock screen view

private struct LockScreenTicketView: View {
    let context: ActivityViewContext<TicketInProgressAttributes>

    var body: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(context.attributes.customerName ?? "Ticket #\(context.attributes.orderId)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .accessibilityLabel("Customer: \(context.attributes.customerName ?? context.attributes.orderId)")

                Text("In progress · \(elapsedText(minutes: context.state.elapsedMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("In progress for \(elapsedText(minutes: context.state.elapsedMinutes))")
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
}
