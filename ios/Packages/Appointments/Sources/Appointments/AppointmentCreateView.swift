import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class AppointmentCreateViewModel {
    public var title: String = ""
    public var startDate: Date = Date().addingTimeInterval(60 * 60) // default: in an hour
    public var endDate: Date = Date().addingTimeInterval(60 * 60 * 2) // default: +1hr of start
    public var notes: String = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endDate > startDate
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard isValid else {
            errorMessage = "A title and end-time-after-start are required."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let f = ISO8601DateFormatter()
        let req = CreateAppointmentRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            startTime: f.string(from: startDate),
            endTime: f.string(from: endDate),
            notes: notes.isEmpty ? nil : notes
        )
        do {
            let created = try await api.createAppointment(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Appointment create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct AppointmentCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppointmentCreateViewModel

    public init(api: APIClient) { _vm = State(wrappedValue: AppointmentCreateViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appointment") {
                    TextField("Title", text: $vm.title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Start", selection: $vm.startDate)
                    DatePicker("End", selection: $vm.endDate)
                }
                Section("Notes") {
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.createdId != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
        }
    }
}
