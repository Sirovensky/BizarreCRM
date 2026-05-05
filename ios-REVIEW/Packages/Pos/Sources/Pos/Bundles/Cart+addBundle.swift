#if canImport(UIKit)
import SwiftUI
import Customers
import DesignSystem
import Core

// MARK: - Cart+addBundle
//
// Extension that resolves a service item's bundle and atomically appends the
// service line plus all required children to the cart in a single array swap.
//
// Spec: docs/pos-redesign-plan.md §4.7
//       docs/pos-implementation-wave.md §Agent F

public extension Cart {

    // MARK: - addBundle

    /// Resolves a service item's bundle children and atomically appends the
    /// service line + required children, all tagged with the same `bundleId`.
    ///
    /// Sequence:
    /// 1. Resolver fetches (or returns cached) bundle definition.
    /// 2. When `resolution.requiresPartPicker == true`, returns a
    ///    `.needsPicker` result so the caller can show a picker modal.
    /// 3. Service line + required children are appended in one `items = items + newLines`
    ///    so a single undo snaps them all back out.
    /// 4. Emits a `.success` haptic + returns a toast string "N lines added".
    ///
    /// - Parameters:
    ///   - serviceItemId:  `inventory_items.id` for the labour/service SKU.
    ///   - serviceRef:     Lightweight ref used to build the `CartItem`.
    ///   - device:         Customer's asset, or `nil` for walk-in.
    ///   - resolver:       Injected `ServiceBundleResolver` actor.
    ///   - quantity:       How many units of the service (default 1).
    /// - Returns: `BundleAddResult` describing what happened.
    @discardableResult
    func addBundle(
        serviceItemId: Int64,
        serviceRef: InventoryItemRef,
        device: CustomerAsset?,
        resolver: ServiceBundleResolver,
        quantity: Int = 1
    ) async throws -> BundleAddResult {
        let qty = max(1, quantity)

        let resolution: BundleResolution
        do {
            resolution = try await resolver.paired(for: serviceItemId, device: device)
        } catch ServiceBundleError.notImplemented {
            AppLog.pos.error("Cart+addBundle: bundle route not implemented — falling back to picker for item \(serviceItemId)")
            return .needsPicker(
                bundleId: UUID(),
                reason: .serverRouteAbsent
            )
        } catch {
            AppLog.pos.error("Cart+addBundle: resolver error for item \(serviceItemId): \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // When a picker is required, return without mutating the cart.
        if resolution.requiresPartPicker {
            return .needsPicker(
                bundleId: resolution.bundleId,
                reason: .deviceNotMatched
            )
        }

        // Build service line.
        let serviceLine = CartItem(
            id: UUID(),
            inventoryItemId: serviceItemId,
            name: serviceRef.name,
            sku: serviceRef.sku,
            quantity: qty,
            unitPrice: Decimal(serviceRef.priceCents) / 100,
            notes: bundleTag(resolution.bundleId)
        )

        // Build required child lines, scaling qty proportionally.
        let childLines: [CartItem] = resolution.required.map { child in
            CartItem(
                id: UUID(),
                inventoryItemId: child.id,
                name: child.name,
                sku: child.sku,
                quantity: qty,       // scale: 2× service → 2× parts
                unitPrice: Decimal(child.priceCents) / 100,
                notes: bundleTag(resolution.bundleId)
            )
        }

        // Atomic append: use addLines(_:) to append all in one array swap,
        // preserving single-undo semantics.
        let newLines = [serviceLine] + childLines
        addLines(newLines)

        // Haptic + toast.
        let totalAdded = newLines.count
        BrandHaptics.success()

        AppLog.pos.info(
            "Cart+addBundle: added \(totalAdded) line(s) (service + \(childLines.count) children) bundleId=\(resolution.bundleId.uuidString, privacy: .public)"
        )

        return .added(
            bundleId: resolution.bundleId,
            linesAdded: totalAdded,
            toastString: "\(totalAdded) \(totalAdded == 1 ? "line" : "lines") added"
        )
    }

    // MARK: - removeBundle

    /// Removes all cart lines tagged with `bundleId`.  Returns the number of
    /// lines removed.  The caller is responsible for showing
    /// `BundleRemoveConfirmation` before calling this.
    @discardableResult
    func removeBundle(bundleId: UUID) -> Int {
        let tag = bundleTag(bundleId)
        let removed = removeLines(withNotesTag: tag)
        if removed > 0 {
            AppLog.pos.info("Cart+removeBundle: removed \(removed) line(s) for bundleId=\(bundleId.uuidString, privacy: .public)")
        }
        return removed
    }

    // MARK: - Private helpers

    /// The notes tag written to every cart line belonging to a bundle.
    /// Format is stable so callers (remove, tests) can reconstruct it.
    nonisolated static func makeBundleTag(_ bundleId: UUID) -> String {
        "bundle:\(bundleId.uuidString)"
    }

    private func bundleTag(_ bundleId: UUID) -> String {
        Cart.makeBundleTag(bundleId)
    }
}

// MARK: - BundleAddResult

/// Describes the outcome of `Cart.addBundle(...)`.
public enum BundleAddResult: Equatable, Sendable {
    /// Lines were appended to the cart.
    case added(bundleId: UUID, linesAdded: Int, toastString: String)
    /// A part-picker modal must be shown before the add can proceed.
    case needsPicker(bundleId: UUID, reason: PickerReason)

    public enum PickerReason: Equatable, Sendable {
        /// No device attached (walk-in).
        case deviceNotMatched
        /// Server route not yet deployed.
        case serverRouteAbsent
    }

    /// Convenience: `true` when lines were added.
    public var didAdd: Bool {
        if case .added = self { return true }
        return false
    }
}
#endif
