import SwiftUI
import Core
import DesignSystem

// MARK: - §19 OpenClosedIndicator

/// Reusable indicator that shows the current open/closed state and a hint
/// ("Closes in 2 h 15 min" / "Opens at 9:00 AM").
///
/// Used in Dashboard header and POS home. Takes the full week schedule +
/// holiday exceptions and re-computes every minute via a timer.
public struct OpenClosedIndicator: View {

    private let week: BusinessHoursWeek
    private let holidays: [HolidayException]
    private let timezone: TimeZone

    @State private var status: OpenStatus = .closed(opensAt: nil)
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    public init(
        week: BusinessHoursWeek,
        holidays: [HolidayException],
        timezone: TimeZone = .current
    ) {
        self.week = week
        self.holidays = holidays
        self.timezone = timezone
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(statusLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(indicatorColor)

                if let hint = hintLabel {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .onReceive(timer) { now = $0 }
        .onChange(of: now) { _, new in recompute(at: new) }
        .onAppear { recompute(at: now) }
    }

    // MARK: - Compute

    private func recompute(at date: Date) {
        status = HoursCalculator.currentStatus(at: date, week: week, holidays: holidays, timezone: timezone)
    }

    // MARK: - Derived display values

    private var indicatorColor: Color {
        switch status {
        case .open:    return Color.bizarreSuccess
        case .onBreak: return Color.bizarreWarning
        case .closed:  return Color.bizarreError
        }
    }

    private var statusLabel: String {
        switch status {
        case .open:    return "Open"
        case .onBreak: return "On break"
        case .closed:  return "Closed"
        }
    }

    private var hintLabel: String? {
        switch status {
        case .open(let closesAt):
            return "Closes \(relativeMins(to: closesAt))"
        case .onBreak(let endsAt):
            return "Break ends \(relativeMins(to: endsAt))"
        case .closed(let opensAt):
            guard let opensAt else { return nil }
            return "Opens \(relativeMins(to: opensAt))"
        }
    }

    private var accessibilityDescription: String {
        [statusLabel, hintLabel].compactMap { $0 }.joined(separator: ". ")
    }

    // MARK: - Helpers

    private func relativeMins(to date: Date) -> String {
        let mins = Int(date.timeIntervalSince(now) / 60)
        if mins < 0 { return "soon" }
        if mins < 60 { return "in \(mins) min" }
        let h = mins / 60
        let m = mins % 60
        if m == 0 { return "in \(h) h" }
        return "in \(h) h \(m) min"
    }
}
