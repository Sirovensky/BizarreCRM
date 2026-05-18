import Foundation
import Observation
import Core

// MARK: - RoleDetailViewModel

@Observable
@MainActor
public final class RoleDetailViewModel {

    // MARK: State

    public var role: Role
    public var isSaving = false
    public var errorMessage: String?
    public var hasUnsavedChanges = false

    // MARK: Derived

    public var domainedCapabilities: [(domain: String, capabilities: [Capability])] {
        CapabilityCatalog.byDomain
    }

    // MARK: Dependencies

    private let repository: any RolesRepository
    private let originalCapabilities: Set<String>

    // MARK: Init

    public init(role: Role, repository: any RolesRepository) {
        self.role = role
        self.repository = repository
        self.originalCapabilities = role.capabilities
    }

    // MARK: Capability editing

    public func toggle(capability: String) {
        var caps = role.capabilities
        if caps.contains(capability) {
            caps.remove(capability)
        } else {
            caps.insert(capability)
        }
        role = Role(id: role.id, name: role.name, preset: role.preset, capabilities: caps)
        hasUnsavedChanges = role.capabilities != originalCapabilities
    }

    public func has(capability: String) -> Bool {
        role.capabilities.contains(capability)
    }

    // MARK: Persistence

    public func save() async {
        // BUGHUNT-2026-05-17: re-entry guard — `isSaving` exists as a flag
        // but the Save button doesn't disable on tap in all callsites. A
        // fast double-tap fires two parallel PATCH /roles/:id requests,
        // each writing the same capability set + an audit row. Without the
        // guard the audit log shows two "capability change" rows back to
        // back for what was one user intent.
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            let updated = try await repository.update(role: role, newCapabilities: role.capabilities)
            role = updated
            hasUnsavedChanges = false
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: PATCH may have already committed when
            // the task was cancelled (screen pop, sheet dismiss). The
            // error banner would tempt the user to re-tap Save → second
            // PATCH writes a duplicate audit row for the same change.
            // Stay silent; next loadRole() will reconcile state.
            isSaving = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    public func discard() {
        role = Role(id: role.id, name: role.name, preset: role.preset, capabilities: originalCapabilities)
        hasUnsavedChanges = false
    }

    // MARK: Preset application

    public func applyPreset(_ preset: RolePreset) {
        role = Role(id: role.id, name: role.name, preset: preset.id, capabilities: preset.capabilities)
        hasUnsavedChanges = role.capabilities != originalCapabilities
    }
}
