import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - §3 Appointments-Today Widget
//
// Compact card on the dashboard showing today's appointment count and the
// next upcoming appointment's customer name + time. Fetches
// GET /api/v1/leads/appointments?date=<today> (ISO 8601 date param).
// Hides itself on 404 or empty — no clutter for shops that don't use
// appointments.
//
// Tap → deep-links to bizarrecrm://appointments (the appointments list
// filtered to today). When `onTapAppointments` is provided the host handles
// navigation; otherwise openURL is used as a fallback.

// MARK: - ViewModel

@MainActor
@Observable
public final class AppointmentsTodayViewModel {
    public enum State: Sendable {
        case loading
        case loaded([Appointment])
        case hidden   // no appointments today, or endpoint absent
    }

    public private(set) var state: State = .loading
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        guard case .loading = state else { return }
        do {
            let today = Self.todayISO()
            let query = [URLQueryItem(name: "date", value: today)]
            let resp = try await api.get(
                "/api/v1/leads/appointments",
                query: query,
                as: AppointmentsListResponse.self
            )
            // Sort by start_time ascending so the soonest is first.
            let sorted = resp.appointments.sorted {
                ($0.startTime ?? "") < ($1.startTime ?? "")
            }
            state = sorted.isEmpty ? .hidden : .loaded(sorted)
        } catch {
            state = .hidden
        }
    }

    /// ISO 8601 local-calendar date string (YYYY-MM-DD) for today.
    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// MARK: - View

public struct AppointmentsTodayWidget: View {
    @State private var vm: AppointmentsTodayViewModel
    public var onTapAppointments: (() -> Void)?

    @Environment(\.openURL) private var openURL

    public init(api: APIClient, onTapAppointments: (() -> Void)? = nil) {
        _vm = State(wrappedValue: AppointmentsTodayViewModel(api: api))
        self.onTapAppointments = onTapAppointments
    }

    public var body: some View {
        switch vm.state {
        case .loading, .hidden:
            EmptyView()
        case .loaded(let appts):
            AppointmentsTodayCard(appointments: appts) {
                if let handler = onTapAppointments {
                    BrandHaptics.selection()
                    handler()
                } else if let url = URL(string: "bizarrecrm://appointments") {
                    BrandHaptics.selection()
                    openURL(url)
                }
            }
            .task { /* already loaded */ }
        }
    }
}

// MARK: - Card

private struct AppointmentsTodayCard: View {
    let appointments: [Appointment]
    let onTap: () -> Void

    private var next: Appointment? { appointments.first }

    private var formattedTime: String? {
        guard let raw = next?.startTime else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: raw) ?? iso2.date(from: raw) else { return nil }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.bizarreOrange.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Appointments Today")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text("\(appointments.count)")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    if let nextName = next?.customerName ?? next?.title,
                       let time = formattedTime {
                        Text("Next: \(nextName) at \(time)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityLabel("Appointments today: \(appointments.count). Tap to view.")
        .accessibilityHint("Opens the appointments list for today.")
    }
}
