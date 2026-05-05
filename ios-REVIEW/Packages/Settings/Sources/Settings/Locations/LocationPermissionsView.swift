import SwiftUI
import Core
import DesignSystem

// MARK: - §60.3 LocationPermissionsView

/// Admin view: per-user × per-location permission matrix.
/// Calls `PATCH /employees/:id/location-access`.
public struct LocationPermissionsView: View {
    @State private var vm: LocationPermissionsViewModel

    public init(repo: any LocationRepository, locations: [Location]) {
        _vm = State(initialValue: LocationPermissionsViewModel(repo: repo, locations: locations))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadMatrix
            }
        }
        .navigationTitle("Location Permissions")
        .task { await vm.load() }
        .overlay {
            if vm.isSaving {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            }
        }
    }

    // MARK: iPhone — nested navigation

    private var iPhoneList: some View {
        List(vm.employeeIds, id: \.self) { empId in
            Section(empId) {
                ForEach(vm.locations) { loc in
                    if let entry = vm.entry(employeeId: empId, locationId: loc.id) {
                        PermissionRow(entry: entry, locationName: loc.name) { updated in
                            Task { await vm.update(entry: updated) }
                        }
                    }
                }
            }
        }
    }

    private var iPhoneLayout: some View {
        iPhoneList
    }

    // MARK: iPad — matrix

    private var iPadMatrix: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: DesignTokens.Spacing.md, verticalSpacing: DesignTokens.Spacing.xs) {
                // Header row
                GridRow {
                    Text("Employee")
                        .font(.headline)
                        .frame(width: 160, alignment: .leading)
                    ForEach(vm.locations) { loc in
                        Text(loc.name)
                            .font(.headline)
                            .frame(width: 100)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                Divider()

                // Data rows
                ForEach(vm.employeeIds, id: \.self) { empId in
                    GridRow {
                        Text(empId)
                            .font(.subheadline)
                            .frame(width: 160, alignment: .leading)
                            .textSelection(.enabled)

                        ForEach(vm.locations) { loc in
                            if let entry = vm.entry(employeeId: empId, locationId: loc.id) {
                                CapabilityToggle(entry: entry) { updated in
                                    Task { await vm.update(entry: updated) }
                                }
                                .frame(width: 100)
                            } else {
                                Text("—")
                                    .frame(width: 100)
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }
}

// MARK: - Sub-views

private struct PermissionRow: View {
    let entry: LocationAccessEntry
    let locationName: String
    let onToggle: (LocationAccessEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(locationName)
                .font(.subheadline.bold())
            HStack(spacing: DesignTokens.Spacing.md) {
                Toggle("View", isOn: Binding(
                    get: { entry.canView },
                    set: { newVal in
                        var e = entry; e = LocationAccessEntry(
                            employeeId: e.employeeId, locationId: e.locationId,
                            canView: newVal, canEdit: e.canEdit, canManage: e.canManage)
                        onToggle(e)
                    }
                ))
                Toggle("Edit", isOn: Binding(
                    get: { entry.canEdit },
                    set: { newVal in
                        var e = entry; e = LocationAccessEntry(
                            employeeId: e.employeeId, locationId: e.locationId,
                            canView: e.canView, canEdit: newVal, canManage: e.canManage)
                        onToggle(e)
                    }
                ))
                Toggle("Manage", isOn: Binding(
                    get: { entry.canManage },
                    set: { newVal in
                        var e = entry; e = LocationAccessEntry(
                            employeeId: e.employeeId, locationId: e.locationId,
                            canView: e.canView, canEdit: e.canEdit, canManage: newVal)
                        onToggle(e)
                    }
                ))
            }
            .toggleStyle(.button)
        }
    }
}

private struct CapabilityToggle: View {
    let entry: LocationAccessEntry
    let onToggle: (LocationAccessEntry) -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            capabilityButton("V", active: entry.canView) {
                onToggle(LocationAccessEntry(
                    employeeId: entry.employeeId, locationId: entry.locationId,
                    canView: !entry.canView, canEdit: entry.canEdit, canManage: entry.canManage
                ))
            }
            capabilityButton("E", active: entry.canEdit) {
                onToggle(LocationAccessEntry(
                    employeeId: entry.employeeId, locationId: entry.locationId,
                    canView: entry.canView, canEdit: !entry.canEdit, canManage: entry.canManage
                ))
            }
            capabilityButton("M", active: entry.canManage) {
                onToggle(LocationAccessEntry(
                    employeeId: entry.employeeId, locationId: entry.locationId,
                    canView: entry.canView, canEdit: entry.canEdit, canManage: !entry.canManage
                ))
            }
        }
    }

    @ViewBuilder
    private func capabilityButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 28, height: 22)
                .foregroundStyle(active ? .bizarreOnOrange : .bizarreOnSurfaceMuted)
                .background(active ? Color.bizarreOrange : Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
        }
        .buttonStyle(.plain)
        .brandHover()
        .accessibilityLabel("\(label) capability \(active ? "on" : "off")")
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class LocationPermissionsViewModel {
    private(set) var entries: [LocationAccessEntry] = []
    let locations: [Location]
    private(set) var isSaving: Bool = false

    private let repo: any LocationRepository

    init(repo: any LocationRepository, locations: [Location]) {
        self.repo = repo
        self.locations = locations
    }

    var employeeIds: [String] {
        Array(Set(entries.map(\.employeeId))).sorted()
    }

    func entry(employeeId: String, locationId: String) -> LocationAccessEntry? {
        entries.first(where: { $0.employeeId == employeeId && $0.locationId == locationId })
    }

    func load() async {
        // Load access for all known employees at all locations
        for loc in locations {
            do {
                // Fetch access for location — server returns all employee entries for given location
                let locEntries = try await repo.fetchLocationAccess(employeeId: loc.id)
                let merged = locEntries.filter { new in
                    !entries.contains(where: { $0.id == new.id })
                }
                entries = entries + merged
            } catch {
                // Non-fatal
            }
        }
    }

    func update(entry: LocationAccessEntry) async {
        // Optimistic local update
        entries = entries.map { $0.id == entry.id ? entry : $0 }
        isSaving = true
        defer { isSaving = false }
        do {
            let empEntries = entries.filter { $0.employeeId == entry.employeeId }
            let updated = try await repo.updateLocationAccess(
                employeeId: entry.employeeId,
                entries: empEntries
            )
            entries = entries.map { old in
                updated.first(where: { $0.id == old.id }) ?? old
            }
        } catch {
            // Revert optimistic on failure by reloading
            await load()
        }
    }
}
