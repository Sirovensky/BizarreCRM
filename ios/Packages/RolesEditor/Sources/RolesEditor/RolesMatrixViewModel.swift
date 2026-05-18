import Foundation
import Observation
import Factory
import Core

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

    // BUGHUNT-2026-05-17: NotificationCenter observer token, captured so
    // subscribeToRolesChangedNotification can dedup repeat subscriptions and
    // unsubscribe() can be called explicitly from view onDisappear. Without
    // this, every call (one per view appear) registered a new observer
    // whose [weak self] closure went no-op once the VM died — but the
    // registration itself stayed in NotificationCenter forever, so the
    // .rolesChanged fan-out cost grew linearly with screen visits.
    @ObservationIgnored
    private var rolesChangedObserver: NSObjectProtocol?

    // MARK: Init

    public nonisolated init(repository: any RolesRepository) {
        self.repository = repository
    }

    /// Call from `onDisappear` of any view that previously invoked
    /// [subscribeToRolesChangedNotification] so the observer is released
    /// before the VM is dropped. A MainActor `deinit` can't safely access
    /// the token under Swift 6 strict concurrency, so cleanup is explicit.
    public func unsubscribeFromRolesChangedNotification() {
        if let token = rolesChangedObserver {
            NotificationCenter.default.removeObserver(token)
            rolesChangedObserver = nil
        }
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
        // BUGHUNT-2026-05-17: re-entry guard — Create-Role sheet's primary
        // action does not disable on tap, so a fast double-tap or
        // SwiftUI-replay would fire createRole twice. POST is not
        // idempotent (no key on the route) → two roles with the same name
        // and same capability set get created; the second tenant audit row
        // is misleading evidence of duplicate-admin intent.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let role = try await repository.create(name: name, description: description, capabilities: capabilities)
            roles.append(role)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: POST may have already created the role
            // server-side when the task was cancelled (sheet dismissed
            // before the response arrived). A red banner would tempt the
            // user to tap Create again → second duplicate role. Stay
            // silent; next list reload reconciles.
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func deleteRole(_ role: Role) async {
        // BUGHUNT-2026-05-17: re-entry guard — confirmation dialog's
        // destructive action isn't disabled on tap. Double-tap → two
        // DELETE requests; the second 404s but the audit trail still
        // records a "delete attempt" on a missing role, which security
        // review reads as a misconfiguration probe.
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await repository.delete(roleId: role.id)
            roles.removeAll { $0.id == role.id }
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: DELETE may have committed server-side
            // before the task was cancelled. A red banner misleads —
            // the role may already be gone. Stay silent.
            isLoading = false
            return
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
        // BUGHUNT-2026-05-17: remove any prior registration so calling this
        // method twice (e.g. on view re-appear) doesn't stack observers.
        // The captured token now lives in `rolesChangedObserver` and is
        // removed in deinit too.
        if let existing = rolesChangedObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        rolesChangedObserver = NotificationCenter.default.addObserver(
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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: capability toggle PATCH is audited
            // server-side. If the PATCH committed but the task was
            // cancelled (column switch, screen tear-down, .rolesChanged
            // refresh racing in), surfacing an error tempts a retry tap
            // → second PATCH writes a second audit row for the same
            // permission change. Stay silent; the next loadRole()
            // reconciles state.
            return
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
