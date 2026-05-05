import Foundation

// MARK: - RolePresetDescriptor
//
// §47 Roles Capability Presets — value type that describes a canonical preset.
// Deliberately separate from the legacy RolePreset in RolePresets.swift so
// no existing file is touched.  The six canonical presets are defined in
// RolePresetCatalog.swift.

/// A named, immutable preset that bundles a description and a capability set.
/// Pure value type — no reference semantics, safe to capture across actors.
public struct RolePresetDescriptor: Sendable, Hashable, Identifiable {

    // MARK: Stored properties

    /// Stable identifier used for persistence (e.g. `"preset.owner"`).
    public let id: String

    /// Human-readable display name shown in the picker and sheet header.
    public let name: String

    /// One-sentence description of the typical use-case for this preset.
    public let description: String

    /// Full set of capability ids granted by this preset.
    public let capabilities: Set<String>

    // MARK: Init

    public init(id: String, name: String, description: String, capabilities: Set<String>) {
        self.id = id
        self.name = name
        self.description = description
        self.capabilities = capabilities
    }

    // MARK: Derived helpers

    /// Returns a new Role seeded from this preset using a fresh UUID.
    public func makeRole() -> Role {
        Role(id: UUID().uuidString, name: name, preset: id, capabilities: capabilities)
    }

    /// Diff relative to the given current capability set.
    /// Positive: capabilities that will be added; negative: capabilities removed.
    public func diff(from current: Set<String>) -> PresetCapabilityDiff {
        PresetCapabilityDiff(added: capabilities.subtracting(current),
                             removed: current.subtracting(capabilities))
    }
}
