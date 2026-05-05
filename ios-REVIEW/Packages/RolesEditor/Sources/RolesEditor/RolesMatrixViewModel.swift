import Foundation
import Observation
import Factory

// MARK: - RolesMatrixViewModel

@Observable
@MainActor
public final class RolesMatrixViewModel {

    // MARK: Published state

    public var roles: [Role] = []
    public var isLoading = false
    public var errorMessage: String?

    /// When non-nil, the UI is in "Preview as role" mode.
    public var activePreviewRoleId: String?

    /// Callback invoked when preview role changes. Host app wires this to
    /// switch the live-session preview persona (§47.3).
    public var onPreviewRoleChanged: ((String?) -> Void)?

    // MARK: Derived

    /// The domains in display order, sourced from the catalog.
    public var domains: [(domain: String, capabilities: [Capability])] {
        CapabilityCatalog.byDomain
    }

    public var activePreviewRole: Role? {
        guard let id = activePreviewRoleId else { return nil }
        return roles.first { $0.id == id }
    }

    // MARK: Dependencies

    public let repository: any RolesRepository

    // MARK: Init

    public nonisolated init(repository: any RolesRepository) {
        self.repository = repository
    }

    // MARK: Load

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            roles = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: Load single role (with capabilities)

    /// Fetches the full capability matrix for a role and updates the roles array.
    public func loadRole(id: String) async {
        errorMessage = nil
        do {
            let role = try await repository.fetchOne(id: id)
            if let idx = roles.firstIndex(where: { $0.id == id }) {
                roles[idx] = role
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Capability toggle (§47.4 — every toggle produces a PATCH)

    /// Toggles a single capability on a role and PATCHes the server immediately.
    public func toggle(capability: String, on role: Role) async {
        var newCaps = role.capabilities
        if newCaps.contains(capability) {
            newCaps.remove(capability)
        } else {
            newCaps.insert(capability)
        }
        await applyCapabilityUpdate(role: role, newCapabilities: newCaps)
    }

    /// Replaces all capabilities on a role with the given set.
    public func setCapabilities(_ capabilities: Set<String>, on role: Role) async {
        await applyCapabilityUpdate(role: role, newCapabilities: capabilities)
    }

    // MARK: Preview (§47.3)

    public func startPreview(roleId: String) {
        activePreviewRoleId = roleId
        onPreviewRoleChanged?(roleId)
    }

    public func exitPreview() {
        activePreviewRoleId = nil
        onPreviewRoleChanged?(nil)
    }

    // MARK: Create / Delete

    public func createRole(name: String, description: String? = nil, preset: String? = nil, capabilities: Set<String> = []) async {
        isLoading = true
        errorMessage = nil
        do {
            let role = try await repository.create(name: name, description: description, capabilities: capabilities)
            roles.append(role)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func deleteRole(_ role: Role) async {
        isLoading = true
        errorMessage = nil
        do {
            try await repository.delete(roleId: role.id)
            roles.removeAll { $0.id == role.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Clone a role into a new custom role (§47.2 CustomRoleClone).
    public func cloneRole(_ role: Role, newName: String) async {
        let cloned = RolePresets.cloneRole(role, newName: newName)
        await createRole(name: cloned.name, preset: nil, capabilities: cloned.capabilities)
    }

    // MARK: §47.9 Revocation subscription

    public func subscribeToRolesChangedNotification() {
        NotificationCenter.default.addObserver(
            forName: .rolesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    // MARK: Private

    private func applyCapabilityUpdate(role: Role, newCapabilities: Set<String>) async {
        errorMessage = nil
        do {
            let updated = try await repository.update(role: role, newCapabilities: newCapabilities)
            if let idx = roles.firstIndex(where: { $0.id == role.id }) {
                roles[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() async {
        do {
            roles = try await repository.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Factory DI

public extension Container {
    var rolesMatrixViewModel: Factory<RolesMatrixViewModel> {
        self {
            RolesMatrixViewModel(repository: self.rolesRepository())
        }
    }
}
