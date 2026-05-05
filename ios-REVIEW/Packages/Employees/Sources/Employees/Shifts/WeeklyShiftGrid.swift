import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - WeeklyShiftGrid
//
// iPad-primary 7-column calendar grid showing one week of shifts per employee.
// iPhone falls back to a day-by-day list layout.
//
// Liquid Glass chrome on the navigation/toolbar layer.
// Hover effects on all tappable cells (.brandHover).

public struct WeeklyShiftGrid: View {

    @Bindable var vm: ShiftsViewModel

    /// All active employees whose shifts should appear as rows.
    let employees: [Employee]

    /// Called when the user taps a shift cell.
    let onShiftTap: (Shift) -> Void

    /// Called when the user taps an empty cell to create a new shift.
    let onCreateTap: (Employee, Date) -> Void

    @State private var selectedShift: Shift?

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE\nd"  // "Mon\n5"
        return f
    }()

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    public init(
        vm: ShiftsViewModel,
        employees: [Employee],
        onShiftTap: @escaping (Shift) -> Void,
        onCreateTap: @escaping (Employee, Date) -> Void
    ) {
        self.vm = vm
        self.employees = employees
        self.onShiftTap = onShiftTap
        self.onCreateTap = onCreateTap
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Schedule")
        .toolbar { weekNavigationToolbar }
        .task { await vm.loadWeek() }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        VStack(spacing: 0) {
            columnHeaderRow
            Divider()
            if vm.loadState == .loading {
                ProgressView("Loading schedule…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading schedule")
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        if employees.isEmpty {
                            emptyEmployeesView
                        } else {
                            ForEach(employees) { employee in
                                employeeRow(employee)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .background(Color.bizarreSurface1)
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            ForEach(vm.weekDays, id: \.self) { day in
                Section(header: Text(dayFormatter.string(from: day).replacingOccurrences(of: "\n", with: " "))) {
                    let dayShifts = shifts(for: day)
                    if dayShifts.isEmpty {
                        Text("No shifts")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        ForEach(dayShifts) { shift in
                            ShiftCell(shift: shift)
                                .onTapGesture { onShiftTap(shift) }
                                .brandHover()
                        }
                    }
                }
            }
        }
        .refreshable { await vm.loadWeek() }
        .overlay { loadFailedOverlay }
    }

    // MARK: - Column header row (iPad)

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            // Employee name column header
            Text("Employee")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: employeeColumnWidth, alignment: .leading)
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)

            ForEach(vm.weekDays, id: \.self) { day in
                Text(dayFormatter.string(from: day))
                    .font(.brandLabelSmall())
                    .foregroundStyle(isToday(day) ? Color.bizarreOrange : .bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(isToday(day) ? Color.bizarreOrange.opacity(0.08) : Color.clear)
                    .accessibilityLabel(accessibilityDayLabel(day))
            }
        }
        .background(Color.bizarreSurface1)
        .brandGlass(.clear)
    }

    // MARK: - Employee row (iPad)

    private func employeeRow(_ employee: Employee) -> some View {
        HStack(spacing: 0) {
            // Employee name cell
            VStack(alignment: .leading, spacing: 2) {
                Text(employee.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let role = employee.role {
                    Text(role)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .frame(width: employeeColumnWidth, alignment: .leading)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)

            ForEach(vm.weekDays, id: \.self) { day in
                shiftDayCell(employee: employee, day: day)
            }
        }
        .frame(minHeight: rowMinHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(employee.displayName)
    }

    // MARK: - Shift day cell (single employee × day)

    private func shiftDayCell(employee: Employee, day: Date) -> some View {
        let dayShifts = vm.shifts(for: employee.id, on: day)
        return ZStack(alignment: .topLeading) {
            // Tap target for creating a new shift
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onCreateTap(employee, day) }
                .brandHover()
                .accessibilityLabel("Add shift for \(employee.displayName) on \(accessibilityDayLabel(day))")
                .accessibilityAddTraits(.isButton)

            if !dayShifts.isEmpty {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    ForEach(dayShifts) { shift in
                        ShiftCell(shift: shift)
                            .onTapGesture { onShiftTap(shift) }
                            .brandHover()
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await vm.deleteShift(id: shift.id) }
                                } label: {
                                    Label("Delete Shift", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(BrandSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, minHeight: rowMinHeight)
        .background(isToday(day) ? Color.bizarreOrange.opacity(0.04) : Color.clear)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var weekNavigationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: vm.retreatWeek) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .accessibilityLabel("Previous week")

            Button(action: vm.advanceWeek) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .accessibilityLabel("Next week")
        }

        ToolbarItem(placement: .principal) {
            Text(monthFormatter.string(from: vm.weekStart))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }

        ToolbarItem(placement: .primaryAction) {
            Button("Today", action: vm.goToCurrentWeek)
                .keyboardShortcut("t", modifiers: [.command])
                .accessibilityLabel("Go to today")
        }
    }

    // MARK: - Helpers

    private var emptyEmployeesView: some View {
        ContentUnavailableView(
            "No Employees",
            systemImage: "person.2",
            description: Text("Add employees to view their schedule")
        )
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    @ViewBuilder
    private var loadFailedOverlay: some View {
        if case let .failed(msg) = vm.loadState {
            ContentUnavailableView(
                "Couldn't Load Schedule",
                systemImage: "exclamationmark.triangle",
                description: Text(msg)
            )
        }
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.autoupdatingCurrent.isDateInToday(day)
    }

    private func accessibilityDayLabel(_ day: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f.string(from: day)
    }

    private func shifts(for day: Date) -> [Shift] {
        employees.flatMap { vm.shifts(for: $0.id, on: day) }
    }

    // Layout constants
    private let employeeColumnWidth: CGFloat = 140
    private let rowMinHeight: CGFloat = 60
}

// MARK: - ShiftCell

/// Compact pill showing a shift's time range and optional role tag.
struct ShiftCell: View {
    let shift: Shift

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(timeRange)
                .font(.brandLabelSmall())
                .foregroundStyle(.white)
                .monospacedDigit()
            if let tag = shift.roleTag, !tag.isEmpty {
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.vertical, BrandSpacing.xxs)
        .background(statusColor, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var timeRange: String {
        let start = format(shift.startAt)
        let end   = format(shift.endAt)
        return "\(start)–\(end)"
    }

    private func format(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return timeFormatter.string(from: date)
    }

    private var statusColor: Color {
        switch shift.status {
        case "cancelled":  return .bizarreOnSurfaceMuted
        case "completed":  return .green.opacity(0.8)
        default:           return .bizarreOrange
        }
    }

    private var accessibilityLabel: String {
        "\(shift.employeeDisplayName) shift \(timeRange)\(shift.roleTag.map { ", \($0)" } ?? "")"
    }
}
