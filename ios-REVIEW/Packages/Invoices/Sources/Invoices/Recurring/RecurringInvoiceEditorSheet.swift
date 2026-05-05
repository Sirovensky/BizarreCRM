#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.8 Recurring Invoice Editor Sheet — admin form
// §7.11 Template picker wired: "Template Invoice" row opens InvoiceTemplatePickerSheet to select
//        the template whose line items are copied on each run.

public struct RecurringInvoiceEditorSheet: View {
    @State private var vm: RecurringInvoiceEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let api: APIClient
    private let onSaved: () async -> Void

    // §7.11 Template picker sheet state
    @State private var showTemplatePicker: Bool = false

    public init(api: APIClient, rule: RecurringInvoiceRule? = nil, onSaved: @escaping () async -> Void) {
        self.api = api
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

                // §7.11 Template invoice picker row
                Section("Template Invoice") {
                    Button {
                        showTemplatePicker = true
                    } label: {
                        HStack {
                            if let name = vm.selectedTemplateName, !name.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                    Text("ID \(vm.templateInvoiceId ?? 0)")
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            } else {
                                Label(
                                    vm.templateInvoiceId != nil
                                        ? "Template #\(vm.templateInvoiceId!)"
                                        : "Choose template…",
                                    systemImage: "doc.plaintext"
                                )
                                .foregroundStyle(vm.templateInvoiceId != nil ? .bizarreOnSurface : .bizarreOrange)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .imageScale(.small)
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        vm.selectedTemplateName != nil
                            ? "Template: \(vm.selectedTemplateName!). Tap to change."
                            : "No template selected — tap to pick a template"
                    )
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
            // §7.11 Template picker sheet
            .sheet(isPresented: $showTemplatePicker) {
                InvoiceTemplatePickerSheet(api: api) { template in
                    vm.templateInvoiceId = template.id
                    vm.selectedTemplateName = template.name
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
