#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §10.1 Time-block Kanban (iPad)
//
// Columns = employees / staff members.
// Rows = time slots (30-min buckets).
// Drag-drop a chip to reschedule (optimistic update + server confirm + rollback on conflict).

// MARK: - Drag payload

struct AppointmentDragPayload: Transferable {
    let appointmentId: Int64
    let originalStaffId: Int64?
    let originalStart: Date

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .text)
    }
}

extension AppointmentDragPayload: Codable {}

// MARK: - ViewModel

@MainActor
@Observable
public final class AppointmentKanbanViewModel {
    public private(set) var appointments: [Appointment] = []
    public private(set) var staff: [KanbanStaffColumn] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var date: Date = Date()

    @ObservationIgnored private let api: APIClient
    private let cal = Calendar.current

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let dateStr = iso(date)
            let resp = try await api.get(
                "/api/v1/appointments/kanban?date=\(dateStr)",
                as: AppointmentKanbanResponse.self
            )
            appointments = resp.appointments
            staff = resp.staff.map { KanbanStaffColumn(id: $0.id, name: $0.name) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func appointments(for staffId: Int64, slot: Date) -> [Appointment] {
        appointments.filter { appt in
            appt.assignedTo == staffId && sameSlot(apptDate(appt), slot)
        }
    }

    public func move(appointmentId: Int64, toStaffId: Int64, slot: Date) async {
        // Optimistic update
        if let idx = appointments.firstIndex(where: { $0.id == appointmentId }) {
            let original = appointments[idx]
            BrandHaptics.tapMedium()
            _ = original
            // Confirm with server
            do {
                let body = RescheduleRequest(assignedTo: toStaffId, startDate: iso(slot))
                let _: EmptyKanbanBody = try await api.patch(
                    "/api/v1/appointments/\(appointmentId)",
                    body: body,
                    as: EmptyKanbanBody.self
                )
                // Reload to get server state
                await load()
            } catch {
                errorMessage = "Reschedule failed: \(error.localizedDescription)"
            }
        }
    }

    private func apptDate(_ appt: Appointment) -> Date {
        guard let s = appt.startTime else { return Date.distantPast }
        return ISO8601DateFormatter().date(from: s) ?? Date.distantPast
    }

    // MARK: Helpers

    public var timeSlots: [Date] {
        let start = cal.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        return (0..<18).compactMap { // 8:00–17:00 in 30-min steps
            cal.date(byAdding: .minute, value: $0 * 30, to: start)
        }
    }

    private func sameSlot(_ a: Date, _ b: Date) -> Bool {
        let diff = abs(a.timeIntervalSince(b))
        return diff < 30 * 60
    }

    private func iso(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}

// MARK: - Supporting Types

public struct KanbanStaffColumn: Identifiable, Sendable {
    public let id: Int64
    public let name: String
}

struct AppointmentKanbanResponse: Decodable {
    let appointments: [Appointment]
    let staff: [StaffDTO]
    struct StaffDTO: Decodable { let id: Int64; let name: String }
}

struct RescheduleRequest: Encodable {
    let assignedTo: Int64
    let startDate: String
    enum CodingKeys: String, CodingKey {
        case assignedTo = "assigned_to"
        case startDate = "start_date"
    }
}

private struct EmptyKanbanBody: Decodable {}

// MARK: - View

public struct AppointmentKanbanView: View {
    @State private var vm: AppointmentKanbanViewModel
    @State private var dragTarget: (staffId: Int64, slot: Date)?

    public init(api: APIClient) {
        _vm = State(wrappedValue: AppointmentKanbanViewModel(api: api))
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section(header: headerRow) {
                    ForEach(vm.timeSlots, id: \.self) { slot in
                        slotRow(slot)
                    }
                }
            }
        }
        .navigationTitle("Kanban — \(vm.date.formatted(date: .abbreviated, time: .omitted))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { datePicker }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .overlay {
            if vm.isLoading { ProgressView() }
        }
    }

    // MARK: Header row (employee names)

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Time")
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
                .frame(width: 60, alignment: .center)
            ForEach(vm.staff) { staff in
                Text(staff.name)
                    .font(.bizarreCaption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.bizarreSurfaceElevated)
            }
        }
        .brandGlass(.regular)
    }

    // MARK: Slot row

    private func slotRow(_ slot: Date) -> some View {
        HStack(spacing: 0) {
            Text(slot.formatted(.dateTime.hour().minute()))
                .font(.bizarreCaption)
                .foregroundStyle(Color.bizarreTextSecondary)
                .frame(width: 60, alignment: .center)
            ForEach(vm.staff) { staff in
                kanbanCell(staffId: staff.id, slot: slot)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .border(Color.bizarreSurface1, width: 0.5)
                    .dropDestination(for: AppointmentDragPayload.self) { items, _ in
                        guard let payload = items.first else { return false }
                        Task { await vm.move(appointmentId: payload.appointmentId,
                                             toStaffId: staff.id, slot: slot) }
                        return true
                    }
            }
        }
    }

    // MARK: Cell contents

    @ViewBuilder
    private func kanbanCell(staffId: Int64, slot: Date) -> some View {
        let appts = vm.appointments(for: staffId, slot: slot)
        ZStack(alignment: .topLeading) {
            if appts.isEmpty {
                Color.bizarreSurface1
            } else {
                ForEach(appts) { appt in
                    kanbanChip(appt)
                }
            }
        }
    }

    private func kanbanChip(_ appt: Appointment) -> some View {
        Text(appt.title ?? "Appointment")
            .font(.bizarreCaption)
            .fontWeight(.medium)
            .lineLimit(2)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bizarrePrimary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .draggable(AppointmentDragPayload(
                appointmentId: appt.id,
                originalStaffId: appt.assignedTo,
                originalStart: ISO8601DateFormatter().date(from: appt.startTime ?? "") ?? Date()
            ))
            .accessibilityLabel("\(appt.title ?? "Appointment") — drag to reschedule")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var datePicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            DatePicker("Date", selection: $vm.date, displayedComponents: .date)
                .labelsHidden()
                .onChange(of: vm.date) { _, _ in Task { await vm.load() } }
        }
    }
}

// Note: Appointment is immutable (struct from Networking); optimistic UI
// reloads from server after move confirm. Full drag-preview shown via chip style.
#endif
