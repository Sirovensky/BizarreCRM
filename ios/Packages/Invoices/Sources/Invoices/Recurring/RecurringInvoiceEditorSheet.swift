#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.8 Recurring Invoice Editor Sheet — admin form

public struct RecurringInvoiceEditorSheet: View {
    @State private var vm: RecurringInvoiceEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () async -> Void

    public init(api: APIClient, rule: RecurringInvoiceRule? = nil, onSaved: @escaping () async -> Void) {
        _vm = State(wrappedValue: RecurringInvoiceEditorViewModel(api: api, rule: rule))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name (optional)", text: $vm.name)
                        .accessibilityLabel("Rule name")

                    Picker("Frequency", selection: $vm.frequency) {
                        ForEach(RecurringFrequency.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    .accessibilityLabel("Recurrence frequency")

                    Stepper("Day of month: \(vm.dayOfMonth)", value: $vm.dayOfMonth, in: 1...28)
                        .accessibilityLabel("Day of month, \(vm.dayOfMonth)")

                    DatePicker("Start date", selection: $vm.startDate, displayedComponents: .date)
                        .accessibilityLabel("Start date")
                }

                Section("End date") {
                    Toggle("Has end date", isOn: $vm.hasEndDate)
                        .accessibilityLabel("Enable end date")
                    if vm.hasEndDate {
                        DatePicker(
                            "End date",
                            selection: Binding(
                                get: { vm.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)! },
                                set: { vm.endDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .accessibilityLabel("End date")
                    }
                }

                Section("Options") {
                    Toggle("Auto-send invoice", isOn: $vm.autoSend)
                        .accessibilityLabel("Automatically email invoice when generated")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .navigationTitle(vm.existingRuleId == nil ? "New Recurring Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await vm.save()
                            if vm.didSave {
                                await onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .accessibilityLabel("Save recurring rule")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
