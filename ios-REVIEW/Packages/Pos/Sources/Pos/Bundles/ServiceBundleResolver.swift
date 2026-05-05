import Foundation
import Customers
import Core

// MARK: - ServiceBundleResolver
//
// Actor that resolves a service item's bundle children with device-aware
// filtering.
//
// Spec: docs/pos-redesign-plan.md §4.7
//       docs/pos-implementation-wave.md §Agent F
//
// Thread-safety: actor isolation guarantees that concurrent calls for the
// same item do not race on the shared cache.

/// Device-aware service bundle resolver.
///
/// Given a service item (e.g. "Labour · Screen Replacement") and an optional
/// customer asset, produces a `BundleResolution` describing which required and
/// optional children to add to the cart.
///
/// Device-aware filtering rules:
/// 1. Device is known (`device != nil`): filter required children to only
///    those whose SKU or name fuzzy-matches the device's make/model.  If
///    after filtering the required list is empty but the raw list was non-empty,
///    set `requiresPartPicker = true` — the BOM exists but no part matched.
/// 2. Device is nil (walk-in / no device attached): always set
///    `requiresPartPicker = true` so the cashier can pick the right part.
public actor ServiceBundleResolver {

    // MARK: - Dependencies

    private let repository: any ServiceBundleRepository

    // MARK: - Cache
    //
    // Responses are cached by serviceItemId for the lifetime of this actor.
    // Cache is intentionally simple (no TTL) because the resolver is created
    // per-sale session and the catalog doesn't change mid-session.

    private var cache: [Int64: BundleResolution] = [:]

    // MARK: - Init

    public init(repository: any ServiceBundleRepository) {
        self.repository = repository
    }

    // MARK: - Public API

    /// Resolves the bundle children for a service item in the context of
    /// an optional customer device.
    ///
    /// - Parameters:
    ///   - serviceItemId: `inventory_items.id` of the service / labour line.
    ///   - device: The customer's device if known, or `nil` for walk-in.
    /// - Returns: A `BundleResolution` ready for `Cart.addBundle(...)`.
    /// - Throws: Propagates `ServiceBundleError` from the repository.
    public func paired(
        for serviceItemId: Int64,
        device: CustomerAsset?
    ) async throws -> BundleResolution {
        // 1. Fetch raw (unfiltered) bundle, using cache when available.
        let raw = try await rawBundle(for: serviceItemId)

        // 2. Walk-in or no device → part picker required.
        guard let device else {
            AppLog.pos.debug("ServiceBundleResolver: no device — picker required for item \(serviceItemId)")
            return BundleResolution(
                required: [],
                optional: raw.optional,
                bundleId: raw.bundleId,
                requiresPartPicker: true
            )
        }

        // 3. Device is known → filter required children.
        let filtered = filterRequired(raw.required, for: device)

        // 4. Raw had required items but none matched the device → picker.
        if !raw.required.isEmpty && filtered.isEmpty {
            AppLog.pos.debug(
                "ServiceBundleResolver: device '\(device.name, privacy: .public)' not in BOM — picker required for item \(serviceItemId)"
            )
            return BundleResolution(
                required: [],
                optional: raw.optional,
                bundleId: raw.bundleId,
                requiresPartPicker: true
            )
        }

        // 5. Happy path — return filtered required + all optional siblings.
        AppLog.pos.debug(
            "ServiceBundleResolver: resolved \(filtered.count) required + \(raw.optional.count) optional for item \(serviceItemId)"
        )
        return BundleResolution(
            required: filtered,
            optional: raw.optional,
            bundleId: raw.bundleId,
            requiresPartPicker: false
        )
    }

    /// Clears the in-memory cache. Call at the start of a new sale session
    /// if the actor is reused across sales.
    public func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private helpers

    private func rawBundle(for serviceItemId: Int64) async throws -> BundleResolution {
        if let cached = cache[serviceItemId] { return cached }
        let resolution = try await repository.fetchBundle(serviceItemId: serviceItemId)
        cache[serviceItemId] = resolution
        return resolution
    }

    /// Returns required children that are compatible with `device`.
    ///
    /// Matching strategy (case-insensitive):
    /// - Child name contains device name tokens (e.g. "iPhone 14 Pro").
    /// - Child SKU contains device type prefix from the name.
    ///
    /// When the device name is empty or cannot be parsed, all required
    /// children pass through (no filtering applied).
    private func filterRequired(
        _ items: [InventoryItemRef],
        for device: CustomerAsset
    ) -> [InventoryItemRef] {
        let deviceName = device.name.trimmingCharacters(in: .whitespaces)
        guard !deviceName.isEmpty else { return items }

        // Tokenize device name into meaningful words (drop short words like "the").
        let tokens = deviceName
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 2 }

        guard !tokens.isEmpty else { return items }

        return items.filter { ref in
            let refName = ref.name.lowercased()
            let refSku  = ref.sku.lowercased()
            return tokens.allSatisfy { token in
                refName.contains(token) || refSku.contains(token)
            }
        }
    }
}
