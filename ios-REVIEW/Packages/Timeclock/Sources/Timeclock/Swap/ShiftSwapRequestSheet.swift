import SwiftUI
import DesignSystem
import Networking

// MARK: - ShiftSwapRequestViewModel

@MainActor
@Observable
public final class ShiftSwapRequestViewModel {

    public enum State: Sendable, Equatable {
        case idle, submitting, submitted, failed(String)
    }

    public private(set) var state: State = .idle
    public var targetEmployeeId: Int64 = 0
    public var note: String = ""
    public var availableShifts: [Shift] = []
    public var selectedShiftId: Int64 = 0

    @ObservationIgnored private let api: APIClient
    var onSubmitted: ((ShiftSwapRequest) -> Void)?

    public init(api: APIClient) {
        self.api = api
    }

    public var canSubmit: Bool {
        selectedShiftId > 0 && targetEmployeeId > 0
    }

    public func submit() async {
        guard canSubmit else { return }
        state = .submitting
        let body = SwapRequestBody(
            requesterShiftId: selectedShiftId,
            targetEmployeeId: targetEmployeeId,
            note: note.isEmpty ? nil : note
        )
        do {
            let request = try await api.createSwapRequest(body: body)
            state = .submitted
            onSubmitted?(request)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - ShiftSwapRequestSheet

/// Sheet for an employee to request a shift swap with a coworker.
///
/// Liquid Glass on the navigation bar per visual language rules.
public struct ShiftSwapRequestSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: ShiftSwapRequestViewModel

    public init(vm: ShiftSwapRequestViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Your Shift") {
                    Picker("Shift", selection: $vm.selectedShiftId) {
                        Text("Select shift").tag(Int64(0))
                        ForEach(vm.availableShifts) { shift in
                            Text(shift.clockIn).tag(shift.id)
                        }
                    }
                    .accessibilityLabel("Select your shift to swap")
                }

                Section("Swap With") {
                    TextField("Coworker employee ID", value: $vm.targetEmployeeId, format: .number)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityLabel("Target employee ID for swap")
                }

                Section("Note (optional)") {
                    TextField("Reason or note", text: $vm.note, axis: .vertical)
                        .lineLimit(2, reservesSpace: true)
                        .accessibilityLabel("Optional swap note")
                }

                if case let .failed(msg) = vm.state {
                    Section {
                        Text(msg).foregroundStyle(.red)
                            .accessibilityLabel("Error: \(msg)")
                    }
                }
            }
            .navigationTitle("Request Shift Swap")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            await vm.submit()
                            if case .submitted = vm.state { dismiss() }
                        }
                    }
                    .disabled(!vm.canSubmit || vm.state == .submitting)
                    .accessibilityLabel("Submit shift swap request")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
