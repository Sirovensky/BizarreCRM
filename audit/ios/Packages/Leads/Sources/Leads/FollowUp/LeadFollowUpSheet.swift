import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - LeadFollowUpSheetViewModel

@MainActor
@Observable
final class LeadFollowUpSheetViewModel {

    enum State: Sendable { case idle, submitting, success, failed(String) }

    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var note: String = ""
    var state: State = .idle

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let leadId: Int64

    init(api: APIClient, leadId: Int64) {
        self.api = api
        self.leadId = leadId
    }

    func submit() async {
        guard case .idle = state else { return }
        state = .submitting
        do {
            let iso = ISO8601DateFormatter().string(from: dueDate)
            let body = LeadFollowUpBody(dueAt: iso, note: note)
            _ = try await api.createFollowUp(leadId: leadId, body: body)
            state = .success
        } catch {
            AppLog.ui.error("Follow-up create failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - LeadFollowUpSheet

/// §9.6 — Set a follow-up reminder for a lead.
public struct LeadFollowUpSheet: View {
    @State private var vm: LeadFollowUpSheetViewModel
    private let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, leadId: Int64, onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: LeadFollowUpSheetViewModel(api: api, leadId: leadId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section {
                        DatePicker(
                            "Due date",
                            selection: $vm.dueDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Follow-up due date and time")
                    }
                    Section("Note") {
                        TextEditor(text: $vm.note)
                            .frame(minHeight: 80)
                            .accessibilityLabel("Follow-up note")
                    }
                    if case .failed(let msg) = vm.state {
                        Section {
                            Text(msg)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Set Follow-Up")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(vm.state == .submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.state == .submitting {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Button("Save") { Task { await vm.submit() } }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: vm.state == .success) { _, isSuccess in
            if isSuccess {
                onSuccess()
                dismiss()
            }
        }
    }
}

extension LeadFollowUpSheetViewModel.State: Equatable {
    static func == (lhs: LeadFollowUpSheetViewModel.State, rhs: LeadFollowUpSheetViewModel.State) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.submitting, .submitting), (.success, .success): return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}
