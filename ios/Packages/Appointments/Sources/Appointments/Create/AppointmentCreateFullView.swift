import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - AppointmentCreateFullView

/// Full appointment create form with:
/// - customer picker
/// - service type segmented control
/// - technician picker with availability filter
/// - slot chip grid
/// - conflict warning badge
/// - recurrence sheet
/// - draft auto-save indicator
public struct AppointmentCreateFullView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppointmentCreateFullViewModel
    @State private var showRepeatSheet = false
    @State private var showConflictAlert = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: AppointmentCreateFullViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.loadEmployees() }
        .sheet(isPresented: $showRepeatSheet) {
            AppointmentRepeatRuleSheet(initial: vm.repeatRule) { rule in
                vm.repeatRule = rule
            }
        }
        .alert("Conflict Warning", isPresented: $showConflictAlert) {
            Button("Pick another time", role: .cancel) {}
            Button("Schedule anyway") { Task { await vm.submit() } }
        } message: {
            Text("This slot overlaps an existing appointment for this technician.")
        }
        .onChange(of: vm.createdId) { _, id in
            if id != nil { dismiss() }
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    formBody
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Appointment")
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
                        customerSection
                        typeSection
                        technicianSection
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: 380)

                    Divider()

                    Form {
                        slotSection
                        notesSection
                        repeatSection
                        errorSection
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("New Appointment")
            .toolbar { toolbarItems }
        }
    }

    // MARK: - Shared form sections

    @ViewBuilder
    private var formBody: some View {
        customerSection
        typeSection
        technicianSection
        slotSection
        notesSection
        repeatSection
        errorSection
    }

    private var customerSection: some View {
        Section("Customer") {
            if vm.customerDisplayName.isEmpty {
                Text("Tap to select a customer")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Select customer — required")
            } else {
                HStack {
                    Text(vm.customerDisplayName)
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Button("Change") { vm.customerId = nil; vm.customerDisplayName = "" }
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Change customer")
                }
            }
            // Customer ID injection — in production a CustomerPicker sheet
            // is presented here. For now expose a simple text field as bridge
            // until §5 customer picker is ready.
            if vm.customerId == nil {
                TextField("Customer ID (numeric)", text: Binding(
                    get: { vm.customerId.map { String($0) } ?? "" },
                    set: { str in
                        if let id = Int64(str) { vm.customerId = id }
                        vm.customerDisplayName = str
                        vm.scheduleDraftSave()
                    }
                ))
#if !os(macOS)
                .keyboardType(.numberPad)
#endif
                .accessibilityLabel("Customer ID")
            }
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
            .onChange(of: vm.serviceType) { _, _ in vm.scheduleDraftSave() }
            .accessibilityLabel("Service type selector")

            HStack {
                Text("Duration")
                    .foregroundStyle(.bizarreOnSurface)
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
        Section("Available slots") {
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
            vm.scheduleDraftSave()
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
                .onChange(of: vm.notes) { _, _ in vm.scheduleDraftSave() }
                .accessibilityLabel("Appointment notes")
        }
    }

    private var repeatSection: some View {
        Section {
            Button {
                showRepeatSheet = true
            } label: {
                HStack {
                    Label(
                        vm.repeatRule == nil ? "Does not repeat" : repeatSummary,
                        systemImage: "arrow.clockwise"
                    )
                    .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel("Recurrence: \(vm.repeatRule == nil ? "none" : repeatSummary)")
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
        if let savedAt = vm.draftSavedAt {
            Section {
                Label("Draft saved \(savedAt, style: .time)", systemImage: "doc.badge.clock")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Draft auto-saved at \(savedAt, style: .time)")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel new appointment")
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
            .accessibilityLabel(vm.isSubmitting ? "Saving appointment" : "Save appointment")
        }
    }

    // MARK: - Helpers

    private var repeatSummary: String {
        guard let r = vm.repeatRule else { return "Does not repeat" }
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return "\(r.frequency.rawValue) until \(df.string(from: r.until))"
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) {
            let tf = DateFormatter()
            tf.dateFormat = "h:mm a"
            tf.locale = Locale(identifier: "en_US_POSIX")
            return tf.string(from: d)
        }
        // fallback: return last portion of ISO string
        return String(iso.suffix(8).prefix(5))
    }
}
