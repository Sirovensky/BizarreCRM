import SwiftUI
import Core
import DesignSystem
import Networking

// §9.3 — "Schedule appointment" — jumps to Appointment create prefilled with the lead's
// customer/contact info and links the created appointment back to the lead.
//
// Cross-package dependency rule: Leads owns this sheet. It calls the Appointments API
// endpoint (not the Appointments package UI) so no Leads→Appointments package import is needed.
// Agent 5 (Appointments) owns AppointmentCreateFullView — we do NOT use it here; instead
// we present a focused inline form that posts directly to POST /appointments with
// `lead_id` pre-populated, keeping the cross-slice boundary clean.

// MARK: - Sheet

public struct LeadScheduleAppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: LeadScheduleAppointmentViewModel

    public init(api: APIClient, lead: LeadDetail) {
        _vm = State(wrappedValue: LeadScheduleAppointmentViewModel(api: api, lead: lead))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    customerSection
                    dateTimeSection
                    typeSection
                    notesSection
                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreError.opacity(0.08))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Schedule Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Scheduling…" : "Schedule") {
                        Task {
                            await vm.submit()
                            if vm.createdId != nil { dismiss() }
                        }
                    }
                    .disabled(vm.isSubmitting)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var customerSection: some View {
        Section("Customer") {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.lead.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let phone = vm.lead.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .accessibilityLabel("Customer: \(vm.lead.displayName)")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var dateTimeSection: some View {
        Section("Date & Time") {
            DatePicker(
                "Start",
                selection: $vm.startAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityLabel("Appointment start date and time")
            .datePickerStyle(.compact)

            Stepper(
                value: $vm.durationMinutes,
                in: 15...480,
                step: 15
            ) {
                HStack {
                    Text("Duration")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer(minLength: 0)
                    Text(vm.durationLabel)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Duration: \(vm.durationLabel)")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Appointment type", selection: $vm.appointmentType) {
                Text("Drop-off").tag("drop_off")
                Text("Pick-up").tag("pick_up")
                Text("Consultation").tag("consultation")
                Text("On-site visit").tag("on_site")
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Appointment type: \(vm.appointmentType)")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Any special instructions…", text: $vm.notes, axis: .vertical)
                .lineLimit(3...6)
                .font(.brandBodyMedium())
                .accessibilityLabel("Appointment notes")
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LeadScheduleAppointmentViewModel {
    public let lead: LeadDetail
    public var startAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    public var durationMinutes: Int = 60
    public var appointmentType: String = "consultation"
    public var notes: String = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient, lead: LeadDetail) {
        self.api = api
        self.lead = lead
    }

    public var durationLabel: String {
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) hr" }
        return "\(h) hr \(m) min"
    }

    public func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let req = CreateAppointmentFromLeadRequest(
                leadId: lead.id,
                customerId: lead.customerId,
                customerName: lead.displayName,
                customerPhone: lead.phone,
                startAt: ISO8601DateFormatter().string(from: startAt),
                durationMinutes: durationMinutes,
                appointmentType: appointmentType,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                idempotencyKey: UUID().uuidString
            )
            let result = try await api.createAppointmentFromLead(req)
            createdId = result.id
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

// MARK: - Request / Response DTOs

public struct CreateAppointmentFromLeadRequest: Encodable, Sendable {
    public let leadId: Int64
    public let customerId: Int64?
    public let customerName: String
    public let customerPhone: String?
    public let startAt: String
    public let durationMinutes: Int
    public let appointmentType: String
    public let notes: String?
    public let idempotencyKey: String

    public init(
        leadId: Int64,
        customerId: Int64? = nil,
        customerName: String,
        customerPhone: String? = nil,
        startAt: String,
        durationMinutes: Int,
        appointmentType: String,
        notes: String? = nil,
        idempotencyKey: String
    ) {
        self.leadId = leadId
        self.customerId = customerId
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.appointmentType = appointmentType
        self.notes = notes
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case leadId           = "lead_id"
        case customerId       = "customer_id"
        case customerName     = "customer_name"
        case customerPhone    = "customer_phone"
        case startAt          = "start_at"
        case durationMinutes  = "duration_minutes"
        case appointmentType  = "appointment_type"
        case notes
        case idempotencyKey   = "idempotency_key"
    }
}

public struct CreatedAppointment: Decodable, Sendable {
    public let id: Int64
    public let startAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case startAt = "start_at"
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `POST /api/v1/appointments` with lead_id prefilled — schedule from a lead.
    public func createAppointmentFromLead(_ req: CreateAppointmentFromLeadRequest) async throws -> CreatedAppointment {
        try await post("/api/v1/appointments", body: req, as: CreatedAppointment.self)
    }
}
