import SwiftUI
import DesignSystem
import Networking
import Core

/// §14 Phase 4 — Dedicated Timeclock screen.
///
/// Hosts clock-in/out controls, break management, and shift history.
///
/// Layout contract:
/// - **iPhone** (compact): single-column scroll view.
///   Header → ClockInOutTile → Break section → Today's shifts → History.
/// - **iPad** (regular): `NavigationSplitView` with a leading panel for clock
///   controls and a detail pane for shift history.
///
/// All views are wired to real ViewModels backed by live API calls.
/// No orphan UI.
public struct TimeclockScreen: View {

    @Bindable var clockVM: ClockInOutViewModel
    @Bindable var historyVM: ShiftHistoryViewModel
    @Bindable var breakVM: BreakInOutViewModel

    /// Controls whether the break sheet is presented.
    @State private var showBreakSheet = false
    /// iPad detail split selection — which section is shown on the right.
    @State private var iPadDetailSection: iPadDetail = .history

    public enum iPadDetail: Hashable {
        case history
        case breaks
    }

    public init(
        clockVM: ClockInOutViewModel,
        historyVM: ShiftHistoryViewModel,
        breakVM: BreakInOutViewModel
    ) {
        self.clockVM = clockVM
        self.historyVM = historyVM
        self.breakVM = breakVM
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Timeclock")
        .task {
            await clockVM.refresh()
            await historyVM.loadCurrentWeek()
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                clockStatusSection
                clockTileSection
                breakSection
                todaySection
                historySection
            }
            .padding(BrandSpacing.base)
        }
        .refreshable {
            await clockVM.refresh()
            await historyVM.loadCurrentWeek()
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            // Leading panel: clock controls + break
            List(selection: $iPadDetailSection) {
                Section("Clock") {
                    clockStatusSection
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    ClockInOutTile(vm: clockVM)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Break") {
                    breakControlRow
                }
                NavigationLink(value: iPadDetail.history) {
                    Label("Shift History", systemImage: "clock")
                }
                NavigationLink(value: iPadDetail.breaks) {
                    Label("Break Details", systemImage: "pause.circle")
                }
            }
            .navigationTitle("Timeclock")
            .frame(minWidth: 240, idealWidth: 300)
        } detail: {
            switch iPadDetailSection {
            case .history:
                shiftHistoryDetailView
            case .breaks:
                BreakInOutView(vm: breakVM)
            }
        }
    }

    // MARK: - Sections (shared iPhone / iPad-sidebar)

    private var clockStatusSection: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("My Time")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                clockStatusBadge
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var clockStatusBadge: some View {
        if case .active = clockVM.state {
            ClockedInBadge(
                isClockedIn: true,
                elapsed: ClockInOutViewModel.formatElapsed(clockVM.runningElapsed)
            )
        } else {
            Text("Not clocked in")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var clockTileSection: some View {
        ClockInOutTile(vm: clockVM)
            .accessibilityIdentifier("timeclock.screen.tile")
    }

    private var breakSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Break")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            breakControlRow
        }
    }

    @ViewBuilder
    private var breakControlRow: some View {
        if case .active = clockVM.state {
            Button {
                showBreakSheet = true
            } label: {
                Label(
                    breakVM.state == .idle ? "Start Break" : "End Break",
                    systemImage: breakVM.state == .idle ? "pause.circle" : "stop.circle"
                )
                .frame(maxWidth: .infinity)
                .padding(BrandSpacing.sm)
            }
            .buttonStyle(.plain)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12), interactive: true)
            .accessibilityLabel(breakVM.state == .idle ? "Start a break" : "End current break")
            .accessibilityIdentifier("timeclock.breakButton")
            .sheet(isPresented: $showBreakSheet) {
                BreakInOutView(vm: breakVM)
                    .presentationDetents([.medium, .large])
            }
        } else {
            Text("Clock in to manage breaks")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Shift list sections

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Today")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if historyVM.loadState == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading today's shifts")
            } else if historyVM.todayEntries.isEmpty {
                Text("No shifts today")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(BrandSpacing.md)
            } else {
                ForEach(historyVM.todayEntries) { entry in
                    ClockEntryRow(entry: entry)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("This Week")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(weekHoursSummary)
                    .font(.brandLabelSmall().monospacedDigit())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Total this week: \(weekHoursSummary)")
            }

            if case let .failed(msg) = historyVM.loadState {
                ContentUnavailableView(
                    "Failed to load history",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
            } else if historyVM.historicalEntries.isEmpty && historyVM.loadState == .loaded {
                Text("No prior shifts this week")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(BrandSpacing.md)
            } else {
                ForEach(historyVM.historicalEntries) { entry in
                    ClockEntryRow(entry: entry)
                }
            }
        }
    }

    // MARK: - iPad detail pane

    private var shiftHistoryDetailView: some View {
        List {
            Section("Today") {
                if historyVM.todayEntries.isEmpty {
                    Text("No shifts today")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyVM.todayEntries) { entry in
                        ClockEntryRow(entry: entry)
                            .brandHover()
                    }
                }
            }
            Section {
                ForEach(historyVM.historicalEntries) { entry in
                    ClockEntryRow(entry: entry)
                        .brandHover()
                }
            } header: {
                HStack {
                    Text("This Week")
                    Spacer()
                    Text(weekHoursSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Shift History")
        .overlay {
            if case .loading = historyVM.loadState {
                ProgressView("Loading shifts…")
                    .accessibilityLabel("Loading shift history")
            }
        }
        .refreshable {
            await historyVM.loadCurrentWeek()
        }
        .keyboardShortcut("r", modifiers: .command)
    }

    // MARK: - Helpers

    private var weekHoursSummary: String {
        let h = Int(historyVM.totalHours)
        let m = Int((historyVM.totalHours - Double(h)) * 60)
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - ClockEntryRow

/// Single row displaying a clock-in/out entry.
///
/// Shows: date, clock-in time, clock-out time (or "Active"), and hours.
public struct ClockEntryRow: View {

    let entry: ClockEntry

    private static let isoFormatter = ISO8601DateFormatter()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public init(entry: ClockEntry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Label(dateString, systemImage: "calendar")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                durationLabel
            }
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("\(clockInTime) → \(clockOutTime)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var dateString: String {
        guard let date = Self.isoFormatter.date(from: entry.clockIn) else { return entry.clockIn }
        return Self.dateFormatter.string(from: date)
    }

    private var clockInTime: String {
        guard let date = Self.isoFormatter.date(from: entry.clockIn) else { return "?" }
        return Self.timeFormatter.string(from: date)
    }

    private var clockOutTime: String {
        guard let out = entry.clockOut,
              let date = Self.isoFormatter.date(from: out)
        else { return "Active" }
        return Self.timeFormatter.string(from: date)
    }

    @ViewBuilder
    private var durationLabel: some View {
        if let hours = entry.totalHours {
            let h = Int(hours)
            let m = Int((hours - Double(h)) * 60)
            Text(m > 0 ? "\(h)h \(m)m" : "\(h)h")
                .font(.brandLabelSmall().monospacedDigit())
                .foregroundStyle(.bizarreOrange)
        } else if entry.clockOut == nil {
            ClockedInBadge(isClockedIn: true)
        }
    }

    private var a11yLabel: String {
        var label = "Shift on \(dateString), clocked in at \(clockInTime)"
        if entry.clockOut != nil {
            label += ", clocked out at \(clockOutTime)"
            if let hours = entry.totalHours {
                let h = Int(hours)
                let m = Int((hours - Double(h)) * 60)
                label += ", \(m > 0 ? "\(h) hours \(m) minutes" : "\(h) hours")"
            }
        } else {
            label += ", currently active"
        }
        return label
    }
}
