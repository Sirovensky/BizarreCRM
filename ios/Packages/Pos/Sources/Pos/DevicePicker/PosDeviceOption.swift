import Foundation

// MARK: - PosDeviceOption
//
// Represents a single row in the device-picker sheet presented when selling
// a repair service. Three cases cover the full picker surface:
//   • .asset    — a saved device belonging to the attached customer
//   • .noSpecificDevice — "No specific device" sentinel row
//   • .addNew   — CTA that opens the asset-creation flow

public enum PosDeviceOption: Equatable, Sendable, Identifiable {
    /// A saved customer asset. `id` is the `customer_assets.id` PK.
    case asset(id: Int64, label: String, subtitle: String?)
    /// The cashier chose not to link a device to this repair line.
    case noSpecificDevice
    /// CTA: open the add-new-device flow (handled by the caller).
    case addNew

    // MARK: Identifiable

    public var id: String {
        switch self {
        case .asset(let assetId, _, _):
            return "asset-\(assetId)"
        case .noSpecificDevice:
            return "no-specific-device"
        case .addNew:
            return "add-new"
        }
    }

    // MARK: Convenience

    /// The asset id for `.asset` rows; `nil` for sentinel rows.
    public var assetId: Int64? {
        guard case .asset(let id, _, _) = self else { return nil }
        return id
    }

    /// Human-readable primary label shown in the list row.
    public var displayLabel: String {
        switch self {
        case .asset(_, let label, _):
            return label
        case .noSpecificDevice:
            return "No specific device"
        case .addNew:
            return "Add a new device"
        }
    }

    /// Optional secondary line shown beneath the primary label.
    public var displaySubtitle: String? {
        guard case .asset(_, _, let subtitle) = self else { return nil }
        return subtitle
    }

    /// SF Symbol name for the leading icon.
    public var systemImage: String {
        switch self {
        case .asset:
            return "iphone"
        case .noSpecificDevice:
            return "questionmark.circle"
        case .addNew:
            return "plus.circle.fill"
        }
    }
}
