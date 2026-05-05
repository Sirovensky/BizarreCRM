import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentTimelineStrip
//
// Horizontal hour-by-hour scrollable timeline for a single day.
// Shows 24 hour slots (configurable range) with appointment chips
// laid out at the correct horizontal position.
//
// Usage:
//   AppointmentTimelineStrip(appointments: vm.dayAgendaAppointments, date: vm.selectedDate)
//       .frame(height: 80)
//
// iPad-only. Do not render on iPhone (guard with Platform.isCompact).

// MARK: - Timeline constants

private enum TimelineLayout {
    /// Width in points for each 1-hour slot.
    static let hourWidth: CGFloat = 80
    /// Height of the strip.
    static let stripHeight: CGFloat = 72
    /// Vertical padding inside each chip.
    static let chipVPad: CGFloat = 4
    /// Minimum chip width.
    static let minChipWidth: CGFloat = 40
    /// Visible hour range (inclusive start, exclusive end).
    static let firstHour: Int = 7
    static let lastHour: Int  = 21
    static var visibleHours: Int { lastHour - firstHour }
}

// MARK: - AppointmentTimelineStrip

/// Horizontal hour-timeline scrollview for a single day.
/// Tapping a chip calls `onSelect`.
public struct AppointmentTimelineStrip: View {

    public let appointments: [Appointment]
    public let date: Date
    public var onSelect: ((Appointment) -> Void)?

    public init(
        appointments: [Appointment],
        date: Date,
        onSelect: ((Appointment) -> Void)? = nil
    ) {
        self.appointments = appointments
        self.date = date
        self.onSelect = onSelect
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return f
    }()

    private static let chipTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    appointmentLayer
                }
                .frame(
                    width: CGFloat(TimelineLayout.visibleHours) * TimelineLayout.hourWidth,
                    height: TimelineLayout.stripHeight
                )
            }
            .onAppear {
                scrollToCurrentHour(proxy: proxy)
            }
        }
        .background(Color.bizarreSurface1)
        .accessibilityLabel("Day timeline, \(formattedDay)")
    }

    // MARK: - Hour grid

    private var hourGrid: some View {
        HStack(spacing: 0) {
            ForEach(TimelineLayout.firstHour..<TimelineLayout.lastHour, id: \.self) { hour in
                hourCell(hour: hour)
            }
        }
    }

    private func hourCell(hour: Int) -> some View {
        let isCurrentHour = Calendar.current.component(.hour, from: Date()) == hour
            && Calendar.current.isDateInToday(date)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Self.hourFormatter.string(from: hourDate(hour)))
                .font(.brandMono(size: 10))
                .foregroundStyle(isCurrentHour ? Color.bizarreOrange : .bizarreOnSurfaceMuted)
                .padding(.leading, BrandSpacing.xxs)
                .padding(.top, BrandSpacing.xxs)
            Spacer()
            Divider()
        }
        .frame(width: TimelineLayout.hourWidth, height: TimelineLayout.stripHeight)
        .background(isCurrentHour ? Color.bizarreOrange.opacity(0.05) : Color.clear)
        .id("hour-\(hour)")
        .accessibilityLabel("\(hour):00")
    }

    // MARK: - Appointment layer

    private var appointmentLayer: some View {
        ForEach(appointments) { appt in
            if let (xOffset, width) = chipGeometry(for: appt) {
                appointmentChip(appt, width: width)
                    .offset(x: xOffset, y: TimelineLayout.chipVPad)
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private func appointmentChip(_ appt: Appointment, width: CGFloat) -> some View {
        Button {
            onSelect?(appt)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(appt.title ?? "Appointment")
                    .font(.brandLabelSmall())
                    .foregroundStyle(chipTextColor(for: appt.status))
                    .lineLimit(1)
                if let raw = appt.startTime, let date = Self.parseDate(raw) {
                    Text(Self.chipTimeFormatter.string(from: date))
                        .font(.brandMono(size: 9))
                        .foregroundStyle(chipTextColor(for: appt.status).opacity(0.8))
                }
            }
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TimelineLayout.stripHeight - TimelineLayout.chipVPad * 2)
            .background(chipBackground(for: appt.status), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .strokeBorder(chipTextColor(for: appt.status).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(apptA11y(for: appt))
        .accessibilityHint("Double tap to view details")
        #if !os(macOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Geometry

    /// Returns (xOffset, width) in the timeline coordinate space, or nil if out of visible range.
    private func chipGeometry(for appt: Appointment) -> (CGFloat, CGFloat)? {
        guard
            let rawS = appt.startTime,
            let start = Self.parseDate(rawS)
        else { return nil }

        let startHour = fractionalHour(from: start)
        guard startHour < CGFloat(TimelineLayout.lastHour) else { return nil }

        let endHour: CGFloat
        if let rawE = appt.endTime, let end = Self.parseDate(rawE) {
            endHour = fractionalHour(from: end)
        } else {
            endHour = startHour + 1.0 // default 1-hr block
        }

        let clampedStart = max(startHour, CGFloat(TimelineLayout.firstHour))
        let clampedEnd   = min(endHour,   CGFloat(TimelineLayout.lastHour))
        guard clampedEnd > clampedStart else { return nil }

        let xOffset = (clampedStart - CGFloat(TimelineLayout.firstHour)) * TimelineLayout.hourWidth
        let width   = max((clampedEnd - clampedStart) * TimelineLayout.hourWidth - 2, TimelineLayout.minChipWidth)
        return (xOffset, width)
    }

    private func fractionalHour(from date: Date) -> CGFloat {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return CGFloat(comps.hour ?? 0) + CGFloat(comps.minute ?? 0) / 60.0
    }

    private func hourDate(_ hour: Int) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var target = comps
        target.hour = hour
        target.minute = 0
        return Calendar.current.date(from: target) ?? date
    }

    private var formattedDay: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    // MARK: - Scroll to now

    private func scrollToCurrentHour(proxy: ScrollViewProxy) {
        guard Calendar.current.isDateInToday(date) else { return }
        let hour = max(Calendar.current.component(.hour, from: Date()) - 1, TimelineLayout.firstHour)
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo("hour-\(hour)", anchor: .leading) }
        }
    }

    // MARK: - Static helpers (mirrors CalendarGrid parser)

    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        let iso2 = ISO8601DateFormatter()
        if let d = iso2.date(from: raw) { return d }
        let sql = DateFormatter()
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sql.timeZone = TimeZone(identifier: "UTC")
        sql.locale = Locale(identifier: "en_US_POSIX")
        return sql.date(from: raw)
    }

    // MARK: - Color helpers

    private func chipBackground(for status: String?) -> Color {
        switch status?.lowercased() {
        case "confirmed":  return Color.bizarreSuccess.opacity(0.15)
        case "completed":  return Color.bizarreSuccess.opacity(0.08)
        case "cancelled":  return Color.bizarreError.opacity(0.10)
        case "no-show":    return Color.bizarreWarning.opacity(0.12)
        default:           return Color.bizarreOrange.opacity(0.15)
        }
    }

    private func chipTextColor(for status: String?) -> Color {
        switch status?.lowercased() {
        case "confirmed":  return .bizarreSuccess
        case "completed":  return .bizarreSuccess
        case "cancelled":  return .bizarreError
        case "no-show":    return .bizarreWarning
        default:           return .bizarreOrange
        }
    }

    private func apptA11y(for appt: Appointment) -> String {
        var parts: [String] = [appt.title ?? "Appointment"]
        if let raw = appt.startTime, let date = Self.parseDate(raw) {
            parts.append(Self.chipTimeFormatter.string(from: date))
        }
        if let status = appt.status { parts.append("Status \(status)") }
        return parts.joined(separator: ", ")
    }
}
