import WidgetKit
import Foundation

// MARK: - §24.9 Smart Stack relevance hints + ReloadTimeline on significant events
//
// `TimelineRelevance` donates time-window + score to WidgetKit so the Smart Stack
// can auto-promote the most contextually relevant widget without user intervention.
//
// Rules (§24.9):
//   - Morning (06:00-09:00) → DashboardMirror promoted (score 0.9)
//   - POS window (10:00-18:00) → TodaysRevenue promoted (score 0.8)
//   - End-of-shift (17:30-18:30) → ClockInOut widget / Live Activity reminder (score 0.7)
//   - Outside windows → neutral (score 0.2)
//
// ReloadTimeline: call `WidgetReloader.shared.reloadOnSignificantEvent()` from the
// main app whenever a ticket changes status, payment is received, or schedule is updated.

// MARK: - SmartStackRelevanceProvider

/// Computes `TimelineRelevance` windows for any widget that wants Smart Stack promotion.
///
/// Usage inside `getTimeline(in:completion:)`:
/// ```swift
/// let relevance = SmartStackRelevanceProvider.relevance(for: .dashboard, now: .now)
/// let entry = MyEntry(date: date, relevance: relevance)
/// ```
public enum SmartStackRelevanceProvider {

    public enum WidgetContext {
        case dashboard
        case revenue
        case clockInOut
        case tickets
        case appointments
    }

    /// Returns a `TimelineRelevance` appropriate for the given context and current time.
    public static func relevance(for context: WidgetContext, now: Date = .now) -> TimelineRelevance {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minuteOfDay = hour * 60 + minute

        switch context {
        case .dashboard:
            // Promote during morning briefing window (06:00–09:00)
            let startMinute = 6 * 60       // 360
            let endMinute   = 9 * 60       // 540
            if minuteOfDay >= startMinute && minuteOfDay < endMinute {
                let windowEnd = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
                return TimelineRelevance(score: 0.9, duration: windowEnd.timeIntervalSince(now))
            }
            return TimelineRelevance(score: 0.2, duration: 3600)

        case .revenue:
            // Promote during peak POS window (10:00–18:00)
            let startMinute = 10 * 60
            let endMinute   = 18 * 60
            if minuteOfDay >= startMinute && minuteOfDay < endMinute {
                let windowEnd = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
                return TimelineRelevance(score: 0.8, duration: windowEnd.timeIntervalSince(now))
            }
            return TimelineRelevance(score: 0.2, duration: 3600)

        case .clockInOut:
            // Promote at end-of-shift (17:30–18:30)
            let startMinute = 17 * 60 + 30
            let endMinute   = 18 * 60 + 30
            if minuteOfDay >= startMinute && minuteOfDay < endMinute {
                let windowEnd = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: now) ?? now
                return TimelineRelevance(score: 0.7, duration: windowEnd.timeIntervalSince(now))
            }
            return TimelineRelevance(score: 0.1, duration: 3600)

        case .tickets:
            // Tickets relevant all day during business hours
            let startMinute = 8 * 60
            let endMinute   = 20 * 60
            if minuteOfDay >= startMinute && minuteOfDay < endMinute {
                return TimelineRelevance(score: 0.6, duration: 3600)
            }
            return TimelineRelevance(score: 0.1, duration: 3600)

        case .appointments:
            // Appointments most relevant 1h before opening and 1h after closing
            let morningMinute = 7 * 60
            let eveningMinute = 17 * 60
            if (minuteOfDay >= morningMinute && minuteOfDay < morningMinute + 120) ||
               (minuteOfDay >= eveningMinute && minuteOfDay < eveningMinute + 120) {
                return TimelineRelevance(score: 0.75, duration: 7200)
            }
            return TimelineRelevance(score: 0.2, duration: 3600)
        }
    }
}

// MARK: - WidgetReloader

/// Called from the main app target to trigger `WidgetCenter` reloads on significant events.
///
/// Usage from main app (e.g., after a ticket status change):
/// ```swift
/// WidgetReloader.shared.reloadOnSignificantEvent(.ticketChanged)
/// ```
public final class WidgetReloader {

    public static let shared = WidgetReloader()
    private init() {}

    public enum SignificantEvent {
        case ticketChanged
        case paymentReceived
        case scheduleUpdated
        case clockInOut
        case stockChanged
    }

    /// Reload the relevant widget kinds after a significant event.
    /// Each event maps to a targeted reload rather than reloading everything.
    public func reloadOnSignificantEvent(_ event: SignificantEvent) {
        let kinds = widgetKinds(for: event)
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }

    /// Reload all timelines (use sparingly — prefer targeted reloads).
    public func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Mapping

    private func widgetKinds(for event: SignificantEvent) -> [String] {
        switch event {
        case .ticketChanged:
            return [
                "com.bizarrecrm.widget.openTickets",
                "com.bizarrecrm.widget.dashboard"
            ]
        case .paymentReceived:
            return [
                "com.bizarrecrm.widget.todaysRevenue",
                "com.bizarrecrm.widget.dashboard"
            ]
        case .scheduleUpdated:
            return [
                "com.bizarrecrm.widget.appointmentsNext",
                "com.bizarrecrm.widget.dashboard"
            ]
        case .clockInOut:
            return [
                "com.bizarrecrm.widget.configurableKPI"
            ]
        case .stockChanged:
            return [
                "com.bizarrecrm.widget.dashboard"
            ]
        }
    }
}
