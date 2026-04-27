import SwiftUI
import DesignSystem

// MARK: - ScheduleSendSheet
//
// §12.2 Schedule send — date/time picker for future delivery.
// Presented as a .medium sheet from the SmsThreadView composer bar.

public struct ScheduleSendSheet: View {
    @Binding public var scheduledDate: Date?
    @State private var pickerDate: Date = defaultPickerDate()
    @Environment(\.dismiss) private var dismiss

    public init(scheduledDate: Binding<Date?>) {
        self._scheduledDate = scheduledDate
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Send at",
                        selection: $pickerDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .accessibilityLabel("Pick send date and time")
                } header: {
                    Text("Schedule Message")
                } footer: {
                    Text("The message will be delivered at the selected time. You can cancel from the message thread before it sends.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if scheduledDate != nil {
                    Section {
                        Button(role: .destructive) {
                            scheduledDate = nil
                            dismiss()
                        } label: {
                            Label("Remove Schedule", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityLabel("Remove scheduled send time")
                    }
                }
            }
            .navigationTitle("Schedule Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel scheduling")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Set") {
                        scheduledDate = pickerDate
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Confirm scheduled send time")
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            pickerDate = scheduledDate ?? Self.defaultPickerDate()
        }
    }

    private static func defaultPickerDate() -> Date {
        // Default to 1 hour from now, rounded to next 15-minute increment.
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let minute = (components.minute ?? 0)
        let roundedMinute = ((minute / 15) + 1) * 15
        components.minute = roundedMinute % 60
        components.hour = (components.hour ?? 0) + roundedMinute / 60 + 1
        return calendar.date(from: components) ?? now.addingTimeInterval(3600)
    }
}
