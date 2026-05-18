import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimesheetEditViewModel

@MainActor
@Observable
public final class TimesheetEditViewModel {

    public enum SaveState: Sendable, Equatable {
        case idle, saving, saved, failed(String)
    }

    public private(set) var saveState: SaveState = .idle
    public var clockInText: String
    public var clockOutText: String
    public var reason: String = ""

    private let shift: Shift
    @ObservationIgnored private let api: APIClient
    var onSaved: ((Shift) -> Void)?

    public init(shift: Shift, api: APIClient) {
        self.shift = shift
        self.api = api
        self.clockInText = shift.clockIn
        self.clockOutText = shift.clockOut ?? ""
    }

    public var canSave: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public func save() async {
        guard canSave else { return }
        // BUGHUNT-2026-05-17: re-entry guard. The Save toolbar button is
        // .disabled while .saving, but the surrounding Task is untracked —
        // a second tap after a brief network blip could resubmit. Refuse
        // re-entry while saving.
        if case .saving = saveState { return }
        saveState = .saving
        let edit = TimesheetEditRequest(
            clockIn: clockInText.isEmpty ? nil : clockInText,
            clockOut: clockOutText.isEmpty ? nil : clockOutText,
            reason: reason
        )
        do {
            let updated = try await api.editShift(shiftId: shift.id, edit: edit)
            saveState = .saved
            onSaved?(updated)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: editShift PATCH may have already landed
            // before the sheet's Save Task was cancelled. Painting
            // "Failed: cancelled" tempts the manager to re-tap Save,
            // double-stamping the audit log with the same correction
            // reason. Roll back to .idle so the manager refreshes the
            // timesheet to verify rather than retap blindly.
            saveState = .idle
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - TimesheetEditSheet

/// Manager sheet to correct clock-in/out times; changes are audit-logged.
///
/// Liquid Glass on sheet header per visual language mandate.
public struct TimesheetEditSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: TimesheetEditViewModel

    public init(vm: TimesheetEditViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Clock Times (ISO-8601 UTC)") {
                    LabeledContent("Clock In") {
                        TextField("Clock In", text: $vm.clockInText)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityLabel("Clock-in timestamp")
                    }
                    LabeledContent("Clock Out") {
                        TextField("Clock Out (optional)", text: $vm.clockOutText)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                            .accessibilityLabel("Clock-out timestamp")
                    }
                }
                Section("Reason (required for audit log)") {
                    TextField("Correction reason", text: $vm.reason, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .accessibilityLabel("Correction reason")
                }
                if case let .failed(msg) = vm.saveState {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(msg)")
                    }
                }
            }
            .navigationTitle("Edit Shift")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await vm.save()
                            if case .saved = vm.saveState { dismiss() }
                        }
                    }
                    .disabled(!vm.canSave || vm.saveState == .saving)
                    .accessibilityLabel("Save shift correction")
                }
            }
        }
    }
}
