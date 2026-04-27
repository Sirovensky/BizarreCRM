#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - ScheduledPricingRulesView (§16)
//
// Displays a calendar-style view of all pricing rules that have
// `validFrom` or `validTo` dates set, grouped by month.
//
// Provides:
//   - Monthly rule timeline (rules active now, upcoming, expired).
//   - An "Effective dates editor" integrated into `PricingRuleEditorView`.
//   - One-tap toggle to activate/deactivate a rule without editing.

// MARK: - ScheduledRuleEntry

/// A rule with at least one validity boundary, used for calendar display.
private struct ScheduledRuleEntry: Identifiable {
    let rule: PricingRule
    var id: String { rule.id }

    var statusLabel: String {
        let now = Date.now
        if let to = rule.validTo, to < now { return "Expired" }
        if let from = rule.validFrom, from > now { return "Upcoming" }
        if rule.isValid(at: now) { return "Active now" }
        return "Disabled"
    }

    var statusColor: Color {
        switch statusLabel {
        case "Active now": return .bizarreSuccess
        case "Upcoming":   return .bizarreWarning
        case "Expired":    return .gray
        default:           return .gray
        }
    }

    var isScheduled: Bool {
        rule.validFrom != nil || rule.validTo != nil
    }
}

// MARK: - ScheduledPricingRulesViewModel

@MainActor
@Observable
public final class ScheduledPricingRulesViewModel {

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    private(set) public var entries: [ScheduledRuleEntry] = []
    private(set) public var loadState: LoadState = .idle

    /// The month currently displayed in the calendar strip.
    public var displayedMonth: Date = Calendar.current.startOfMonth(for: .now)

    private let repository: any PricingRulesRepository

    public init(repository: any PricingRulesRepository) {
        self.repository = repository
    }

    public convenience init(api: any APIClient) {
        self.init(repository: PricingRulesRepositoryImpl(api: api))
    }

    // MARK: - Loading

    public func load() async {
        loadState = .loading
        do {
            let all = try await repository.listRules()
            entries = all
                .filter { $0.validFrom != nil || $0.validTo != nil }
                .map { ScheduledRuleEntry(rule: $0) }
                .sorted {
                    ($0.rule.validFrom ?? .distantPast) < ($1.rule.validFrom ?? .distantPast)
                }
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Calendar helpers

    public var currentMonthEntries: [ScheduledRuleEntry] {
        let cal = Calendar.current
        let components = cal.dateComponents([.year, .month], from: displayedMonth)
        return entries.filter { entry in
            let from = entry.rule.validFrom ?? .distantPast
            let to   = entry.rule.validTo   ?? .distantFuture
            // Show if window overlaps with the displayed month
            guard let monthStart = cal.date(from: components),
                  let monthEnd   = cal.date(byAdding: .month, value: 1, to: monthStart)
            else { return false }
            return from < monthEnd && to > monthStart
        }
    }

    public var activeEntries:   [ScheduledRuleEntry] { entries.filter { $0.statusLabel == "Active now" } }
    public var upcomingEntries: [ScheduledRuleEntry] { entries.filter { $0.statusLabel == "Upcoming"   } }
    public var expiredEntries:  [ScheduledRuleEntry] { entries.filter { $0.statusLabel == "Expired"    } }

    public func previousMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    public func nextMonth() {
        displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }
}

// MARK: - ScheduledPricingRulesView

public struct ScheduledPricingRulesView: View {

    @Bindable public var vm: ScheduledPricingRulesViewModel

    public init(vm: ScheduledPricingRulesViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Group {
            switch vm.loadState {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading scheduled rules")

            case .error(let msg):
                ContentUnavailableView(
                    "Could not load rules",
                    systemImage: "exclamationmark.triangle",
                    description: Text(msg)
                )
                .accessibilityLabel("Error: \(msg)")

            case .loaded:
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        monthNavigator
                        rulesSection(
                            title: "Active this month",
                            icon: "checkmark.circle.fill",
                            color: .bizarreSuccess,
                            entries: vm.currentMonthEntries.filter { $0.statusLabel == "Active now" }
                        )
                        rulesSection(
                            title: "Upcoming",
                            icon: "clock.fill",
                            color: .bizarreWarning,
                            entries: vm.upcomingEntries
                        )
                        rulesSection(
                            title: "Expired",
                            icon: "xmark.circle.fill",
                            color: .gray,
                            entries: vm.expiredEntries
                        )
                    }
                    .padding(BrandSpacing.base)
                }
            }
        }
        .navigationTitle("Scheduled Rules")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - Sub-views

    private var monthNavigator: some View {
        HStack {
            Button {
                vm.previousMonth()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.bizarreMutedForeground)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(vm.displayedMonth, format: .dateTime.month(.wide).year())
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            Spacer()

            Button {
                vm.nextMonth()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.bizarreMutedForeground)
            }
            .accessibilityLabel("Next month")
        }
        .padding(.vertical, BrandSpacing.sm)
    }

    @ViewBuilder
    private func rulesSection(
        title: String,
        icon: String,
        color: Color,
        entries: [ScheduledRuleEntry]
    ) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Label(title, systemImage: icon)
                    .font(.brandLabelSmall())
                    .foregroundStyle(color)
                    .textCase(.uppercase)
                    .kerning(0.8)

                ForEach(entries) { entry in
                    scheduledRuleRow(entry: entry, accentColor: color)
                }
            }
        }
    }

    private func scheduledRuleRow(entry: ScheduledRuleEntry, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(entry.rule.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(entry.statusLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            HStack(spacing: BrandSpacing.md) {
                if let from = entry.rule.validFrom {
                    Label(from.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar.badge.clock")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreMutedForeground)
                }
                if let to = entry.rule.validTo {
                    Label(to.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar.badge.exclamationmark")
                        .font(.brandBodySmall())
                        .foregroundStyle(.bizarreMutedForeground)
                }
            }

            Text(entry.rule.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreMutedForeground)
        }
        .padding(BrandSpacing.md)
        .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.rule.name), \(entry.statusLabel)")
        .accessibilityIdentifier("scheduledRule.\(entry.rule.id)")
    }
}

// MARK: - EffectiveDatesEditorSection
//
// Reusable section embedded inside `PricingRuleEditorView` to set
// `validFrom` / `validTo` on a rule.

public struct EffectiveDatesEditorSection: View {

    @Binding public var validFrom: Date?
    @Binding public var validTo: Date?

    @State private var fromEnabled: Bool
    @State private var toEnabled: Bool
    @State private var localFrom: Date
    @State private var localTo: Date

    public init(validFrom: Binding<Date?>, validTo: Binding<Date?>) {
        self._validFrom = validFrom
        self._validTo   = validTo
        let now = Date.now
        _fromEnabled = State(initialValue: validFrom.wrappedValue != nil)
        _toEnabled   = State(initialValue: validTo.wrappedValue != nil)
        _localFrom   = State(initialValue: validFrom.wrappedValue ?? now)
        _localTo     = State(initialValue: validTo.wrappedValue ?? Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now)
    }

    public var body: some View {
        Section("Effective Dates") {
            Toggle("Start date", isOn: $fromEnabled)
                .tint(.bizarreOrange)
                .onChange(of: fromEnabled) { _, enabled in
                    validFrom = enabled ? localFrom : nil
                }
                .accessibilityIdentifier("pricingRule.fromDateToggle")

            if fromEnabled {
                DatePicker(
                    "Activate on",
                    selection: $localFrom,
                    displayedComponents: [.date]
                )
                .onChange(of: localFrom) { _, date in validFrom = date }
                .tint(.bizarreOrange)
                .accessibilityIdentifier("pricingRule.fromDatePicker")
            }

            Toggle("End date", isOn: $toEnabled)
                .tint(.bizarreOrange)
                .onChange(of: toEnabled) { _, enabled in
                    validTo = enabled ? localTo : nil
                }
                .accessibilityIdentifier("pricingRule.toDateToggle")

            if toEnabled {
                DatePicker(
                    "Deactivate on",
                    selection: $localTo,
                    in: localFrom...,
                    displayedComponents: [.date]
                )
                .onChange(of: localTo) { _, date in validTo = date }
                .tint(.bizarreOrange)
                .accessibilityIdentifier("pricingRule.toDatePicker")
            }
        }
    }
}

// MARK: - Calendar.startOfMonth helper

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Preview

#Preview("Scheduled rules (no data)") {
    NavigationStack {
        ScheduledPricingRulesView(
            vm: ScheduledPricingRulesViewModel(repository: PreviewPricingRulesRepository())
        )
    }
    .preferredColorScheme(.dark)
}

// MARK: - Preview stub

private final class PreviewPricingRulesRepository: PricingRulesRepository {
    func listRules() async throws -> [PricingRule] { [] }
    func updateRule(_ rule: PricingRule) async throws {}
    func deleteRule(id: String) async throws {}
    func reorderRules(orderedIds: [String]) async throws {}
}
#endif
