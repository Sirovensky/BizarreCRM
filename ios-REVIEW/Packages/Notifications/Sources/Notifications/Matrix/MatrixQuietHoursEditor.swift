import SwiftUI
import DesignSystem

// MARK: - MatrixQuietHoursEditor
//
// §70 Matrix — Quiet Hours Editor
//
// Presented as a sheet from NotificationMatrixView when the user taps the
// clock icon on any event row.  Lets the user toggle quiet hours on/off,
// pick start/end times via wheel DatePicker, and allow critical-event override.
//
// Uses a callback-based API so the parent VM drives the save; this view holds
// no repository reference and is purely presentational.

public struct MatrixQuietHoursEditor: View {

    // MARK: - Local state

    @State private var isEnabled: Bool
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var criticalOverride: Bool

    private let onSave: (QuietHours?) -> Void

    // MARK: - Init

    public init(initialQuietHours: QuietHours?, onSave: @escaping (QuietHours?) -> Void) {
        let qh = initialQuietHours
        _isEnabled = State(wrappedValue: qh != nil)
        _startMinutes = State(wrappedValue: qh?.startMinutesFromMidnight ?? 22 * 60)
        _endMinutes = State(wrappedValue: qh?.endMinutesFromMidnight ?? 7 * 60)
        _criticalOverride = State(wrappedValue: qh?.allowCriticalOverride ?? true)
        self.onSave = onSave
    }

    // MARK: - Body

    public var body: some View {
        Form {
            // Enable/disable section
            Section {
                Toggle("Enable Quiet Hours", isOn: $isEnabled)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Enable quiet hours: \(isEnabled ? "on" : "off")")
                    .accessibilityIdentifier("matrixQH.enableToggle")
            } footer: {
                Text("Notifications are suppressed during quiet hours, except critical events when the override is on.")
            }

            if isEnabled {
                // Time range section
                Section("Quiet Period") {
                    timePickerRow(label: "Start", minutes: $startMinutes)
                        .accessibilityIdentifier("matrixQH.startPicker")
                    timePickerRow(label: "End", minutes: $endMinutes)
                        .accessibilityIdentifier("matrixQH.endPicker")
                }

                // Critical override
                Section {
                    Toggle("Allow critical alerts during quiet hours", isOn: $criticalOverride)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Critical override: \(criticalOverride ? "on" : "off")")
                        .accessibilityIdentifier("matrixQH.criticalOverride")
                } footer: {
                    Text("Critical events (Backup failed, Security event, Out of stock, Payment declined) will still deliver.")
                }
            }

            // Save section
            Section {
                Button("Save") { commitSave() }
                    .foregroundStyle(.bizarreOrange)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Save quiet hours settings")
                    .accessibilityIdentifier("matrixQH.saveButton")
            }
            .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    // MARK: - Time picker row

    @ViewBuilder
    private func timePickerRow(label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            DatePicker(
                label,
                selection: Binding(
                    get: { minutesToDate(minutes.wrappedValue) },
                    set: { minutes.wrappedValue = dateToMinutes($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .tint(.bizarreOrange)
            .accessibilityLabel("\(label) time: \(minutesDescription(minutes.wrappedValue))")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Helpers

    private func commitSave() {
        let result: QuietHours? = isEnabled
            ? QuietHours(
                startMinutesFromMidnight: startMinutes,
                endMinutesFromMidnight: endMinutes,
                allowCriticalOverride: criticalOverride
              )
            : nil
        onSave(result)
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func dateToMinutes(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func minutesDescription(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let period = h < 12 ? "AM" : "PM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayH, m, period)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("No quiet hours") {
    NavigationStack {
        MatrixQuietHoursEditor(initialQuietHours: nil) { _ in }
            .navigationTitle("Quiet Hours")
    }
}

#Preview("With quiet hours") {
    NavigationStack {
        MatrixQuietHoursEditor(
            initialQuietHours: QuietHours(
                startMinutesFromMidnight: 22 * 60,
                endMinutesFromMidnight: 7 * 60,
                allowCriticalOverride: true
            )
        ) { _ in }
        .navigationTitle("Quiet Hours")
    }
}
#endif
