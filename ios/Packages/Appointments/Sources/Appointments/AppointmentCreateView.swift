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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: POST create appointment. Unlike the
            // FullViewModel this basic create doesn't carry an idempotency
            // key — every retap of Save creates a fresh appointment row.
            // If the user dismisses mid-flight the server may already have
            // inserted; painting an error tempts a retap that duplicates.
            // Stay silent; list reload reveals the row.
            return
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
#if !os(macOS)
                        .textInputAutocapitalization(.sentences)
#endif
                    DatePicker("Start", selection: $vm.startDate)
                        .onChange(of: vm.startDate) { _, newStart in
                            // BUGHUNT-2026-05-18: when user pushes Start
                            // past current End, keep the 1-hour default
                            // duration rather than silently breaking the
                            // form. Mirrors Calendar / Reminders default UX.
                            if vm.endDate <= newStart {
                                vm.endDate = newStart.addingTimeInterval(60 * 60)
                            }
                        }
                    // BUGHUNT-2026-05-18: End DatePicker had no range, so a
                    // user who scrolled End back before Start saw the Save
                    // button silently disable with no inline reason. Clamp
                    // to `startDate...` so the picker physically prevents
                    // the invalid state.
                    DatePicker("End", selection: $vm.endDate, in: vm.startDate...)
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
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
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
