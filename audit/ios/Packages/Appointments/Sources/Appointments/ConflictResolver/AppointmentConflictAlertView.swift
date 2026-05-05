import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ConflictResolutionOption

public enum ConflictResolutionOption: Sendable, Equatable {
    case changeTech(staffId: Int64)
    case pickAnotherSlot(slot: DateInterval)
    case adminOverride
}

// MARK: - AppointmentConflictAlertViewModel

@MainActor
@Observable
public final class AppointmentConflictAlertViewModel {
    public private(set) var alternativeSlots: [DateInterval] = []
    public private(set) var freeTechs: [StaffOption] = []
    public private(set) var isLoading = false
    public var adminPinInput: String = ""
    public var showPinEntry = false
    public var resolvedOption: ConflictResolutionOption?

    private let correctAdminPin: String
    @ObservationIgnored private let hours: BusinessHoursWeek
    @ObservationIgnored private let busy: [DateInterval]

    public init(
        conflictDate: Date,
        duration: TimeInterval,
        hours: BusinessHoursWeek,
        busy: [DateInterval],
        adminPin: String = "0000"
    ) {
        self.hours = hours
        self.busy = busy
        self.correctAdminPin = adminPin
        alternativeSlots = AvailableSlotFinder.findSlots(
            on: conflictDate,
            duration: duration,
            hours: hours,
            busy: busy
        )
    }

    public func selectTech(_ option: StaffOption) {
        resolvedOption = .changeTech(staffId: option.id)
    }

    public func selectSlot(_ slot: DateInterval) {
        resolvedOption = .pickAnotherSlot(slot: slot)
    }

    public func submitPin() {
        if adminPinInput == correctAdminPin {
            resolvedOption = .adminOverride
            showPinEntry = false
        } else {
            adminPinInput = ""
        }
    }
}

// MARK: - StaffOption

public struct StaffOption: Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public init(id: Int64, name: String) { self.id = id; self.name = name }
}

// MARK: - AppointmentConflictAlertView

/// Shown when a create/reschedule collides. Liquid Glass overlay.
public struct AppointmentConflictAlertView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppointmentConflictAlertViewModel

    private let conflictingInterval: DateInterval
    private let availableTechs: [StaffOption]
    private let onResolve: (ConflictResolutionOption) -> Void

    public init(
        conflictingInterval: DateInterval,
        availableTechs: [StaffOption],
        hours: BusinessHoursWeek,
        busy: [DateInterval],
        adminPin: String = "0000",
        onResolve: @escaping (ConflictResolutionOption) -> Void
    ) {
        self.conflictingInterval = conflictingInterval
        self.availableTechs = availableTechs
        self.onResolve = onResolve
        _vm = State(wrappedValue: AppointmentConflictAlertViewModel(
            conflictDate: conflictingInterval.start,
            duration: conflictingInterval.duration,
            hours: hours,
            busy: busy,
            adminPin: adminPin
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: BrandSpacing.lg) {
                        conflictBanner
                        optionsSection
                    }
                    .padding(BrandSpacing.md)
                }
            }
            .navigationTitle("Scheduling Conflict")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial) // Liquid Glass
        .onChange(of: vm.resolvedOption) { _, option in
            guard let option else { return }
            onResolve(option)
            dismiss()
        }
        .alert("Manager PIN", isPresented: $vm.showPinEntry) {
            SecureField("PIN", text: $vm.adminPinInput)
            Button("Confirm") { vm.submitPin() }
            Button("Cancel", role: .cancel) {
                vm.adminPinInput = ""
                vm.showPinEntry = false
            }
        } message: {
            Text("Enter your 4-digit manager PIN to override the conflict.")
        }
    }

    // MARK: - Sub-views

    private var conflictBanner: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Scheduling conflict")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("The selected time slot is already booked.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduling conflict. The selected time slot is already booked.")
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Resolution options")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            // Option 1 — Change tech
            if !availableTechs.isEmpty {
                GroupBox("Change technician") {
                    VStack(spacing: BrandSpacing.sm) {
                        ForEach(availableTechs) { tech in
                            Button {
                                vm.selectTech(tech)
                            } label: {
                                HStack {
                                    Image(systemName: "person.circle")
                                        .foregroundStyle(.bizarreOrange)
                                        .accessibilityHidden(true)
                                    Text(tech.name)
                                        .font(.brandBodyLarge())
                                        .foregroundStyle(.bizarreOnSurface)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(BrandSpacing.sm)
                                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Assign to \(tech.name)")
                        }
                    }
                }
            }

            // Option 2 — Pick another slot
            if !vm.alternativeSlots.isEmpty {
                GroupBox("Pick another slot") {
                    VStack(spacing: BrandSpacing.sm) {
                        ForEach(vm.alternativeSlots.prefix(5), id: \.start) { slot in
                            Button {
                                vm.selectSlot(slot)
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.bizarreOrange)
                                        .accessibilityHidden(true)
                                    Text(Self.formatSlot(slot))
                                        .font(.brandBodyLarge())
                                        .foregroundStyle(.bizarreOnSurface)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(BrandSpacing.sm)
                                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Pick slot at \(Self.formatSlot(slot))")
                        }
                    }
                }
            }

            // Option 3 — Admin override
            GroupBox("Override (admin)") {
                Button {
                    vm.showPinEntry = true
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                        Text("Override conflict")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreError)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Override conflict — requires manager PIN")
            }
        }
    }

    // MARK: - Helpers

    private static let slotFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static func formatSlot(_ slot: DateInterval) -> String {
        "\(slotFormatter.string(from: slot.start)) – \(slotFormatter.string(from: slot.end))"
    }
}
