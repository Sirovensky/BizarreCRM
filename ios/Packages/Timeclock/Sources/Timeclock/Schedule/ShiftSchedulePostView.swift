import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - ShiftSchedulePostViewModel

@MainActor
@Observable
public final class ShiftSchedulePostViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }
    public enum PublishState: Sendable, Equatable {
        case idle, publishing, published, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var publishState: PublishState = .idle
    public private(set) var shifts: [ScheduledShift] = []
    public private(set) var conflicts: [ScheduleConflict] = []
    public var weekStart: String = currentWeekStartISO()

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ptoBlocks: [PTOBlock]

    public init(api: APIClient, ptoBlocks: [PTOBlock] = []) {
        self.api = api
        self.ptoBlocks = ptoBlocks
    }

    public func load() async {
        loadState = .loading
        do {
            let loaded = try await api.getSchedule(weekStart: weekStart)
            shifts = loaded
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func addShift(body: CreateScheduledShiftBody) async {
        let newConflicts = ShiftScheduleConflictChecker.check(
            proposed: body,
            existingShifts: shifts,
            ptoBlocks: ptoBlocks
        )
        if !newConflicts.isEmpty {
            conflicts = newConflicts
            return
        }
        do {
            let shift = try await api.createScheduledShift(body: body)
            shifts = shifts + [shift]
            conflicts = []
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func publish() async {
        publishState = .publishing
        do {
            try await api.publishSchedule(weekStart: weekStart)
            publishState = .published
        } catch {
            publishState = .failed(error.localizedDescription)
        }
    }

    private static func currentWeekStartISO() -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        return ISO8601DateFormatter().string(from: start)
    }
}

// MARK: - ShiftSchedulePostView

/// Manager view: weekly schedule grid with add-shift and publish.
///
/// iPad: 7-column grid with drag-drop (simplified placeholder for now).
/// iPhone: list grouped by day.
/// Liquid Glass on toolbar + publish banner.
public struct ShiftSchedulePostView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var vm: ShiftSchedulePostViewModel
    @State private var showingAddSheet = false

    public init(vm: ShiftSchedulePostViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
            .navigationTitle("Week Schedule")
            .toolbar { scheduleToolbar }
            .task { await vm.load() }
            .safeAreaInset(edge: .bottom) {
                publishBanner
            }
            .sheet(isPresented: $showingAddSheet) {
                AddShiftSheet(onAdd: { body in
                    Task { await vm.addShift(body: body) }
                })
            }
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        List {
            ForEach(vm.shifts) { shift in
                ScheduledShiftRow(shift: shift)
            }
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    private var iPadLayout: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: [GridItem(.flexible())], spacing: DesignTokens.Spacing.md) {
                ForEach(vm.shifts) { shift in
                    ScheduledShiftRow(shift: shift)
                        .frame(width: 160)
                        .brandHover()
                }
            }
            .padding()
        }
        .overlay { stateOverlay }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var scheduleToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add Shift", systemImage: "plus") {
                showingAddSheet = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add new shift")
        }
    }

    // MARK: - Publish banner

    @ViewBuilder
    private var publishBanner: some View {
        if case .published = vm.publishState {
            ShiftPublishBanner()
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
        } else if !vm.conflicts.isEmpty {
            ConflictBanner(conflicts: vm.conflicts)
        } else {
            Button("Publish Week") {
                Task { await vm.publish() }
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
            .padding()
            .disabled(vm.publishState == .publishing)
            .accessibilityLabel("Publish schedule for this week")
        }
    }

    // MARK: - State overlay

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading schedule…")
        case let .failed(msg):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(msg))
        default:
            EmptyView()
        }
    }
}

// MARK: - ScheduledShiftRow

private struct ScheduledShiftRow: View {
    let shift: ScheduledShift

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Employee \(shift.employeeId)")
                .font(.caption.weight(.semibold))
            Text("\(shift.startAt) → \(shift.endAt)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let role = shift.role {
                Text(role).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shift for employee \(shift.employeeId) from \(shift.startAt) to \(shift.endAt)")
    }
}

// MARK: - ConflictBanner

private struct ConflictBanner: View {
    let conflicts: [ScheduleConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Label("Schedule Conflicts", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            ForEach(conflicts.indices, id: \.self) { idx in
                Text(description(for: conflicts[idx]))
                    .font(.caption)
            }
        }
        .padding()
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schedule conflicts detected")
    }

    private func description(for conflict: ScheduleConflict) -> String {
        switch conflict {
        case let .doubleBooking(empId, shiftId, _, _):
            return "Employee \(empId) is already scheduled (shift \(shiftId))"
        case let .ptoOverlap(empId, desc):
            return "Employee \(empId) has PTO: \(desc)"
        }
    }
}

// MARK: - AddShiftSheet (minimal)

private struct AddShiftSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (CreateScheduledShiftBody) -> Void
    @State private var employeeId: Int64 = 0
    @State private var startAt: String = ""
    @State private var endAt: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Employee ID", value: $employeeId, format: .number)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .accessibilityLabel("Employee ID")
                TextField("Start (ISO-8601)", text: $startAt)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Shift start time")
                TextField("End (ISO-8601)", text: $endAt)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Shift end time")
            }
            .navigationTitle("Add Shift")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let body = CreateScheduledShiftBody(
                            employeeId: employeeId,
                            startAt: startAt,
                            endAt: endAt
                        )
                        onAdd(body)
                        dismiss()
                    }
                    .disabled(employeeId == 0 || startAt.isEmpty || endAt.isEmpty)
                    .accessibilityLabel("Add shift to schedule")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
