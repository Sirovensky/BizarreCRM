// §57 FieldServiceDashboardTile — reusable Dashboard tile for field techs.
// Shows next appointment, ETA, and a "Start" button.
// Used on Dashboard for users with fieldService role.

import SwiftUI
import Core
import Networking
import DesignSystem

// MARK: - FieldServiceDashboardTileViewModel

@MainActor
@Observable
public final class FieldServiceDashboardTileViewModel {

    public enum TileState: Sendable {
        case loading
        case noJobsToday
        case nextJob(appointment: Appointment, etaMinutes: Int?)
        case failed(String)
    }

    public private(set) var state: TileState = .loading

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let routeService: FieldServiceRouteService

    public init(api: APIClient, routeService: FieldServiceRouteService) {
        self.api = api
        self.routeService = routeService
    }

    public func load() async {
        state = .loading
        do {
            // BUGHUNT-2026-05-18: was `ISO8601DateFormatter().string(from: Date())`,
            // which emits a full `2026-05-18T10:30:45Z` timestamp for BOTH bounds.
            // The server filter then evaluates `start_time >= now AND start_time
            // <= now` — only appointments at that exact instant match, so the
            // tile permanently showed "no jobs today" even for users with full
            // calendars. Pass a date-only `YYYY-MM-DD`; the matching server fix
            // (leads.routes.ts list-appointments) end-of-day-expands the bound.
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(identifier: "UTC")
            let today = df.string(from: Date())
            let appointments = try await api.listAppointments(fromDate: today, toDate: today)
            let pending = appointments.filter { $0.status != "completed" && $0.status != "cancelled" }
            guard let next = pending.sorted(by: { ($0.startTime ?? "") < ($1.startTime ?? "") }).first else {
                state = .noJobsToday
                return
            }
            // ETA calculation would use route service with user's current location.
            // For tile display, show nil ETA until location is available.
            state = .nextJob(appointment: next, etaMinutes: nil)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: dashboard pull-to-refresh cancels load;
            // keep prior tile state visible.
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - FieldServiceDashboardTile

/// Dashboard tile shown to field technicians.
///
/// iPhone: compact card row.
/// iPad: wider card with more detail visible.
public struct FieldServiceDashboardTile: View {

    @State private var vm: FieldServiceDashboardTileViewModel
    public var onStart: ((Appointment) -> Void)?

    public init(
        vm: FieldServiceDashboardTileViewModel,
        onStart: ((Appointment) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: vm)
        self.onStart = onStart
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                tileShell {
                    HStack {
                        ProgressView()
                        Text("Loading jobs…")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.secondary)
                    }
                }
            case .noJobsToday:
                tileShell {
                    Label("No jobs scheduled today", systemImage: "calendar.badge.checkmark")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.secondary)
                }
            case .nextJob(let appt, let eta):
                nextJobTile(appt: appt, eta: eta)
            case .failed:
                tileShell {
                    Button("Retry") { Task { await vm.load() } }
                        .font(.brandBodyMedium())
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Next job tile

    private func nextJobTile(appt: Appointment, eta: Int?) -> some View {
        tileShell {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Next Job")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                    Text(appt.title ?? "Appointment #\(appt.id)")
                        .font(.brandTitleMedium())
                        .lineLimit(1)
                    if let customer = appt.customerName {
                        Text(customer)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
                    if let eta {
                        Text("\(eta) min")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnOrange)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(Color.bizarreOrange, in: Capsule())
                    }
                    Button("Start") { onStart?(appt) }
                        .buttonStyle(.brandGlass)
                        .font(.brandLabelSmall())
                        .accessibilityHint("Navigates to the job map and check-in flow")
                }
            }
        }
    }

    // MARK: - Shell

    @ViewBuilder
    private func tileShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}
