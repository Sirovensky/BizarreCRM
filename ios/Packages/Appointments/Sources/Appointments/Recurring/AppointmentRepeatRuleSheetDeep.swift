import SwiftUI
import DesignSystem

// MARK: - AppointmentRepeatRuleSheetDeep
//
// Extended version of AppointmentRepeatRuleSheet supporting:
//   - RecurrenceRule (deep) with all frequency types + yearly
//   - Weekday multi-select (weekly only)
//   - Three end modes: until-date / N-occurrences / forever
//   - Monthly mode: on day N vs on Nth weekday
//   - Exception dates list

public struct AppointmentRepeatRuleSheetDeep: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: RecurrenceRule
    @State private var endModeSelection: EndModeTag = .untilDate
    @State private var untilDate: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var occurrenceCount: Int = 10
    @State private var newException: Date = Date()
    @State private var showExceptionPicker = false

    private let onSave: (RecurrenceRule?) -> Void

    private enum EndModeTag: String, CaseIterable {
        case untilDate   = "Until date"
        case count       = "N occurrences"
        case forever     = "Forever"
    }

    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private static let weekdayNames  = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public init(
        initial: RecurrenceRule? = nil,
        onSave: @escaping (RecurrenceRule?) -> Void
    ) {
        _rule = State(wrappedValue: initial ?? RecurrenceRule())
        self.onSave = onSave
        // Sync endModeSelection from initial rule
        if let initial {
            switch initial.endMode {
            case .untilDate(let d):
                _endModeSelection = State(wrappedValue: .untilDate)
                _untilDate = State(wrappedValue: d)
            case .count(let n):
                _endModeSelection = State(wrappedValue: .count)
                _occurrenceCount = State(wrappedValue: n)
            case .forever:
                _endModeSelection = State(wrappedValue: .forever)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    frequencySection
                    if rule.frequency == .weekly  { weekdaySection }
                    if rule.frequency == .monthly { monthlyModeSection }
                    endModeSection
                    if endModeSelection == .untilDate { untilDateSection }
                    if endModeSelection == .count     { countSection }
                    exceptionSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Repeat")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Remove") { onSave(nil); dismiss() }
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Remove recurrence")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(resolvedRule); dismiss() }
                        .accessibilityLabel("Save recurrence rule")
                }
            }
            .presentationDetents([.large])
            .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Resolved rule

    private var resolvedRule: RecurrenceRule {
        let endMode: RecurrenceEndMode = {
            switch endModeSelection {
            case .untilDate: return .untilDate(untilDate)
            case .count:     return .count(max(1, occurrenceCount))
            case .forever:   return .forever
            }
        }()
        return RecurrenceRule(
            frequency: rule.frequency,
            weekdays: rule.weekdays,
            monthlyMode: rule.monthlyMode,
            endMode: endMode,
            exceptionDates: rule.exceptionDates
        )
    }

    // MARK: - Sections

    private var frequencySection: some View {
        Section("Frequency") {
            Picker("Repeat", selection: $rule.frequency) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                    Text(freq.rawValue).tag(freq)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Recurrence frequency")
        }
    }

    private var weekdaySection: some View {
        Section("On") {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(0..<7, id: \.self) { day in
                    let selected = rule.weekdays.contains(day)
                    Button {
                        var updated = rule.weekdays
                        if selected { updated.remove(day) } else { updated.insert(day) }
                        rule = RecurrenceRule(
                            frequency: rule.frequency,
                            weekdays: updated,
                            monthlyMode: rule.monthlyMode,
                            endMode: rule.endMode,
                            exceptionDates: rule.exceptionDates
                        )
                    } label: {
                        Text(Self.weekdayLabels[day])
                            .font(.brandLabelSmall())
                            .frame(width: 36, height: 36)
                            .foregroundStyle(selected ? Color.white : .bizarreOnSurface)
                            .background(
                                selected ? Color.bizarreOrange : Color.bizarreSurface2,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.weekdayNames[day])
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.bizarreSurface1)
        }
    }

    private var monthlyModeSection: some View {
        Section("Monthly pattern") {
            Picker("Mode", selection: $rule.monthlyMode) {
                ForEach(MonthlyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Monthly recurrence mode")
        }
    }

    private var endModeSection: some View {
        Section("Ends") {
            Picker("End", selection: $endModeSelection) {
                ForEach(EndModeTag.allCases, id: \.self) { tag in
                    Text(tag.rawValue).tag(tag)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Recurrence end mode")
        }
    }

    private var untilDateSection: some View {
        Section("Until date") {
            DatePicker(
                "End date",
                selection: $untilDate,
                in: Date()...,
                displayedComponents: .date
            )
            .accessibilityLabel("Recurrence end date")
        }
    }

    private var countSection: some View {
        Section("Occurrences") {
            Stepper("\(occurrenceCount) time\(occurrenceCount == 1 ? "" : "s")", value: $occurrenceCount, in: 1...500)
                .accessibilityLabel("Number of occurrences: \(occurrenceCount)")
        }
    }

    private var exceptionSection: some View {
        Section("Skip dates") {
            if rule.exceptionDates.isEmpty {
                Text("None")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(rule.exceptionDates.sorted(), id: \.self) { date in
                    Text(Self.formatDate(date))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .onDelete { indices in
                    let sorted = rule.exceptionDates.sorted()
                    let remaining = sorted.enumerated()
                        .filter { !indices.contains($0.offset) }
                        .map(\.element)
                    rule = RecurrenceRule(
                        frequency: rule.frequency,
                        weekdays: rule.weekdays,
                        monthlyMode: rule.monthlyMode,
                        endMode: rule.endMode,
                        exceptionDates: remaining
                    )
                }
            }
            if showExceptionPicker {
                DatePicker("Skip date", selection: $newException, displayedComponents: .date)
                    .accessibilityLabel("Exception date to add")
                Button("Add") {
                    guard !rule.exceptionDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: newException) }) else { return }
                    rule = RecurrenceRule(
                        frequency: rule.frequency,
                        weekdays: rule.weekdays,
                        monthlyMode: rule.monthlyMode,
                        endMode: rule.endMode,
                        exceptionDates: rule.exceptionDates + [newException]
                    )
                    showExceptionPicker = false
                }
                .foregroundStyle(.bizarreOrange)
            } else {
                Button("Add skip date") { showExceptionPicker = true }
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Add exception date")
            }
        }
    }

    // MARK: - Helpers

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
