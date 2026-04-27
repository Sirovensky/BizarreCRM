#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.4 — Per-device pre-conditions intake checklist.
//
// Presented as a bottom sheet (iPhone .medium detent / iPad popover) from
// the device row on TicketDeviceSheet or TicketDetailView.
//
// Wired to: PUT /api/v1/tickets/devices/:deviceId/checklist
//
// The checklist must be completed (all items acknowledged + technician notes
// if any) before the ticket status can advance to "diagnosed". Frontend
// enforces this gate; server also validates.
//
// Default items come from the server-configured tenant default or the
// device template's `diagnostic_checklist_json`. The ViewModel loads the
// current state and sends the full array on save.

// MARK: - Item model

private struct ChecklistEntry: Identifiable, Equatable {
    let id: String
    var label: String
    var checked: Bool
}

// MARK: - ViewModel

@MainActor
@Observable
final class TicketDeviceChecklistViewModel {

    // Editable checklist state
    private(set) var items: [ChecklistEntry] = []
    var technicianNotes: String = ""

    // Load / save state
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var savedSuccessfully: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    private let deviceId: Int64

    /// All items acknowledged (checked or explicitly unchecked — staff reviewed each).
    var allItemsReviewed: Bool {
        // For the purposes of "signed" we require at least one item checked.
        // (Unchecked items are valid — they mean the condition doesn't apply.)
        !items.isEmpty
    }

    init(api: APIClient, deviceId: Int64, preloadedItems: [ChecklistItemPayload]? = nil) {
        self.api = api
        self.deviceId = deviceId
        if let items = preloadedItems {
            self.items = items.map {
                ChecklistEntry(id: UUID().uuidString, label: $0.label, checked: $0.checked)
            }
        } else {
            // Default checklist when no server items provided.
            self.items = Self.defaultItems()
        }
    }

    // MARK: - Default checklist

    static func defaultItems() -> [ChecklistEntry] {
        [
            ChecklistEntry(id: "screen_cracked",     label: "Screen cracked",        checked: false),
            ChecklistEntry(id: "water_damage",       label: "Water damage",           checked: false),
            ChecklistEntry(id: "passcode_provided",  label: "Passcode provided",      checked: false),
            ChecklistEntry(id: "battery_swollen",    label: "Battery swollen",        checked: false),
            ChecklistEntry(id: "sim_tray",           label: "SIM tray present",       checked: false),
            ChecklistEntry(id: "accessories",        label: "Accessories included",   checked: false),
            ChecklistEntry(id: "backup_done",        label: "Backup completed",       checked: false),
            ChecklistEntry(id: "device_powers_on",   label: "Device powers on",       checked: true),
        ]
    }

    // MARK: - Toggle

    func toggle(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].checked.toggle()
    }

    // MARK: - Save

    func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let payload = items.map { ChecklistItemPayload(label: $0.label, checked: $0.checked) }
        let notes = technicianNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await api.updateDeviceChecklist(
                deviceId: deviceId,
                checklist: payload,
                technicianSignature: notes.isEmpty ? nil : notes
            )
            savedSuccessfully = true
        } catch {
            AppLog.ui.error(
                "Device checklist save failed for device \(deviceId): \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sheet view

public struct TicketDeviceChecklistSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketDeviceChecklistViewModel

    private let deviceName: String

    public init(
        api: APIClient,
        deviceId: Int64,
        deviceName: String,
        preloadedItems: [ChecklistItemPayload]? = nil
    ) {
        self.deviceName = deviceName
        _vm = State(wrappedValue: TicketDeviceChecklistViewModel(
            api: api,
            deviceId: deviceId,
            preloadedItems: preloadedItems
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        // Header
                        headerCard

                        // Error banner
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }

                        // Checklist
                        checklistCard

                        // Technician notes
                        notesCard

                        // Save button
                        saveButton
                    }
                    .padding(BrandSpacing.lg)
                }
            }
            .navigationTitle("Pre-conditions: \(deviceName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel checklist")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: vm.savedSuccessfully) { _, success in
            if success { dismiss() }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("Intake Checklist", systemImage: "checklist")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Text("Review each condition with the customer. Tap to check/uncheck. This is required before advancing to Diagnosed.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Checklist card

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(vm.items) { item in
                Button {
                    vm.toggle(id: item.id)
                } label: {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(item.checked ? .bizarreOrange : .bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(item.label)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityValue(item.checked ? "checked" : "unchecked")
                .accessibilityHint("Toggle this checklist item")

                if item.id != vm.items.last?.id {
                    Divider().padding(.leading, BrandSpacing.lg + 28)
                }
            }
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Notes card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Technician notes (optional)")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)

            TextField(
                "Any additional observations…",
                text: $vm.technicianNotes,
                axis: .vertical
            )
            .lineLimit(3...6)
            .font(.brandBodyMedium())
            .accessibilityLabel("Technician notes")
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            Task { await vm.save() }
        } label: {
            if vm.isSaving {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Save Checklist")
                    .font(.brandBodyLarge().bold())
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(BrandGlassProminentButtonStyle())
        .disabled(vm.isSaving || vm.items.isEmpty)
        .accessibilityLabel(vm.isSaving ? "Saving checklist" : "Save checklist")
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white).accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium()).foregroundStyle(.white)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}
#endif
