import Foundation

// MARK: - BundleResolution
//
// Produced by `ServiceBundleResolver.paired(for:device:)`.  Describes
// which children a service line must (required) or may (optional) bring
// into the cart.
//
// Spec: docs/pos-redesign-plan.md §4.7
//       docs/pos-implementation-wave.md §Agent F

/// The result of resolving a service item's bundle children for a specific
/// device context.
///
/// - `required`:  Children that are auto-added with the service line in a
///   single atomic cart transaction.
/// - `optional`:  Siblings presented as "tap to add" chips below the cart
///   row — never silently added.
/// - `bundleId`:  Client-generated identifier that tags all lines belonging
///   to the same bundle so undo and removal can be atomic.
/// - `requiresPartPicker`: When `true` the caller must present a modal
///   part-picker before the add can proceed (walk-in, unknown device, or
///   device model not in BOM map).
public struct BundleResolution: Equatable, Sendable {
    /// Auto-added items. May be empty for services with no BOM data.
    public let required: [InventoryItemRef]
    /// Chip-presented optional siblings.
    public let optional: [InventoryItemRef]
    /// Stable identifier shared by the service line and all its children.
    public let bundleId: UUID
    /// When `true` the UI should present a part-picker modal before adding.
    public let requiresPartPicker: Bool

    public init(
        required: [InventoryItemRef] = [],
        optional: [InventoryItemRef] = [],
        bundleId: UUID = UUID(),
        requiresPartPicker: Bool = false
    ) {
        self.required = required
        self.optional = optional
        self.bundleId = bundleId
        self.requiresPartPicker = requiresPartPicker
    }
}

// MARK: - Convenience

public extension BundleResolution {
    /// An empty resolution with no children and no picker requirement.
    static func empty(bundleId: UUID = UUID()) -> BundleResolution {
        BundleResolution(
            required: [],
            optional: [],
            bundleId: bundleId,
            requiresPartPicker: false
        )
    }

    /// A resolution that signals to the caller that a part-picker is needed
    /// before the cart add may proceed.
    static func needsPicker(bundleId: UUID = UUID()) -> BundleResolution {
        BundleResolution(
            required: [],
            optional: [],
            bundleId: bundleId,
            requiresPartPicker: true
        )
    }

    /// Total number of lines that would be added (service + required children).
    /// Used for the "N lines added" toast.
    var totalLinesAdded: Int {
        // The service line itself is counted by the caller; this is children only.
        required.count
    }

    /// `true` when there are no children at all (required or optional).
    var isEmpty: Bool { required.isEmpty && optional.isEmpty }
}
