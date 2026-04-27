import SwiftUI
import Core
import DesignSystem

// MARK: - §3.1 Date-range selector for dashboard KPIs
//
// Presets: Today / Yesterday / Last 7 / This month / Last month / This year /
//          All-time / Custom.
// Persists selection per-user in UserDefaults.
// The selected range is passed as query params to the server: ?from=&to=

// MARK: - Model

public enum DashboardDateRange: String, CaseIterable, Sendable, Identifiable {
    case today        = "today"
    case yesterday    = "yesterday"
    case last7        = "last7"
    case thisMonth    = "thisMonth"
    case lastMonth    = "lastMonth"
    case thisYear     = "thisYear"
    case allTime      = "allTime"
    case custom       = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today:      return "Today"
        case .yesterday:  return "Yesterday"
        case .last7:      return "Last 7 days"
        case .thisMonth:  return "This month"
        case .lastMonth:  return "Last month"
        case .thisYear:   return "This year"
        case .allTime:    return "All time"
        case .custom:     return "Custom"
        }
    }

    /// ISO-8601 `from` and `to` strings for the server query.
    /// `to` is always today (inclusive) for built-ins; `nil` = omit param.
    public func dateInterval(relativeTo now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date) {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: DateComponents(day: 1, second: -1), to: today)!
        switch self {
        case .today:
            return (today, endOfToday)
        case .yesterday:
            let y = cal.date(byAdding: .day, value: -1, to: today)!
            let endY = cal.date(byAdding: DateComponents(day: 1, second: -1), to: y)!
            return (y, endY)
        case .last7:
            let from = cal.date(byAdding: .day, value: -6, to: today)!
            return (from, endOfToday)
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: today)
            let from = cal.date(from: comps)!
            return (from, endOfToday)
        case .lastMonth:
            var comps = cal.dateComponents([.year, .month], from: today)
            comps.month = (comps.month ?? 1) - 1
            let from = cal.date(from: comps)!
            var endComps = cal.dateComponents([.year, .month], from: today)
            let endFrom = cal.date(from: endComps)!
            let to = cal.date(byAdding: .second, value: -1, to: endFrom)!
            return (from, to)
        case .thisYear:
            var comps = DateComponents()
            comps.year = cal.component(.year, from: today)
            comps.month = 1
            comps.day = 1
            let from = cal.date(from: comps)!
            return (from, endOfToday)
        case .allTime:
            // 10 years back — server treats missing `from` as beginning of time;
            // we send a distant past date to keep the API param consistent.
            let from = cal.date(byAdding: .year, value: -10, to: today)!
            return (from, endOfToday)
        case .custom:
            // Caller must provide custom dates; return today as safe fallback.
            return (today, endOfToday)
        }
    }
}

// MARK: - Store

/// Persists the selected date range + custom bounds in UserDefaults.
public final class DashboardDateRangeStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let rangeKey        = "dashboard.dateRange"
    private static let customFromKey   = "dashboard.dateRange.customFrom"
    private static let customToKey     = "dashboard.dateRange.customTo"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadRange() -> DashboardDateRange {
        DashboardDateRange(rawValue: defaults.string(forKey: Self.rangeKey) ?? "") ?? .today
    }

    public func saveRange(_ range: DashboardDateRange) {
        defaults.set(range.rawValue, forKey: Self.rangeKey)
    }

    public func loadCustomDates() -> (from: Date, to: Date) {
        let fromInterval = defaults.double(forKey: Self.customFromKey)
        let toInterval   = defaults.double(forKey: Self.customToKey)
        let now = Date()
        let from = fromInterval > 0 ? Date(timeIntervalSince1970: fromInterval) : Calendar.current.startOfDay(for: now)
        let to   = toInterval   > 0 ? Date(timeIntervalSince1970: toInterval) : now
        return (from, to)
    }

    public func saveCustomDates(from: Date, to: Date) {
        defaults.set(from.timeIntervalSince1970, forKey: Self.customFromKey)
        defaults.set(to.timeIntervalSince1970,   forKey: Self.customToKey)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class DashboardDateRangeViewModel {
    public var selectedRange: DashboardDateRange = .today
    public var customFrom: Date = Calendar.current.startOfDay(for: Date())
    public var customTo: Date = Date()
    public var isShowingCustomPicker: Bool = false

    private let store: DashboardDateRangeStore
    /// Called whenever the effective range changes so the dashboard refetches.
    public var onChange: ((DashboardDateRange, Date, Date) -> Void)?

    public init(store: DashboardDateRangeStore = DashboardDateRangeStore()) {
        self.store = store
        self.selectedRange = store.loadRange()
        let (f, t) = store.loadCustomDates()
        customFrom = f
        customTo = t
    }

    public func select(_ range: DashboardDateRange) {
        selectedRange = range
        store.saveRange(range)
        if range == .custom {
            isShowingCustomPicker = true
        } else {
            let (f, t) = range.dateInterval()
            onChange?(range, f, t)
        }
    }

    public func applyCustomDates() {
        store.saveCustomDates(from: customFrom, to: customTo)
        isShowingCustomPicker = false
        onChange?(selectedRange, customFrom, customTo)
    }

    /// Current effective (from, to) pair — safe to read without triggering a pick.
    public var effectiveInterval: (from: Date, to: Date) {
        if selectedRange == .custom {
            return (customFrom, customTo)
        }
        return selectedRange.dateInterval()
    }
}

// MARK: - View

/// Horizontal scrollable chip bar for dashboard date-range selection (§3.1).
/// Shows preset chips; "Custom" opens a sheet with two DatePickers.
public struct DashboardDateRangePicker: View {
    @State private var vm: DashboardDateRangeViewModel

    public init(vm: DashboardDateRangeViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(DashboardDateRange.allCases) { range in
                    chip(range)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .sheet(isPresented: $vm.isShowingCustomPicker) {
            customPickerSheet
        }
    }

    @ViewBuilder
    private func chip(_ range: DashboardDateRange) -> some View {
        let isSelected = vm.selectedRange == range
        Button {
            vm.select(range)
        } label: {
            Text(range.displayName)
                .font(.brandLabelLarge())
                .foregroundStyle(isSelected ? Color.white : Color.bizarreOnSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.bizarreOrange : Color.bizarreSurface2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.bizarreOutline.opacity(0.35),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(range.displayName)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var customPickerSheet: some View {
        NavigationStack {
            Form {
                Section("From") {
                    DatePicker("Start date",
                               selection: $vm.customFrom,
                               in: ...vm.customTo,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityLabel("Custom range start date")
                }
                Section("To") {
                    DatePicker("End date",
                               selection: $vm.customTo,
                               in: vm.customFrom...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityLabel("Custom range end date")
                }
            }
            .navigationTitle("Custom range")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { vm.applyCustomDates() }
                        .accessibilityLabel("Apply custom date range")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.isShowingCustomPicker = false }
                        .accessibilityLabel("Cancel custom date range")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Tests
#if DEBUG
import XCTest
// Run via swift test in Package context.
#endif
