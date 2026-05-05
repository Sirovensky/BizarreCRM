import Foundation

/// §16.16 — A single quick-sale hotkey entry.
/// `unitPriceCents` is stored so the tile can add to cart without a catalog lookup.
public struct QuickSaleHotkey: Identifiable, Codable, Equatable, Sendable {
    public let id:             UUID
    public let sku:            String?
    public let displayName:    String
    public let unitPriceCents: Int
    public let inventoryId:    Int64?

    public init(
        id:             UUID   = UUID(),
        sku:            String? = nil,
        displayName:    String,
        unitPriceCents: Int,
        inventoryId:    Int64? = nil
    ) {
        self.id             = id
        self.sku            = sku
        self.displayName    = displayName
        self.unitPriceCents = max(0, unitPriceCents)
        self.inventoryId    = inventoryId
    }
}

/// §16.16 — Tenant-configurable collection of exactly 3 quick-sale hotkeys.
/// Persisted in `UserDefaults` (migrated to GRDB in a later phase).
public struct QuickSaleHotkeys: Codable, Sendable {
    /// Always exactly 3 entries; nil slots render as disabled tiles.
    public var slots: [QuickSaleHotkey?]

    public static let empty = QuickSaleHotkeys(slots: [nil, nil, nil])

    public init(slots: [QuickSaleHotkey?]) {
        // Clamp to exactly 3 slots.
        var padded = Array(slots.prefix(3))
        while padded.count < 3 { padded.append(nil) }
        self.slots = padded
    }

    /// Replace the hotkey at `index` (0-based). Out-of-range is a no-op.
    public func setting(_ hotkey: QuickSaleHotkey?, at index: Int) -> QuickSaleHotkeys {
        guard index >= 0 && index < 3 else { return self }
        var copy = slots
        copy[index] = hotkey
        return QuickSaleHotkeys(slots: copy)
    }
}

// MARK: - Persistence

/// Actor-isolated store for quick-sale hotkeys.
public actor QuickSaleHotkeyStore {
    public static let shared = QuickSaleHotkeyStore()

    private let defaults: UserDefaults
    private let key      = "pos_quick_sale_hotkeys"
    private let encoder  = JSONEncoder()
    private let decoder  = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> QuickSaleHotkeys {
        guard let data = defaults.data(forKey: key),
              let hotkeys = try? decoder.decode(QuickSaleHotkeys.self, from: data)
        else { return .empty }
        return hotkeys
    }

    public func save(_ hotkeys: QuickSaleHotkeys) {
        guard let data = try? encoder.encode(hotkeys) else { return }
        defaults.set(data, forKey: key)
    }
}
