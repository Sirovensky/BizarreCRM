import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimeOffRequestSheet
//
// Self-service time-off submission sheet.
// Calls POST /api/v1/time-off via `TimeOffViewModel.submit(...)`.
// Liquid Glass on sheet navigation chrome per visual language mandate.
//
// Local state (kind/dates/reason) lives entirely in this @Observable VM
// which is created in the View's @State — no parent VM coupling required.

@MainActor
@Observable
public final class TimeOffRequestSheetViewModel {

    public var kind: TimeOffKind = .pto
    public var startDate: Date = Date()
    public var endDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    public var reason: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    public var canSubmit: Bool { endDate >= startDate }

    public init() {}

    /// Returns a (startISO, endISO) pair ready for the server, or nil + sets errorMessage.
    public func buildDateStrings() -> (start: String, end: String)? {
        guard canSubmit else {
            errorMessage = "End date must be on or after start date."
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return (formatter.string(from: startDate), formatter.string(from: endDate))
    }
}

public struct TimeOffRequestSheet: View {

    @Bindable var vm: TimeOffViewModel
    @State private var sheetVM = TimeOffRequestSheetViewModel()
    @Environment(\.dismiss) private var dismiss

    public init(vm: TimeOffViewModel, onSaved: @escaping @MainActor (TimeOffRequest) -> Void = { _ in }) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Request Details") {
                    Picker("Type", selection: $sheetVM.kind) {
                        ForEach(TimeOffKind.allCases, id: \.self) { k in
                            Text(k.displayName).tag(k)
                        }
                    }
                    .accessibilityLabel("Time off type")

                    DatePicker(
                        "Start",
                        selection: $sheetVM.startDate,
                        displayedComponents: .date
                    )
                    .accessibilityLabel("Start date")

                    DatePicker(
                        "End",
                        selection: $sheetVM.endDate,
                        in: sheetVM.startDate...,
                        displayedComponents: .date
                    )
                    .accessibilityLabel("End date")
                }

                Section("Reason (optional)") {
                    TextEditor(text: $sheetVM.reason)
                        .frame(minHeight: 72)
                        .accessibilityLabel("Reason for time-off request")
                }

                if let err = sheetVM.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .navigationTitle("Request Time Off")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel request")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sheetVM.isSaving {
                        ProgressView()
                            .accessibilityLabel("Submitting request")
                    } else {
                        Button("Submit") {
                            Task { await handleSubmit() }
                        }
                        .disabled(!sheetVM.canSubmit)
                        .keyboardShortcut(.return)
                        .accessibilityLabel("Submit time-off request")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func handleSubmit() async {
        guard let (start, end) = sheetVM.buildDateStrings() else { return }
        sheetVM.isSaving = true
        defer { sheetVM.isSaving = false }
        sheetVM.errorMessage = nil

        await vm.submit(
            startDate: start,
            endDate: end,
            kind: sheetVM.kind,
            reason: sheetVM.reason.isEmpty ? nil : sheetVM.reason
        )

        switch vm.submitState {
        case .submitted:
            dismiss()
        case let .failed(msg):
            sheetVM.errorMessage = msg
        default:
            break
        }
    }
}
