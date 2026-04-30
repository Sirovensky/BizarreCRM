import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - §24.3 Live Activity: Appointment countdown (15 min before)
//
// Starts 15 minutes before a scheduled appointment.
// Displays on Lock Screen + Dynamic Island with countdown timer, customer name,
// and service type. Ends when the appointment starts or is cancelled.
//
// Start from Appointments ViewModel:
// ```swift
// let coordinator = LiveActivityCoordinator()
// try await coordinator.startAppointmentCountdown(
//     appointmentId: appointment.id,
//     customerName: appointment.customerName,
//     service: appointment.service,
//     scheduledAt: appointment.scheduledAt
// )
// ```

// MARK: - Attributes

public struct AppointmentCountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Minutes remaining until appointment.
        public var minutesRemaining: Int
        /// Whether the appointment has been confirmed by staff.
        public var isConfirmed: Bool
    }

    public let appointmentId: Int
    public let customerName: String
    public let service: String
    public let scheduledAt: Date
}

// MARK: - Widget

struct AppointmentCountdownLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AppointmentCountdownAttributes.self) { context in
            LockScreenAppointmentView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.customerName)
                            .font(.caption)
                            .lineLimit(1)
                            .accessibilityLabel("Customer: \(context.attributes.customerName)")
                    } icon: {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownLabel(minutes: context.state.minutesRemaining)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.service)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if context.state.isConfirmed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.bizarreSuccess)
                                .accessibilityLabel("Confirmed")
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } compactTrailing: {
                countdownLabel(minutes: context.state.minutesRemaining)
            } minimal: {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Appointment countdown")
            }
        }
    }

    @ViewBuilder
    private func countdownLabel(minutes: Int) -> some View {
        if minutes <= 0 {
            Text("Now")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.bizarreWarning)
                .monospacedDigit()
                .accessibilityLabel("Appointment now")
        } else {
            Text("\(minutes)m")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .monospacedDigit()
                .accessibilityLabel("\(minutes) minutes remaining")
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenAppointmentView: View {
    let context: ActivityViewContext<AppointmentCountdownAttributes>

    var body: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(context.attributes.customerName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .accessibilityLabel("Customer: \(context.attributes.customerName)")

                    if context.state.isConfirmed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.bizarreSuccess)
                            .accessibilityLabel("Confirmed")
                    }
                }

                Text(context.attributes.service)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if context.state.minutesRemaining <= 0 {
                    Text("Starting now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.bizarreWarning)
                } else {
                    Text("In \(context.state.minutesRemaining) min — \(context.attributes.scheduledAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("In \(context.state.minutesRemaining) minutes at \(context.attributes.scheduledAt.formatted(date: .omitted, time: .shortened))")
                }
            }

            Spacer()

            Link(destination: URL(string: "bizarrecrm://appointments/\(context.attributes.appointmentId)")!) {
                Text("View")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("View appointment")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Coordinator extension

public extension LiveActivityCoordinator {

    /// Start a 15-minute countdown Live Activity for an upcoming appointment.
    /// - Requires `NSSupportsLiveActivities` in Info.plist.
    @available(iOS 16.2, *)
    @discardableResult
    func startAppointmentCountdown(
        appointmentId: Int,
        customerName: String,
        service: String,
        scheduledAt: Date
    ) async throws -> Activity<AppointmentCountdownAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let minutesRemaining = max(0, Int(scheduledAt.timeIntervalSinceNow / 60))
        let attributes = AppointmentCountdownAttributes(
            appointmentId: appointmentId,
            customerName: customerName,
            service: service,
            scheduledAt: scheduledAt
        )
        let state = AppointmentCountdownAttributes.ContentState(
            minutesRemaining: minutesRemaining,
            isConfirmed: false
        )
        let content = ActivityContent(
            state: state,
            staleDate: scheduledAt.addingTimeInterval(60)   // stale 1 min after start
        )
        return try Activity.request(attributes: attributes, content: content)
    }

    /// Update countdown remaining minutes (call every minute from a Timer).
    @available(iOS 16.2, *)
    func updateAppointmentCountdown(
        activity: Activity<AppointmentCountdownAttributes>,
        minutesRemaining: Int,
        isConfirmed: Bool = false
    ) async {
        let state = AppointmentCountdownAttributes.ContentState(
            minutesRemaining: minutesRemaining,
            isConfirmed: isConfirmed
        )
        let stale = activity.attributes.scheduledAt.addingTimeInterval(60)
        let content = ActivityContent(state: state, staleDate: stale)
        await activity.update(content)
    }

    /// End the appointment countdown (appointment started or cancelled).
    @available(iOS 16.2, *)
    func endAppointmentCountdown(
        activity: Activity<AppointmentCountdownAttributes>
    ) async {
        let finalState = AppointmentCountdownAttributes.ContentState(
            minutesRemaining: 0,
            isConfirmed: true
        )
        let content = ActivityContent(state: finalState, staleDate: .now)
        await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(5)))
    }
}
