import SwiftUI
import DesignSystem

// MARK: - QuietHoursEditorView

/// Time range picker for quiet hours (start + end).
/// "Critical only during quiet hours" toggle.
public struct QuietHoursEditorView: View {

    // MARK: - Binding

    @Binding private var quietHours: QuietHours?
    private let onSave: ((QuietHours?) -> Void)?

    // MARK: - Local state

    @State private var isEnabled: Bool
    @State private var startMinutes: Int
    @State private var endMinutes: Int
    @State private var criticalOverride: Bool

    // MARK: - Init

    public init(quietHours: Binding<QuietHours?>, onSave: ((QuietHours?) -> Void)? = nil) {
        _quietHours = quietHours
        self.onSave = onSave
        let qh = quietHours.wrappedValue
        _isEnabled = State(wrappedValue: qh != nil)
        _startMinutes = State(wrappedValue: qh?.startMinutesFromMidnight ?? 22 * 60)
        _endMinutes = State(wrappedValue: qh?.endMinutesFromMidnight ?? 7 * 60)
        _criticalOverride = State(wrappedValue: qh?.allowCriticalOverride ?? true)
    }

    // MARK: - Body

    public var body: some View {
        Form {
            Section {
                Toggle("Enable Quiet Hours", isOn: $isEnabled)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Enable quiet hours: \(isEnabled ? "on" : "off")")
            } footer: {
                Text("Notifications are suppressed during quiet hours, except critical events if the override is enabled.")
            }

            if isEnabled {
                Section("Quiet Period") {
                    timePicker(label: "Start", minutesFromMidnight: $startMinutes)
                    timePicker(label: "End", minutesFromMidnight: $endMinutes)
                }

                Section {
                    Toggle("Allow critical alerts during quiet hours", isOn: $criticalOverride)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Critical override: \(criticalOverride ? "on" : "off")")
                } footer: {
                    Text("Critical events (Backup failed, Security event, Out of stock, Payment declined) will still deliver.")
                }
            }

            Section {
                Button("Save") { save() }
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Save quiet hours settings")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Quiet Hours")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Time picker row

    @ViewBuilder
    private func timePicker(label: String, minutesFromMidnight: Binding<Int>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            DatePicker(
                label,
                selection: Binding(
                    get: { minutesToDate(minutesFromMidnight.wrappedValue) },
                    set: { minutesFromMidnight.wrappedValue = dateToMinutes($0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .tint(.bizarreOrange)
            .accessibilityLabel("\(label) time: \(minutesDescription(minutesFromMidnight.wrappedValue))")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Helpers

    private func save() {
        let result: QuietHours? = isEnabled
            ? QuietHours(
                startMinutesFromMidnight: startMinutes,
                endMinutesFromMidnight: endMinutes,
                allowCriticalOverride: criticalOverride
              )
            : nil
        quietHours = result
        onSave?(result)
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
#Preview {
    @Previewable @State var qh: QuietHours? = nil
    return NavigationStack {
        QuietHoursEditorView(quietHours: $qh)
    }
}
#endif
