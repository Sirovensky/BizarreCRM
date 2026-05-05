import Foundation

// Hashable conformance for ConflictItem so SwiftUI navigation destinations
// and List selection APIs can use it. Keyed by id (unique per conflict row).

extension ConflictItem: Hashable {
    public static func == (lhs: ConflictItem, rhs: ConflictItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
