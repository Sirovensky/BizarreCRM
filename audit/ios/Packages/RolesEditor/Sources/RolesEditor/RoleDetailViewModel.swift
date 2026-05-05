import Foundation
import Observation

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
        isSaving = true
        errorMessage = nil
        do {
            let updated = try await repository.update(role: role, newCapabilities: role.capabilities)
            role = updated
            hasUnsavedChanges = false
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
