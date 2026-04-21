import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PTORequestSheetViewModel

@MainActor
@Observable
public final class PTORequestSheetViewModel {
    public var ptoType: PTOType = .vacation
    public var startDate: Date = Date()
    public var endDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    public var reason: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let employeeId: String
    @ObservationIgnored private let onSaved: @MainActor (PTORequest) -> Void

    public init(api: APIClient, employeeId: String, onSaved: @escaping @MainActor (PTORequest) -> Void) {
        self.api = api
        self.employeeId = employeeId
        self.onSaved = onSaved
    }

    public func submit() async {
        guard endDate >= startDate else {
            errorMessage = "End date must be on or after start date."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let req = CreatePTORequest(
                employeeId: employeeId,
                type: ptoType,
                startDate: startDate,
                endDate: endDate,
                reason: reason
            )
            let created = try await api.createPTORequest(req)
            onSaved(created)
        } catch {
            AppLog.ui.error("PTORequestSheet submit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PTORequestSheet

public struct PTORequestSheet: View {
    @State private var vm: PTORequestSheetViewModel
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, employeeId: String, onSaved: @escaping @MainActor (PTORequest) -> Void) {
        _vm = State(wrappedValue: PTORequestSheetViewModel(api: api, employeeId: employeeId, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Request Details") {
                    Picker("Type", selection: $vm.ptoType) {
                        ForEach(PTOType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    DatePicker("Start", selection: $vm.startDate, displayedComponents: .date)
                    DatePicker("End", selection: $vm.endDate, in: vm.startDate..., displayedComponents: .date)
                }

                Section("Reason (optional)") {
                    TextEditor(text: $vm.reason)
                        .frame(minHeight: 72)
                        .accessibilityLabel("Reason for time off")
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Request Time Off")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Submit") {
                            Task { await vm.submit() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
