import Foundation
import SwiftUI
import DesignSystem

// MARK: - §37 Campaign Schedule Types (recurring + triggered)

/// Extended schedule options beyond the simple `now / scheduled` of §37.1.
///
/// This enum extends the campaign scheduling with:
/// - `recurring` — weekly newsletter, monthly digest, etc.
/// - `triggered` — event-driven sends (birthday, post-service, re-engagement).
///
/// The UI exposes these through `CampaignScheduleSectionView`; the ViewModel
/// converts the selection into `ScheduleChoice` for the existing save path.
public enum CampaignScheduleKind: String, CaseIterable, Sendable, Codable {
    case sendNow       = "now"
    case sendAt        = "scheduled"
    case recurring     = "recurring"
    case triggered     = "triggered"

    public var displayName: String {
        switch self {
        case .sendNow:   return "Send now"
        case .sendAt:    return "At a specific time"
        case .recurring: return "Recurring"
        case .triggered: return "Triggered by event"
        }
    }

    public var systemImage: String {
        switch self {
        case .sendNow:   return "paperplane.fill"
        case .sendAt:    return "calendar.badge.clock"
        case .recurring: return "repeat.circle.fill"
        case .triggered: return "bolt.fill"
        }
    }
}

/// Recurrence configuration for `CampaignScheduleKind.recurring`.
public struct CampaignRecurrenceConfig: Codable, Sendable, Equatable {
    public enum Frequency: String, CaseIterable, Codable, Sendable {
        case daily, weekly, biweekly, monthly, quarterly

        public var displayName: String {
            switch self {
            case .daily:       return "Daily"
            case .weekly:      return "Weekly"
            case .biweekly:    return "Every 2 weeks"
            case .monthly:     return "Monthly"
            case .quarterly:   return "Quarterly"
            }
        }
    }

    public var frequency: Frequency
    /// Calendar day-of-week (1 = Sunday, 7 = Saturday). Nil for non-weekly.
    public var dayOfWeek: Int?
    /// Day of month (1–28). Nil for non-monthly.
    public var dayOfMonth: Int?
    /// Wall-clock send time (hour + minute).
    public var sendHour: Int
    public var sendMinute: Int
    /// Optional end date after which no more sends occur.
    public var endsAt: Date?

    public init(
        frequency: Frequency = .weekly,
        dayOfWeek: Int? = 2, // Monday by default
        dayOfMonth: Int? = nil,
        sendHour: Int = 9,
        sendMinute: Int = 0,
        endsAt: Date? = nil
    ) {
        self.frequency = frequency
        self.dayOfWeek = dayOfWeek
        self.dayOfMonth = dayOfMonth
        self.sendHour = sendHour
        self.sendMinute = sendMinute
        self.endsAt = endsAt
    }

    /// Human-readable summary.
    public var summary: String {
        var parts: [String] = [frequency.displayName]
        switch frequency {
        case .weekly, .biweekly:
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            if let dow = dayOfWeek, dow >= 1, dow <= 7 {
                parts.append("on \(dayNames[dow - 1])")
            }
        case .monthly, .quarterly:
            if let dom = dayOfMonth {
                parts.append("on day \(dom)")
            }
        default: break
        }
        let hour = sendHour % 12 == 0 ? 12 : sendHour % 12
        let ampm = sendHour < 12 ? "AM" : "PM"
        parts.append("at \(hour):\(String(format: "%02d", sendMinute)) \(ampm)")
        return parts.joined(separator: " ")
    }
}

/// Trigger event configuration for `CampaignScheduleKind.triggered`.
public struct CampaignTriggerConfig: Codable, Sendable, Equatable {
    public enum TriggerEvent: String, CaseIterable, Codable, Sendable {
        case birthday          = "birthday"
        case postServiceSMS    = "post_service"
        case reengagement      = "reengagement"
        case membershipExpiry  = "membership_expiry"
        case firstVisit        = "first_visit"
        case inactivity        = "inactivity"

        public var displayName: String {
            switch self {
            case .birthday:         return "Birthday"
            case .postServiceSMS:   return "After service completed"
            case .reengagement:     return "Re-engagement (lapsed customer)"
            case .membershipExpiry: return "Membership expiring soon"
            case .firstVisit:       return "First visit"
            case .inactivity:       return "Customer inactivity"
            }
        }

        public var systemImage: String {
            switch self {
            case .birthday:         return "gift.fill"
            case .postServiceSMS:   return "checkmark.seal.fill"
            case .reengagement:     return "arrow.counterclockwise.circle.fill"
            case .membershipExpiry: return "creditcard.fill"
            case .firstVisit:       return "person.badge.plus"
            case .inactivity:       return "moon.zzz.fill"
            }
        }
    }

    public var event: TriggerEvent
    /// Delay from trigger (e.g. send 24h after service, or 7d before birthday).
    /// Positive = after event; negative = before event.
    public var delayHours: Int

    public init(event: TriggerEvent = .postServiceSMS, delayHours: Int = 24) {
        self.event = event
        self.delayHours = delayHours
    }

    public var summary: String {
        let delay = abs(delayHours)
        let timing = delayHours < 0 ? "\(delay)h before" : "\(delay)h after"
        return "\(event.displayName) (\(timing))"
    }
}

// MARK: - CampaignScheduleSectionView

/// Full-featured schedule section for `CampaignCreateView`.
///
/// Replaces the simple two-option picker with the four-mode selector
/// (`sendNow / sendAt / recurring / triggered`). A small "preview" card
/// below the controls summarises the active configuration.
public struct CampaignScheduleSectionView: View {
    @Binding public var kind: CampaignScheduleKind
    @Binding public var sendAt: Date
    @Binding public var recurrence: CampaignRecurrenceConfig
    @Binding public var trigger: CampaignTriggerConfig

    public init(
        kind: Binding<CampaignScheduleKind>,
        sendAt: Binding<Date>,
        recurrence: Binding<CampaignRecurrenceConfig>,
        trigger: Binding<CampaignTriggerConfig>
    ) {
        _kind = kind
        _sendAt = sendAt
        _recurrence = recurrence
        _trigger = trigger
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Kind picker chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(CampaignScheduleKind.allCases, id: \.self) { k in
                        kindChip(k)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
            .padding(.horizontal, -BrandSpacing.base) // bleed to edge

            // Detail controls per kind
            switch kind {
            case .sendNow:
                sendNowRow
            case .sendAt:
                sendAtRow
            case .recurring:
                recurringControls
            case .triggered:
                triggeredControls
            }

            // Summary card
            summaryCard
        }
    }

    // MARK: - Kind chips

    private func kindChip(_ k: CampaignScheduleKind) -> some View {
        Button { kind = k } label: {
            Label(k.displayName, systemImage: k.systemImage)
                .font(.brandLabelLarge())
                .foregroundStyle(kind == k ? .bizarreOnOrange : .bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .background(
                    kind == k ? Color.bizarreOrange : Color.bizarreSurface2,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schedule: \(k.displayName)")
        .accessibilityAddTraits(kind == k ? .isSelected : [])
        .hoverEffect(.highlight)
    }

    // MARK: - Detail controls

    private var sendNowRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "paperplane.fill").foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Campaign sends immediately after approval.")
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var sendAtRow: some View {
        DatePicker(
            "Send at",
            selection: $sendAt,
            in: Date()...,
            displayedComponents: [.date, .hourAndMinute]
        )
        .accessibilityLabel("Send date and time")
    }

    private var recurringControls: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Picker("Frequency", selection: $recurrence.frequency) {
                ForEach(CampaignRecurrenceConfig.Frequency.allCases, id: \.self) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .accessibilityLabel("Recurrence frequency")

            if recurrence.frequency == .weekly || recurrence.frequency == .biweekly {
                Stepper(
                    "Day of week: \(dayName(recurrence.dayOfWeek ?? 2))",
                    value: Binding(
                        get: { recurrence.dayOfWeek ?? 2 },
                        set: { recurrence.dayOfWeek = $0 }
                    ),
                    in: 1...7
                )
                .accessibilityLabel("Day of week for recurring send")
            }

            if recurrence.frequency == .monthly || recurrence.frequency == .quarterly {
                Stepper(
                    "Day of month: \(recurrence.dayOfMonth ?? 1)",
                    value: Binding(
                        get: { recurrence.dayOfMonth ?? 1 },
                        set: { recurrence.dayOfMonth = $0 }
                    ),
                    in: 1...28
                )
                .accessibilityLabel("Day of month for recurring send")
            }

            HStack {
                Text("Send time")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Stepper(
                    "\(recurrence.sendHour):\(String(format: "%02d", recurrence.sendMinute))",
                    value: $recurrence.sendHour,
                    in: 0...23
                )
                .frame(maxWidth: 180)
            }

            DatePicker("Ends (optional)", selection: Binding(
                get: { recurrence.endsAt ?? Date().addingTimeInterval(86400 * 90) },
                set: { recurrence.endsAt = $0 }
            ), in: Date()..., displayedComponents: .date)
            .accessibilityLabel("Recurrence end date (optional)")
        }
    }

    private var triggeredControls: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Picker("Trigger event", selection: $trigger.event) {
                ForEach(CampaignTriggerConfig.TriggerEvent.allCases, id: \.self) { e in
                    Label(e.displayName, systemImage: e.systemImage).tag(e)
                }
            }
            .accessibilityLabel("Trigger event")

            Stepper(
                "Delay: \(abs(trigger.delayHours))h \(trigger.delayHours < 0 ? "before" : "after")",
                value: $trigger.delayHours,
                in: -72...168,
                step: 1
            )
            .accessibilityLabel("Send delay in hours relative to trigger event")
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(scheduleSummary)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schedule summary: \(scheduleSummary)")
    }

    private var scheduleSummary: String {
        switch kind {
        case .sendNow:   return "Sends immediately after approval"
        case .sendAt:    return "Sends \(sendAt.formatted(date: .abbreviated, time: .shortened))"
        case .recurring: return recurrence.summary
        case .triggered: return trigger.summary
        }
    }

    // MARK: - Helpers

    private func dayName(_ dow: Int) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard dow >= 1, dow <= 7 else { return "?" }
        return names[dow]
    }
}
