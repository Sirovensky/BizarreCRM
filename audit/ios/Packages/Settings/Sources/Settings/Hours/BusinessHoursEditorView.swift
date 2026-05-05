import SwiftUI
import Core
import DesignSystem

// MARK: - §19 BusinessHoursEditorView

/// Displays a 7-row weekly schedule editor.
/// iPhone: vertical Form. iPad: two-column layout (week grid | summary).
public struct BusinessHoursEditorView: View {

    @State private var viewModel: BusinessHoursEditorViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(viewModel: BusinessHoursEditorViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Business Hours")
        .toolbar { toolbarContent }
        .task { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        Form {
            helperButtonsSection
            weekSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
            Form {
                helperButtonsSection
                weekSection
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(DesignTokens.Spacing.lg)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Sections

    private var helperButtonsSection: some View {
        Section("Quick fill") {
            Button("Copy Mon to all weekdays") {
                withAnimation(.easeInOut(duration: DesignTokens.Motion.snappy)) {
                    viewModel.copyMondayToWeekdays()
                }
            }
            .accessibilityLabel("Copy Monday schedule to Tuesday through Friday")

            Button("Copy Sat to Sun") {
                withAnimation(.easeInOut(duration: DesignTokens.Motion.snappy)) {
                    viewModel.copySaturdayToSunday()
                }
            }
            .accessibilityLabel("Copy Saturday schedule to Sunday")
        }
    }

    private var weekSection: some View {
        Section("Weekly schedule") {
            ForEach(viewModel.week.days, id: \.weekday) { day in
                DayRow(
                    day: day,
                    onToggleOpen: { isOpen in
                        viewModel.setOpen(isOpen, for: day.weekday)
                    },
                    onChangeOpen: { dc in
                        viewModel.setOpenTime(dc, for: day.weekday)
                    },
                    onChangeClose: { dc in
                        viewModel.setCloseTime(dc, for: day.weekday)
                    },
                    onAddBreak: {
                        viewModel.addBreak(to: day.weekday)
                    },
                    onRemoveBreak: { id in
                        viewModel.removeBreak(id: id, from: day.weekday)
                    },
                    onChangeBreakStart: { dc, id in
                        viewModel.updateBreakStart(dc, id: id, weekday: day.weekday)
                    },
                    onChangeBreakEnd: { dc, id in
                        viewModel.updateBreakEnd(dc, id: id, weekday: day.weekday)
                    }
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await viewModel.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(viewModel.isSaving)
            .accessibilityLabel("Save business hours")
        }
    }
}

// MARK: - DayRow

private struct DayRow: View {
    let day: BusinessDay
    let onToggleOpen: (Bool) -> Void
    let onChangeOpen: (DateComponents) -> Void
    let onChangeClose: (DateComponents) -> Void
    let onAddBreak: () -> Void
    let onRemoveBreak: (UUID) -> Void
    let onChangeBreakStart: (DateComponents, UUID) -> Void
    let onChangeBreakEnd: (DateComponents, UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Toggle row
            Toggle(isOn: Binding(
                get: { day.isOpen },
                set: { onToggleOpen($0) }
            )) {
                Text(day.displayName)
                    .fontWeight(.medium)
            }
            .accessibilityLabel("\(day.displayName): \(day.isOpen ? "Open" : "Closed")")
            .animation(reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.quick), value: day.isOpen)

            if day.isOpen {
                // Open / close time pickers
                HStack {
                    TimePickerField(
                        label: "Opens",
                        components: day.openAt ?? DateComponents(hour: 9, minute: 0),
                        onChange: onChangeOpen
                    )
                    Spacer()
                    TimePickerField(
                        label: "Closes",
                        components: day.closeAt ?? DateComponents(hour: 17, minute: 0),
                        onChange: onChangeClose
                    )
                }

                // Breaks
                if let breaks = day.breaks {
                    ForEach(breaks) { br in
                        BreakRow(
                            timeBreak: br,
                            onRemove: { onRemoveBreak(br.id) },
                            onChangeStart: { dc in onChangeBreakStart(dc, br.id) },
                            onChangeEnd: { dc in onChangeBreakEnd(dc, br.id) }
                        )
                    }
                }

                Button {
                    onAddBreak()
                } label: {
                    Label("Add break", systemImage: "plus.circle")
                        .font(.footnote)
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add break for \(day.displayName)")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}

// MARK: - BreakRow

private struct BreakRow: View {
    let timeBreak: TimeBreak
    let onRemove: () -> Void
    let onChangeStart: (DateComponents) -> Void
    let onChangeEnd: (DateComponents) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(timeBreak.label ?? "Break")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                HStack {
                    TimePickerField(label: "From", components: timeBreak.startAt, onChange: onChangeStart)
                    TimePickerField(label: "To", components: timeBreak.endAt, onChange: onChangeEnd)
                }
            }
            Spacer()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.bizarreError)
            }
            .accessibilityLabel("Remove \(timeBreak.label ?? "break")")
        }
    }
}

// MARK: - TimePickerField

private struct TimePickerField: View {
    let label: String
    let components: DateComponents
    let onChange: (DateComponents) -> Void

    private var binding: Binding<Date> {
        Binding(
            get: {
                var cal = Calendar.current
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                var dc = cal.dateComponents([.year, .month, .day], from: Date())
                dc.hour = components.hour ?? 0
                dc.minute = components.minute ?? 0
                return cal.date(from: dc) ?? Date()
            },
            set: { newDate in
                var cal = Calendar.current
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                let dc = DateComponents(
                    hour: cal.component(.hour, from: newDate),
                    minute: cal.component(.minute, from: newDate)
                )
                onChange(dc)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            DatePicker(
                label,
                selection: binding,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
        }
        .accessibilityLabel("\(label) time")
    }
}
