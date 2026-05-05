import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - PayPeriod

public struct PayPeriod: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public static func currentWeek(calendar: Calendar = .autoupdatingCurrent) -> PayPeriod {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        return PayPeriod(start: start, end: end)
    }

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

// MARK: - TimesheetViewModel

@MainActor
@Observable
public final class TimesheetViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var shifts: [Shift] = []
    public private(set) var breaks: [BreakEntry] = []
    public private(set) var overtimeBreakdown: OvertimeBreakdown?
    public var period: PayPeriod = .currentWeek()

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var userIdProvider: @Sendable () async -> Int64
    @ObservationIgnored private let rules: OvertimeRules

    public init(
        api: APIClient,
        userIdProvider: @escaping @Sendable () async -> Int64 = { 0 },
        rules: OvertimeRules = .federal
    ) {
        self.api = api
        self.userIdProvider = userIdProvider
        self.rules = rules
    }

    public func load() async {
        loadState = .loading
        let userId = await userIdProvider()
        do {
            let result = try await api.getTimesheet(employeeId: userId, period: period)
            let newShifts = result.shifts
            let newBreaks = result.breaks
            let breakdown = OvertimeCalculator.compute(
                shifts: newShifts,
                breaks: newBreaks,
                rules: rules
            )
            shifts = newShifts
            breaks = newBreaks
            overtimeBreakdown = breakdown
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - TimesheetView

/// Employee's own timesheet for the current pay period.
///
/// A11y: each row has a full VoiceOver label with clock-in/out times and
/// duration. Dynamic Type is honored via system font scaling.
public struct TimesheetView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var vm: TimesheetViewModel

    public init(vm: TimesheetViewModel) {
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
        .navigationTitle("My Timesheet")
        .task { await vm.load() }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            if let breakdown = vm.overtimeBreakdown {
                Section("Overtime Summary") {
                    overtimeSummaryRows(breakdown)
                }
            }
            Section("Shifts") {
                shiftRows
            }
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            List {
                Section("Shifts") {
                    shiftRows
                }
            }
            .frame(maxWidth: 420)

            if let breakdown = vm.overtimeBreakdown {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("Overtime Summary")
                        .font(.headline)
                        .padding(.horizontal)
                    overtimeSummaryRows(breakdown)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, DesignTokens.Spacing.lg)
            }
        }
        .overlay { stateOverlay }
    }

    // MARK: - Shared subviews

    @ViewBuilder
    private var shiftRows: some View {
        ForEach(vm.shifts) { shift in
            ShiftRowView(shift: shift, breaks: vm.breaks.filter { $0.shiftId == shift.id })
        }
    }

    @ViewBuilder
    private func overtimeSummaryRows(_ breakdown: OvertimeBreakdown) -> some View {
        OvertimeSummaryRow(label: "Regular", minutes: breakdown.regularMinutes)
        OvertimeSummaryRow(label: "Overtime (1.5×)", minutes: breakdown.overtimeMinutes)
        OvertimeSummaryRow(label: "Double-time (2×)", minutes: breakdown.doubleTimeMinutes)
        OvertimeSummaryRow(label: "Holiday", minutes: breakdown.holidayMinutes)
        OvertimeSummaryRow(label: "Total", minutes: breakdown.totalMinutes, isTotal: true)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading timesheet…")
                .accessibilityLabel("Loading timesheet")
        case let .failed(msg):
            ContentUnavailableView("Failed to load", systemImage: "exclamationmark.triangle", description: Text(msg))
        default:
            EmptyView()
        }
    }
}

// MARK: - ShiftRowView

private struct ShiftRowView: View {
    let shift: Shift
    let breaks: [BreakEntry]

    private static let isoFormatter = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(clockInDisplay)
                    .font(.subheadline.weight(.medium))
                Text("→")
                    .foregroundStyle(.secondary)
                Text(clockOutDisplay)
                    .font(.subheadline)
            }
            if let dur = shift.totalMinutes {
                Text(formatDuration(dur))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !breaks.isEmpty {
                Text("\(breaks.count) break(s)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var clockInDisplay: String {
        guard let d = Self.isoFormatter.date(from: shift.clockIn) else { return shift.clockIn }
        return Self.timeFormatter.string(from: d)
    }

    private var clockOutDisplay: String {
        guard let out = shift.clockOut, let d = Self.isoFormatter.date(from: out) else { return "–" }
        return Self.timeFormatter.string(from: d)
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private var accessibilityLabel: String {
        "Shift: clocked in at \(clockInDisplay), clocked out at \(clockOutDisplay)"
            + (shift.totalMinutes.map { ", \(formatDuration($0)) total" } ?? "")
    }
}

// MARK: - OvertimeSummaryRow

private struct OvertimeSummaryRow: View {
    let label: String
    let minutes: Int
    var isTotal: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(isTotal ? .subheadline.weight(.semibold) : .subheadline)
            Spacer()
            Text(formattedHours)
                .font(isTotal ? .subheadline.weight(.semibold) : .subheadline)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formattedHours)")
    }

    private var formattedHours: String {
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
