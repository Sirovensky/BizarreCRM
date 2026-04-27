import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.6 Ticket Status Taxonomy settings
//
// Admin tool for managing custom ticket statuses: re-order, rename, add, archive.
// Server endpoints: GET/POST/PATCH/DELETE /settings/statuses
// Each status has a name, color, and position; new tickets use the "default" status.

// MARK: - Models

public struct TicketStatus: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public var name: String
    public var color: String      // hex e.g. "#FF6200"
    public var position: Int
    public var isDefault: Bool
    public var isArchived: Bool

    public init(id: Int, name: String, color: String = "#FF6200",
                position: Int = 0, isDefault: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.position = position
        self.isDefault = isDefault
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, position
        case isDefault  = "is_default"
        case isArchived = "is_archived"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketStatusSettingsViewModel {
    public private(set) var statuses: [TicketStatus] = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public var errorMessage: String?

    // Add new status sheet state
    public var newStatusName: String = ""
    public var newStatusColor: String = "#FF6200"
    public var showAddSheet = false

    // Edit sheet state
    public var editingStatus: TicketStatus?
    public var showEditSheet = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            statuses = try await api.listTicketStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addStatus() async {
        guard !newStatusName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Status name cannot be empty."; return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let created = try await api.createTicketStatus(
                name: newStatusName.trimmingCharacters(in: .whitespaces),
                color: newStatusColor
            )
            statuses.append(created)
            statuses.sort { $0.position < $1.position }
            newStatusName = ""
            newStatusColor = "#FF6200"
            showAddSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateStatus(_ status: TicketStatus) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await api.updateTicketStatus(status)
            if let idx = statuses.firstIndex(where: { $0.id == status.id }) {
                statuses[idx] = updated
            }
            showEditSheet = false
            editingStatus = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reorder statuses after drag-drop. Sends PATCH with new positions.
    public func move(from source: IndexSet, to destination: Int) {
        statuses.move(fromOffsets: source, toOffset: destination)
        // Update position values to match new order.
        for (idx, var status) in statuses.enumerated() {
            status.position = idx
            statuses[idx] = status
        }
        // Fire-and-forget position update.
        Task { [weak self] in
            guard let self else { return }
            _ = try? await api.reorderTicketStatuses(statuses.map { $0.id })
        }
    }

    public func setDefault(_ status: TicketStatus) async {
        var updated = status
        updated.isDefault = true
        await updateStatus(updated)
        // Clear default flag from all others locally.
        for idx in statuses.indices where statuses[idx].id != status.id {
            statuses[idx].isDefault = false
        }
    }

    public func toggleArchive(_ status: TicketStatus) async {
        var updated = status
        updated.isArchived = !status.isArchived
        await updateStatus(updated)
    }
}

// MARK: - Endpoints (additive — Agent 9 owns APIClient+Notifications.swift, but
//          ticket-statuses touches Settings scope; adding to APIClient+Notifications
//          would be incorrect domain. Using the Settings-scoped SettingsPageEndpoints file.)

extension APIClient {
    func listTicketStatuses() async throws -> [TicketStatus] {
        let resp = try await get("/api/v1/settings/statuses", as: TicketStatusListResponse.self)
        return resp.statuses
    }

    func createTicketStatus(name: String, color: String) async throws -> TicketStatus {
        struct Body: Encodable { let name: String; let color: String }
        return try await post("/api/v1/settings/statuses", body: Body(name: name, color: color), as: TicketStatus.self)
    }

    func updateTicketStatus(_ status: TicketStatus) async throws -> TicketStatus {
        return try await patch("/api/v1/settings/statuses/\(status.id)", body: status, as: TicketStatus.self)
    }

    func reorderTicketStatuses(_ ids: [Int]) async throws {
        struct Body: Encodable { let order: [Int] }
        struct Ack: Decodable {}
        _ = try? await post("/api/v1/settings/statuses/reorder", body: Body(order: ids), as: Ack.self)
    }
}

private struct TicketStatusListResponse: Decodable {
    let statuses: [TicketStatus]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.statuses = (try? c.decode([TicketStatus].self, forKey: .statuses))
            ?? (try? c.decode([TicketStatus].self, forKey: .data)) ?? []
    }
    enum CodingKeys: String, CodingKey { case statuses, data }
}

// MARK: - View

public struct TicketStatusSettingsPage: View {
    @State private var vm: TicketStatusSettingsViewModel
    @State private var showArchived = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: TicketStatusSettingsViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                activeSection
                if showArchived {
                    archivedSection
                }
                if vm.statuses.filter(\.isArchived).count > 0 {
                    Section {
                        Toggle("Show archived", isOn: $showArchived)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Ticket Statuses")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add status")
                .accessibilityIdentifier("ticketStatus.add")
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showAddSheet) { addSheet }
        .sheet(isPresented: $vm.showEditSheet) {
            if let status = vm.editingStatus {
                EditStatusSheet(status: status) { updated in
                    Task { await vm.updateStatus(updated) }
                } onCancel: {
                    vm.showEditSheet = false; vm.editingStatus = nil
                }
            }
        }
        .overlay {
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.bizarreSurfaceBase.opacity(0.5))
            }
        }
    }

    private var activeSection: some View {
        Section {
            ForEach(vm.statuses.filter { !$0.isArchived }) { status in
                StatusRow(status: status) {
                    vm.editingStatus = status
                    vm.showEditSheet = true
                } onSetDefault: {
                    Task { await vm.setDefault(status) }
                } onArchive: {
                    Task { await vm.toggleArchive(status) }
                }
            }
            .onMove { source, dest in vm.move(from: source, to: dest) }
        } header: {
            Text("Active statuses — drag to reorder")
        } footer: {
            Text("The default status is assigned to new tickets. Tap a status to rename or change its color.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        let archived = vm.statuses.filter(\.isArchived)
        if !archived.isEmpty {
            Section("Archived") {
                ForEach(archived) { status in
                    StatusRow(status: status) {
                        vm.editingStatus = status
                        vm.showEditSheet = true
                    } onSetDefault: {
                        Task { await vm.setDefault(status) }
                    } onArchive: {
                        Task { await vm.toggleArchive(status) }
                    }
                }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("New Status") {
                        TextField("Status name", text: $vm.newStatusName)
                            .autocorrectionDisabled()
                            .listRowBackground(Color.bizarreSurface1)
                            .accessibilityIdentifier("newStatus.name")
                        ColorPickerRow(hex: $vm.newStatusColor)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Status")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await vm.addStatus() }
                    }
                    .disabled(vm.newStatusName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("newStatus.confirm")
                }
            }
        }
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let status: TicketStatus
    let onEdit: () -> Void
    let onSetDefault: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Circle()
                .fill(Color(hex: status.color) ?? .bizarreOrange)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(status.name)
                .font(.brandBodyMedium())
                .foregroundStyle(status.isArchived ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
            Spacer()
            if status.isDefault {
                Text("Default")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.bizarreOrange.opacity(0.12), in: Capsule())
            }
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .swipeActions(edge: .leading) {
            if !status.isDefault && !status.isArchived {
                Button {
                    onSetDefault()
                } label: {
                    Label("Set Default", systemImage: "star.fill")
                }
                .tint(.bizarreOrange)
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                onArchive()
            } label: {
                Label(status.isArchived ? "Restore" : "Archive", systemImage: status.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(status.isArchived ? .bizarreTeal : .bizarreWarning)
        }
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.name)\(status.isDefault ? ", default" : "")\(status.isArchived ? ", archived" : "")")
    }
}

// MARK: - Edit Status Sheet

private struct EditStatusSheet: View {
    @State var status: TicketStatus
    let onSave: (TicketStatus) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Edit Status") {
                        TextField("Status name", text: $status.name)
                            .autocorrectionDisabled()
                            .listRowBackground(Color.bizarreSurface1)
                        ColorPickerRow(hex: $status.color)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Status")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(status) }
                        .disabled(status.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Color picker row (hex-coded)

private struct ColorPickerRow: View {
    @Binding var hex: String

    private let presets = ["#FF6200", "#4DB8C9", "#E91E8C", "#4CAF50", "#9C27B0",
                           "#F44336", "#FF9800", "#2196F3", "#607D8B", "#795548"]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Color")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(presets, id: \.self) { preset in
                        Circle()
                            .fill(Color(hex: preset) ?? .gray)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().strokeBorder(
                                    hex == preset ? Color.white : Color.clear,
                                    lineWidth: 2
                                )
                            )
                            .onTapGesture { hex = preset }
                            .accessibilityLabel("Color \(preset)")
                    }
                }
            }
        }
    }
}

// MARK: - Color+hex init

private extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#if DEBUG
// Preview requires a live APIClient — omitted for build safety.
// Test via TicketStatusSettingsPage(api: <injected>) in Preview target.
#endif
