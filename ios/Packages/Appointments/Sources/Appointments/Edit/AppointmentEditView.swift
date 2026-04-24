import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentEditView

/// Edit / reschedule an existing appointment.
///
/// iPhone: single-column `NavigationStack` with a form.
/// iPad: two-column side-by-side form (left = identity, right = scheduling).
public struct AppointmentEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppointmentEditViewModel
    @State private var showConflictAlert = false

    public init(appointment: Appointment, api: APIClient) {
        _vm = State(wrappedValue: AppointmentEditViewModel(appointment: appointment, api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task {
            await vm.loadEmployees()
            await vm.loadAvailability()
        }
        .alert("Conflict Warning", isPresented: $showConflictAlert) {
            Button("Pick another time", role: .cancel) {}
            Button("Reschedule anyway") { Task { await vm.submit() } }
        } message: {
            Text("This slot overlaps an existing appointment for this technician.")
        }
        .onChange(of: vm.updatedAppointment) { _, appt in
            if appt != nil { dismiss() }
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form { formBody }
                    .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Appointment")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
        }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                HStack(alignment: .top, spacing: 0) {
                    Form {
                        titleSection
                        typeSection
                        technicianSection
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: 380)

                    Divider()

                    Form {
                        slotSection
                        notesSection
                        errorSection
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Edit Appointment")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Shared sections

    @ViewBuilder
    private var formBody: some View {
        titleSection
        typeSection
        technicianSection
        slotSection
        notesSection
        errorSection
    }

    private var titleSection: some View {
        Section("Title") {
            TextField("Appointment title", text: $vm.title)
                .accessibilityLabel("Appointment title")
        }
    }

    private var typeSection: some View {
        Section("Service type") {
            Picker("Service type", selection: $vm.serviceType) {
                ForEach(AppointmentServiceType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Service type selector")

            HStack {
                Text("Duration").foregroundStyle(.bizarreOnSurface)
                Spacer()
                Picker("Duration", selection: $vm.duration) {
                    Text("30 min").tag(TimeInterval(30 * 60))
                    Text("1 hour").tag(TimeInterval(60 * 60))
                    Text("2 hours").tag(TimeInterval(120 * 60))
                    Text("3 hours").tag(TimeInterval(180 * 60))
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Appointment duration")
            }
        }
    }

    private var technicianSection: some View {
        Section("Technician") {
            if vm.isLoadingEmployees {
                HStack {
                    ProgressView().accessibilityHidden(true)
                    Text("Loading technicians…").foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                Picker("Technician", selection: $vm.technicianId) {
                    Text("Any available").tag(Int64?.none)
                    ForEach(vm.employees) { emp in
                        Text(emp.displayName).tag(Int64?.some(emp.id))
                    }
                }
                .accessibilityLabel("Technician picker")
                .onChange(of: vm.technicianId) { _, _ in
                    Task { await vm.loadAvailability() }
                }
            }

            DatePicker("Date", selection: $vm.selectedDate, displayedComponents: .date)
                .onChange(of: vm.selectedDate) { _, _ in
                    Task { await vm.loadAvailability() }
                }
                .accessibilityLabel("Appointment date")
        }
    }

    private var slotSection: some View {
        Section("Reschedule slot") {
            if vm.isLoadingSlots {
                HStack {
                    ProgressView().accessibilityHidden(true)
                    Text("Checking availability…").foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else if vm.availabilitySlots.isEmpty && vm.technicianId != nil {
                Text("No slots available for this date.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No available time slots")
            } else if vm.technicianId == nil {
                Text("Select a technician to see slots.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BrandSpacing.sm) {
                        ForEach(vm.availabilitySlots) { slot in
                            slotChip(slot)
                        }
                    }
                    .padding(.vertical, BrandSpacing.xs)
                }
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: BrandSpacing.md,
                    bottom: 0,
                    trailing: BrandSpacing.md
                ))
            }

            if vm.conflictWarning {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    Text("Conflict: technician has another appointment at this time.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                }
                .accessibilityLabel("Conflict warning: technician is double-booked")
            }
        }
    }

    private func slotChip(_ slot: AvailabilitySlot) -> some View {
        let isSelected = vm.selectedSlot?.id == slot.id
        let isConflict = vm.conflictingSlots.contains(slot.id)
        let label = shortTime(slot.start)

        return Button {
            vm.selectSlot(slot)
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                if isConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white : .bizarreWarning)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? Color.white : .bizarreOnSurface)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(
                isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isConflict ? "Slot \(label) — has conflict" : "Slot \(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes", text: $vm.notes, axis: .vertical)
                .lineLimit(2...5)
                .accessibilityLabel("Appointment notes")
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let err = vm.errorMessage {
            Section {
                Text(err)
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel editing appointment")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSubmitting ? "Saving…" : "Save") {
                if vm.conflictWarning {
                    showConflictAlert = true
                } else {
                    Task { await vm.submit() }
                }
            }
            .disabled(!vm.isValid || vm.isSubmitting)
            .keyboardShortcut("S", modifiers: .command)
            .accessibilityLabel(vm.isSubmitting ? "Saving appointment" : "Save appointment changes")
        }
    }

    // MARK: - Helpers

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) {
            let tf = DateFormatter()
            tf.dateFormat = "h:mm a"
            tf.locale = Locale(identifier: "en_US_POSIX")
            return tf.string(from: d)
        }
        return String(iso.suffix(8).prefix(5))
    }
}
