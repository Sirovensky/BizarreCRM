import ActivityKit
import WidgetKit
import SwiftUI
import Core
import DesignSystem

// MARK: - Live Activity Widget declaration

/// Live Activity for employee clock-in/out.
///
/// Shows current shift duration in the Dynamic Island and on the lock screen.
/// Start by calling `LiveActivityCoordinator.startShiftActivity(...)` from the main app.
/// Update every minute via `LiveActivityCoordinator.updateShiftActivity(durationMinutes:)`.
/// End via `LiveActivityCoordinator.endShiftActivity()` on clock-out.
struct ClockInOutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            // Lock screen / StandBy presentation
            LockScreenShiftView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded (long press)
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.employeeName)
                            .font(.caption)
                            .accessibilityLabel("Employee: \(context.attributes.employeeName)")
                    } icon: {
                        Image(systemName: "person.fill")
                            .accessibilityHidden(true)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedText(minutes: context.state.elapsedMinutes))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Shift duration: \(elapsedText(minutes: context.state.elapsedMinutes))")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Clocked in \(context.attributes.clockedInAt, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Clocked in at \(context.attributes.clockedInAt.formatted(date: .omitted, time: .shortened))")
                        Spacer()
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
            } compactLeading: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(elapsedText(minutes: context.state.elapsedMinutes))
                    .font(.caption2.weight(.semibold))
                    .accessibilityLabel("Shift: \(elapsedText(minutes: context.state.elapsedMinutes))")
            } minimal: {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Shift active")
            }
        }
    }

    private func elapsedText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        } else {
            return String(format: "%dm", mins)
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenShiftView: View {
    let context: ActivityViewContext<ShiftActivityAttributes>

    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(context.attributes.employeeName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Employee: \(context.attributes.employeeName)")

                Text("On shift · \(elapsedText(minutes: context.state.elapsedMinutes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("On shift for \(elapsedText(minutes: context.state.elapsedMinutes))")
            }

            Spacer()

            Link(destination: URL(string: "bizarrecrm://timeclock")!) {
                Text("View")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(.tint)
                    .accessibilityLabel("View timesheet")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    }

    private func elapsedText(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, mins)
        } else {
            return String(format: "%dm", mins)
        }
    }
}
