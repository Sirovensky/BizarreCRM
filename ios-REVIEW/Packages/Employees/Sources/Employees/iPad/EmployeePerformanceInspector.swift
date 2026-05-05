#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §22 — iPad trailing inspector: employee performance metrics
//
// Loaded lazily when an employee is selected in the three-column layout.
// The inspector fetches performance data independently so the detail view
// remains responsive during the extra load.
//
// Layout:
// ┌─────────────────────┐
// │  PERFORMANCE        │   Glass section header
// │  Tickets   42       │
// │  Closed    38       │
// │  Revenue   $12,340  │
// │  Avg/ticket $293    │
// ├─────────────────────┤
// │  DEVICES            │
// │  Repaired  24       │
// │  Avg Time  2.3h     │
// ├─────────────────────┤
// │  SHIFT              │
// │  Status    Clocked In│
// │  Since     09:14 AM │
// └─────────────────────┘

// MARK: - EmployeePerformanceInspectorViewModel

/// Testable view-model extracted from `EmployeePerformanceInspector`.
/// Holds load-state independently of SwiftUI rendering.
@MainActor
@Observable
public final class EmployeePerformanceInspectorViewModel {

    // MARK: - State

    public enum State: Sendable {
        case loading
        case loaded(EmployeePerformance)
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var clockedIn: Bool = false
    public private(set) var clockInTime: String? = nil

    @ObservationIgnored private let employeeId: Int64
    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(employeeId: Int64, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        state = .loading
        do {
            async let perfFetch   = api.getEmployeePerformance(id: employeeId)
            async let detailFetch = api.getEmployee(id: employeeId)
            let (perf, detail) = try await (perfFetch, detailFetch)
            state = .loaded(perf)
            clockedIn = detail.isClockedIn ?? false
            clockInTime = detail.currentClockEntry?.clockIn
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Test seam

    /// Sets state directly without making network calls. For unit tests only.
    public func setState(_ newState: State) {
        state = newState
    }

    // MARK: - Computed helpers

    /// Formats a currency value as USD.
    public func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// Formats elapsed time from an ISO-8601 clock-in string.
    public func elapsedSince(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return "—" }
        let secs = Int(Date().timeIntervalSince(date))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    /// Formats a short display time from an ISO-8601 string.
    public func shortTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.timeStyle = .short
        display.dateStyle = .none
        return display.string(from: date)
    }
}

// MARK: - EmployeePerformanceInspector

/// Trailing-column inspector showing live performance metrics for
/// the selected employee in the three-column iPad layout.
public struct EmployeePerformanceInspector: View {

    // MARK: - State

    @State private var vm: EmployeePerformanceInspectorViewModel

    // MARK: - Init

    public init(employeeId: Int64, api: APIClient) {
        _vm = State(wrappedValue: EmployeePerformanceInspectorViewModel(
            employeeId: employeeId,
            api: api
        ))
    }

    /// Internal init for preview / test injection.
    init(viewModel: EmployeePerformanceInspectorViewModel) {
        _vm = State(wrappedValue: viewModel)
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                switch vm.state {
                case .loading:
                    loadingPlaceholder
                case .loaded(let perf):
                    inspectorContent(perf)
                case .failed(let msg):
                    errorView(message: msg)
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: - Content

    private func inspectorContent(_ perf: EmployeePerformance) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                ticketsSection(perf)

                Divider()
                    .overlay(Color.bizarreOnSurfaceMuted.opacity(0.2))

                devicesSection(perf)

                Divider()
                    .overlay(Color.bizarreOnSurfaceMuted.opacity(0.2))

                shiftSection
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Tickets section

    private func ticketsSection(_ perf: EmployeePerformance) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Tickets & Revenue", icon: "ticket")

            metricsRow(
                label: "Total Tickets",
                value: "\(perf.totalTickets)",
                icon: "ticket"
            )
            metricsRow(
                label: "Closed",
                value: "\(perf.closedTickets)",
                icon: "checkmark.circle"
            )

            Divider().overlay(Color.bizarreOnSurfaceMuted.opacity(0.15))

            metricsRow(
                label: "Revenue",
                value: vm.formatMoney(perf.totalRevenue),
                icon: "dollarsign.circle",
                valueColor: .bizarreSuccess
            )
            metricsRow(
                label: "Avg / Ticket",
                value: vm.formatMoney(perf.avgTicketValue),
                icon: "chart.bar"
            )
        }
    }

    // MARK: - Devices section

    private func devicesSection(_ perf: EmployeePerformance) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Devices", icon: "wrench.and.screwdriver")

            metricsRow(
                label: "Repaired",
                value: "\(perf.totalDevicesRepaired)",
                icon: "wrench"
            )

            if let avgHours = perf.avgRepairHours {
                metricsRow(
                    label: "Avg Repair Time",
                    value: String(format: "%.1fh", avgHours),
                    icon: "clock"
                )
            } else {
                metricsRow(
                    label: "Avg Repair Time",
                    value: "—",
                    icon: "clock"
                )
            }
        }
    }

    // MARK: - Shift section

    private var shiftSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Current Shift", icon: "clock.badge")

            if vm.clockedIn, let clockIn = vm.clockInTime {
                metricsRow(
                    label: "Status",
                    value: "Clocked In",
                    icon: "circle.fill",
                    valueColor: .green
                )
                metricsRow(
                    label: "Since",
                    value: vm.shortTime(clockIn),
                    icon: "clock"
                )
                metricsRow(
                    label: "Elapsed",
                    value: vm.elapsedSince(clockIn),
                    icon: "timer"
                )
            } else {
                metricsRow(
                    label: "Status",
                    value: "Not clocked in",
                    icon: "circle",
                    valueColor: .bizarreOnSurfaceMuted
                )
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.6)
        }
        .padding(.bottom, BrandSpacing.xxs)
    }

    // MARK: - Metrics row

    private func metricsRow(
        label: String,
        value: String,
        icon: String,
        valueColor: Color = .bizarreOnSurface
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .labelStyle(.iconOnly)
                .accessibilityHidden(true)
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .bold()
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Loading / error

    private var loadingPlaceholder: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
            Text("Loading metrics…")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading performance metrics")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load metrics")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Retry loading metrics")
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
