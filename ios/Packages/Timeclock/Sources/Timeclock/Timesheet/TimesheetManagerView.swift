import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimesheetManagerViewModel

@MainActor
@Observable
public final class TimesheetManagerViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var timesheets: [TimesheetResponse] = []
    public var selectedEmployeeId: Int64? = nil
    public var period: PayPeriod = .currentWeek()

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let rules: OvertimeRules

    public init(api: APIClient, rules: OvertimeRules = .federal) {
        self.api = api
        self.rules = rules
    }

    public func load() async {
        loadState = .loading
        do {
            let result = try await api.getTeamTimesheets(period: period, employeeId: selectedEmployeeId)
            timesheets = result
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func overtimeFor(response: TimesheetResponse) -> OvertimeBreakdown {
        OvertimeCalculator.compute(shifts: response.shifts, breaks: response.breaks, rules: rules)
    }
}

// MARK: - TimesheetManagerView

/// Manager view — team timesheets with employee + period filter.
///
/// iPad: `Table` with sortable columns. iPhone: `List` rows.
public struct TimesheetManagerView: View {

    @Bindable var vm: TimesheetManagerViewModel

    public init(vm: TimesheetManagerViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Team Timesheets")
        .toolbar { filterToolbar }
        .task { await vm.load() }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        List {
            ForEach(vm.timesheets, id: \.self.shifts.first?.employeeId) { ts in
                Section {
                    ForEach(ts.shifts) { shift in
                        ShiftManagerRow(shift: shift)
                    }
                } header: {
                    Text("Employee \(ts.shifts.first?.employeeId ?? 0)")
                }
            }
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    private var iPadLayout: some View {
        Table(vm.timesheets.flatMap(\.shifts)) {
            TableColumn("Employee") { shift in
                Text("\(shift.employeeId)")
                    .textSelection(.enabled)
            }
            TableColumn("Clock In") { shift in
                Text(shift.clockIn)
                    .textSelection(.enabled)
            }
            TableColumn("Clock Out") { shift in
                Text(shift.clockOut ?? "–")
                    .textSelection(.enabled)
            }
            TableColumn("Duration") { shift in
                Text(shift.totalMinutes.map { "\($0 / 60)h \($0 % 60)m" } ?? "–")
            }
        }
        .overlay { stateOverlay }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Refresh") {
                Task { await vm.load() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Refresh team timesheets")
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading team timesheets…")
                .accessibilityLabel("Loading team timesheets")
        case let .failed(msg):
            ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle", description: Text(msg))
        default:
            EmptyView()
        }
    }
}

// MARK: - ShiftManagerRow

private struct ShiftManagerRow: View {
    let shift: Shift

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Employee \(shift.employeeId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(shift.clockIn) → \(shift.clockOut ?? "open")")
                    .font(.subheadline)
            }
            Spacer()
            if let dur = shift.totalMinutes {
                Text("\(dur / 60)h \(dur % 60)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shift for employee \(shift.employeeId), \(shift.clockIn) to \(shift.clockOut ?? "open")")
        .brandHover()
        .contextMenu {
            Button("Edit shift…") { /* opens TimesheetEditSheet */ }
        }
    }
}
