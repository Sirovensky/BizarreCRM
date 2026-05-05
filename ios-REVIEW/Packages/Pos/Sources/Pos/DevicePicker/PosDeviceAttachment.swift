import Foundation

// MARK: - PosDeviceAttachment
//
// Lightweight value stored by the caller (PosView) for each cart line that
// is a repair service. The key in the caller's dictionary is `cartLineId`.
//
// NEXT-STEP: wire from PosView.pick(...) when the selected inventory item
//            is_service=true. Show `PosDevicePickerSheet`, then write the
//            resulting attachment into `[UUID: PosDeviceAttachment]` on Cart.

public struct PosDeviceAttachment: Equatable, Sendable {
    /// The `CartItem.id` (UUID) this attachment belongs to.
    public let cartLineId: UUID

    /// The selected `customer_assets.id`, or `nil` when the cashier chose
    /// "No specific device".
    public let deviceOptionId: Int64?

    public init(cartLineId: UUID, deviceOptionId: Int64?) {
        self.cartLineId = cartLineId
        self.deviceOptionId = deviceOptionId
    }

    /// Convenience: `true` when the cashier explicitly chose no device.
    public var isUnspecified: Bool { deviceOptionId == nil }
}
