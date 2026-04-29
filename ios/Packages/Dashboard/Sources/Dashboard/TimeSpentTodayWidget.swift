import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - §3 Time Spent Today Widget
//
// Shows hours worked by the signed-in employee today, sourced from
// GET /api/v1/employees/:id/timeclock/today
// Response: { clock_in_at: ISO8601?, total_minutes: Int, is_clocked_in: Bool }
//
// Designed to complement the ClockInOutTile (§3.11) without duplicating
// controls. Read-only; live-ticks every 60s while clocked in.

// MARK: - Model

public struct TimeclockTodayData: Decodable, Sendable {
    public let clockInAt: Date?
    public let totalMinutes: Int      // minutes accumulated before the current session
    public let isClockedIn: Bool

    public init(clockInAt: Date? = nil, totalMinutes: Int = 0, isClockedIn: Bool = false) {
        self.clockInAt = clockInAt
        self.totalMinutes = totalMinutes
        self.isClockedIn = isClockedIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.totalMinutes = (try? c.decode(Int.self,  forKey: .totalMinutes)) ?? 0
        self.isClockedIn  = (try? c.decode(Bool.self, forKey: .isClockedIn)) ?? false

        if let raw = try? c.decode(String.self, forKey: .clockInAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.clockInAt = iso.date(from: raw)
        } else {
            self.clockInAt = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case clockInAt     = "clock_in_at"
        case totalMinutes  = "total_minutes"
        case isClockedIn   = "is_clocked_in"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TimeSpentTodayViewModel {
    public enum State: Sendable {
        case loading
        case loaded(TimeclockTodayData)
        case unavailable   // hide widget (endpoint absent / user not a time-tracked employee)
    }

    public private(set) var state: State = .loading
    /// Live clock: minutes elapsed since clockInAt (added on top of totalMinutes)
    public private(set) var liveMinutes: Int = 0

    private let api: APIClient
    private let userId: Int64
    private var tickTask: Task<Void, Never>?

    public init(api: APIClient, userId: Int64) {
        self.api = api
        self.userId = userId
    }

    deinit { tickTask?.cancel() }

    public func load() async {
        guard case .loading = state else { return }
        do {
            let data = try await api.get(
                "/api/v1/employees/\(userId)/timeclock/today",
                as: TimeclockTodayData.self
            )
            state = .loaded(data)
            startTicking(data: data)
        } catch {
            state = .unavailable
        }
    }

    private func startTicking(data: TimeclockTodayData) {
        tickTask?.cancel()
        guard data.isClockedIn, let clockInAt = data.clockInAt else {
            liveMinutes = data.totalMinutes
            return
        }
        liveMinutes = data.totalMinutes + Int(Date().timeIntervalSince(clockInAt) / 60)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, case .loaded(let d) = self.state,
                      let cin = d.clockInAt else { break }
                self.liveMinutes = d.totalMinutes + Int(Date().timeIntervalSince(cin) / 60)
            }
        }
    }
}

// MARK: - View

public struct TimeSpentTodayWidget: View {
    @State private var vm: TimeSpentTodayViewModel

    public init(api: APIClient, userId: Int64) {
        _vm = State(wrappedValue: TimeSpentTodayViewModel(api: api, userId: userId))
    }

    public var body: some View {
        switch vm.state {
        case .loading:
            EmptyView()
        case .unavailable:
            EmptyView()
        case .loaded(let data):
            WidgetCard(data: data, liveMinutes: vm.liveMinutes)
        }
    }
}

// MARK: - WidgetCard

private struct WidgetCard: View {
    let data: TimeclockTodayData
    let liveMinutes: Int

    private var formattedDuration: String {
        let h = liveMinutes / 60
        let m = liveMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private var statusLabel: String {
        data.isClockedIn ? "Clocked in · live" : "Today's total"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.bizarreOrange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: data.isClockedIn ? "clock.fill" : "clock")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Time Spent Today")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(formattedDuration)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    if data.isClockedIn {
                        Circle()
                            .fill(Color.bizarreSuccess)
                            .frame(width: 6, height: 6)
                    }
                    Text(statusLabel)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time spent today: \(formattedDuration). \(statusLabel).")
    }
}
