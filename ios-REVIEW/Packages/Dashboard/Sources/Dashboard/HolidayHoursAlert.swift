import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - §3 Holiday Hours Alert
//
// Shows a glass banner when today is a configured holiday or the shop has
// modified hours today. Fetches GET /api/v1/store/hours/today which returns
// whether today is a holiday, the holiday name, and effective open/close times.
//
// The banner is dismissible per day via UserDefaults. If the endpoint is absent
// (404) or returns no holiday, the view hides itself — zero noise for normal days.

// MARK: - Model

public struct TodayHoursPayload: Decodable, Sendable {
    /// Whether the shop is closed all day for a holiday / special closure.
    public let isHoliday: Bool
    /// Human-readable holiday name (e.g. "Thanksgiving", "Memorial Day").
    public let holidayName: String?
    /// Whether hours are modified today (not a holiday but different schedule).
    public let isModifiedHours: Bool
    /// Effective open time string ("09:00", "HH:mm"). Nil = closed all day.
    public let openTime: String?
    /// Effective close time string ("17:00", "HH:mm"). Nil = closed all day.
    public let closeTime: String?

    public init(isHoliday: Bool = false, holidayName: String? = nil,
                isModifiedHours: Bool = false,
                openTime: String? = nil, closeTime: String? = nil) {
        self.isHoliday = isHoliday
        self.holidayName = holidayName
        self.isModifiedHours = isModifiedHours
        self.openTime = openTime
        self.closeTime = closeTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isHoliday       = (try? c.decode(Bool.self,   forKey: .isHoliday))       ?? false
        self.holidayName     =  try? c.decode(String.self, forKey: .holidayName)
        self.isModifiedHours = (try? c.decode(Bool.self,   forKey: .isModifiedHours)) ?? false
        self.openTime        =  try? c.decode(String.self, forKey: .openTime)
        self.closeTime       =  try? c.decode(String.self, forKey: .closeTime)
    }

    enum CodingKeys: String, CodingKey {
        case isHoliday       = "is_holiday"
        case holidayName     = "holiday_name"
        case isModifiedHours = "is_modified_hours"
        case openTime        = "open_time"
        case closeTime       = "close_time"
    }

    /// True when the banner should show.
    public var needsAlert: Bool { isHoliday || isModifiedHours }

    public var bannerTitle: String {
        if isHoliday {
            return holidayName.map { "Holiday: \($0)" } ?? "Holiday Closure"
        }
        return "Modified Hours Today"
    }

    public var bannerBody: String {
        if let open = openTime, let close = closeTime {
            return "Today's hours: \(open) – \(close). Staff and customer-facing messages may need updating."
        }
        if isHoliday {
            return "The shop is closed today. Scheduled messages will still send — review your automation."
        }
        return "Your shop has non-standard hours today. Update customer-facing channels if needed."
    }

    public var icon: String {
        isHoliday ? "star.circle.fill" : "clock.badge.exclamationmark.fill"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class HolidayHoursAlertViewModel {
    public enum State: Sendable {
        case loading
        case visible(TodayHoursPayload)
        case hidden
    }

    public private(set) var state: State = .loading
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    private static func dismissKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "holiday.hours.dismissed.\(f.string(from: Date()))"
    }

    public func load() async {
        guard case .loading = state else { return }
        // If already dismissed today, skip the network call.
        if UserDefaults.standard.bool(forKey: Self.dismissKey()) {
            state = .hidden
            return
        }
        do {
            let payload = try await api.get(
                "/api/v1/store/hours/today",
                as: TodayHoursPayload.self
            )
            state = payload.needsAlert ? .visible(payload) : .hidden
        } catch {
            state = .hidden
        }
    }

    public func dismiss() {
        UserDefaults.standard.set(true, forKey: Self.dismissKey())
        state = .hidden
    }
}

// MARK: - View

public struct HolidayHoursAlert: View {
    @State private var vm: HolidayHoursAlertViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: HolidayHoursAlertViewModel(api: api))
    }

    public var body: some View {
        switch vm.state {
        case .loading, .hidden:
            EmptyView()
        case .visible(let payload):
            AlertCard(payload: payload, onDismiss: { vm.dismiss() })
                .task { /* already loaded */ }
        }
    }
}

// MARK: - AlertCard

private struct AlertCard: View {
    let payload: TodayHoursPayload
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: payload.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(payload.isHoliday ? Color.bizarreWarning : Color.bizarreOrange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.bannerTitle)
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Text(payload.bannerBody)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss holiday hours alert")
        }
        .padding(BrandSpacing.md)
        .background(
            Color.bizarreWarning.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(payload.bannerTitle). \(payload.bannerBody). Dismiss button available.")
    }
}
