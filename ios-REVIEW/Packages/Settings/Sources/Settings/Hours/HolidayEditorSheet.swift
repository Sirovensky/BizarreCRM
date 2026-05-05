import SwiftUI
import Core
import DesignSystem

// MARK: - §19 HolidayEditorSheet

/// Modal sheet for creating or editing a ``HolidayException``.
public struct HolidayEditorSheet: View {

    @State private var viewModel: HolidayEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let onDone: () async -> Void

    public init(viewModel: HolidayEditorViewModel, onDone: @escaping () async -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker(
                        "Date",
                        selection: $viewModel.date,
                        displayedComponents: [.date]
                    )
                    .accessibilityLabel("Holiday date")

                    Picker("Repeats", selection: $viewModel.recurring) {
                        ForEach(Recurrence.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .accessibilityLabel("Recurrence pattern")
                }

                Section("Reason") {
                    TextField("e.g. Christmas Day", text: $viewModel.reason)
                        .accessibilityLabel("Holiday reason")
                }

                Section("Hours") {
                    Toggle("Open with custom hours", isOn: $viewModel.isOpen)
                        .accessibilityLabel("Toggle open with special hours")

                    if viewModel.isOpen {
                        DatePicker(
                            "Opens at",
                            selection: openBinding,
                            displayedComponents: [.hourAndMinute]
                        )
                        .accessibilityLabel("Custom open time")

                        DatePicker(
                            "Closes at",
                            selection: closeBinding,
                            displayedComponents: [.hourAndMinute]
                        )
                        .accessibilityLabel("Custom close time")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(viewModel.reason.isEmpty ? "New Holiday" : viewModel.reason)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                            if viewModel.saveSucceeded {
                                await onDone()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Time bindings (maps DateComponents ↔ Date)

    private var openBinding: Binding<Date> {
        componentsToDate($viewModel.openAt)
    }

    private var closeBinding: Binding<Date> {
        componentsToDate($viewModel.closeAt)
    }

    private func componentsToDate(_ binding: Binding<DateComponents>) -> Binding<Date> {
        Binding(
            get: {
                var cal = Calendar.current
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                var dc = cal.dateComponents([.year, .month, .day], from: Date())
                dc.hour = binding.wrappedValue.hour ?? 0
                dc.minute = binding.wrappedValue.minute ?? 0
                return cal.date(from: dc) ?? Date()
            },
            set: { newDate in
                var cal = Calendar.current
                cal.timeZone = TimeZone(secondsFromGMT: 0)!
                binding.wrappedValue = DateComponents(
                    hour: cal.component(.hour, from: newDate),
                    minute: cal.component(.minute, from: newDate)
                )
            }
        )
    }
}
