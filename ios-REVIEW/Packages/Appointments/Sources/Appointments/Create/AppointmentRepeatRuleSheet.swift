import SwiftUI
import DesignSystem

// RecurrenceFrequency is declared in Recurring/RecurrenceRule.swift (canonical location).

// MARK: - RepeatRule

public struct RepeatRule: Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    public var weekdays: Set<Int>   // 0=Sun … 6=Sat; only used for .weekly
    public var until: Date

    public init(
        frequency: RecurrenceFrequency = .weekly,
        weekdays: Set<Int> = [],
        until: Date = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    ) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.until = until
    }
}

// MARK: - AppointmentRepeatRuleSheet

/// Recurrence picker sheet: frequency (daily/weekly/monthly),
/// optional weekday chip set (weekly only), and an "until" date.
public struct AppointmentRepeatRuleSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: RepeatRule
    private let onSave: (RepeatRule?) -> Void

    public init(
        initial: RepeatRule? = nil,
        onSave: @escaping (RepeatRule?) -> Void
    ) {
        _rule = State(wrappedValue: initial ?? RepeatRule())
        self.onSave = onSave
    }

    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]
    private static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    frequencySection
                    if rule.frequency == .weekly { weekdaySection }
                    untilSection
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
                    Button("Done") { onSave(rule); dismiss() }
                        .accessibilityLabel("Save recurrence rule")
                }
            }
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
        }
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
                        rule = RepeatRule(frequency: rule.frequency, weekdays: updated, until: rule.until)
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

    private var untilSection: some View {
        Section("Until") {
            DatePicker(
                "End date",
                selection: $rule.until,
                in: Date()...,
                displayedComponents: .date
            )
            .accessibilityLabel("Recurrence end date")
        }
    }
}
