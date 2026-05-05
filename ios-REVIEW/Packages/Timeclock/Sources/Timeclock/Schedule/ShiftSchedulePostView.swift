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
    /// §14.6 drag-drop: local display sort order (indices into `shifts`).
    /// iPad drag-drop updates this array; server order unchanged (sorted by time).
    public private(set) var sortedIndices: [Int] = []

    @ObservationIgnored private let api: APIClient
    /// §14.9 — PTO blocks used for conflict checking. Mutable so approved PTO
    /// requests can be added at runtime without reloading the whole schedule.
    private var ptoBlocks: [PTOBlock]

    public init(api: APIClient, ptoBlocks: [PTOBlock] = []) {
        self.api = api
        self.ptoBlocks = ptoBlocks
    }

    /// §14.9 — Integrate an approved PTO request into the conflict checker.
    /// Called by `TimeOffRequestsSidebar` via its `onApproved` callback.
    /// Converts the approved `TimeOffRequest` to a `PTOBlock` and re-runs
    /// conflict detection across existing shifts.
    public func addApprovedPTOBlock(from request: TimeOffRequest) {
        let block = PTOBlock(
            employeeId: request.userId,
            startAt: request.startDate + "T00:00:00Z",
            endAt: request.endDate + "T23:59:59Z",
            description: "\(request.kind.rawValue.capitalized) \(request.startDate)–\(request.endDate)"
        )
        ptoBlocks.append(block)
        // Re-evaluate conflicts across all existing shifts with the new PTO block.
        let newConflicts = shifts.compactMap { shift -> [ScheduleConflict]? in
            let body = CreateScheduledShiftBody(
                employeeId: shift.employeeId,
                startAt: shift.startAt,
                endAt: shift.endAt,
                role: shift.role,
                notes: shift.notes
            )
            let c = ShiftScheduleConflictChecker.check(
                proposed: body,
                existingShifts: shifts.filter { $0.id != shift.id },
                ptoBlocks: ptoBlocks
            )
            return c.isEmpty ? nil : c
        }.flatMap { $0 }
        conflicts = Array(Set(newConflicts))
    }

    public func load() async {
        loadState = .loading
        do {
            let loaded = try await api.getSchedule(weekStart: weekStart)
            shifts = loaded
            sortedIndices = Array(loaded.indices)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// §14.6 iPad drag-drop: reorder local display order without a server call.
    /// The server shift times are unchanged; this affects visual grouping only.
    public func moveShifts(fromOffsets: IndexSet, toOffset: Int) {
        sortedIndices.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Shifts in the current display order.
    public var sortedShifts: [ScheduledShift] {
        sortedIndices.compactMap { idx in
            shifts.indices.contains(idx) ? shifts[idx] : nil
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
            sortedIndices = Array(shifts.indices)
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
/// iPad: scrollable grid with drag-drop reordering (§14.6).
/// iPhone: list grouped by day with swipe-to-delete.
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

    /// iPhone: plain list with pull-to-refresh.
    private var iPhoneLayout: some View {
        List {
            ForEach(vm.sortedShifts) { shift in
                ScheduledShiftRow(shift: shift)
            }
        }
        .refreshable { await vm.load() }
        .overlay { stateOverlay }
    }

    /// iPad: scrollable grid with drag-drop reorder (§14.6).
    ///
    /// Uses `List` with `.onMove` so SwiftUI provides the native long-press-then-drag
    /// affordance on iPad. The list scrolls horizontally when there are many shifts,
    /// but the default vertical `List` works fine for the standard weekly layout.
    private var iPadLayout: some View {
        List {
            ForEach(vm.sortedShifts) { shift in
                ScheduledShiftRow(shift: shift)
                    .frame(maxWidth: .infinity)
                    .brandHover()
                    .hoverEffect(.highlight)
                    .contextMenu {
                        Button(role: .destructive) {
                            // Deletion deferred to §14 delete task (server PATCH needed)
                        } label: {
                            Label("Remove Shift", systemImage: "trash")
                        }
                    }
            }
            .onMove { from, to in
                vm.moveShifts(fromOffsets: from, toOffset: to)
            }
        }
        .environment(\.editMode, .constant(.active))
        .refreshable { await vm.load() }
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
