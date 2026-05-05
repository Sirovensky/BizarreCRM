import SwiftUI

// §22.G — Rail item value type.

/// Optional badge shown on a rail item.
public enum Badge: Equatable, Sendable {
    /// An unread-count dot (no number).
    case dot
    /// A numeric count (e.g. pending tickets).
    case count(Int)
}

/// A single entry in the rail sidebar.
///
/// Value-type per coding-style rules — immutable, Sendable.
///
/// `title` is a plain `String` (table key) rather than `LocalizedStringKey`
/// because `LocalizedStringKey` does not conform to `Sendable` in Swift 6
/// strict concurrency mode. Views convert to `Text(item.title)` (SwiftUI
/// `Text` looks up localisation automatically from String literals when the
/// string matches a Localizable.strings key).
public struct RailItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// Localisation key — pass to `Text(verbatim:)` or `Text(item.title)`
    /// at the call site. SwiftUI `Text.init(_:)` accepts a `String` and
    /// performs table lookup via the bundle's Localizable.strings.
    public let title: String
    public let systemImage: String
    public let destination: RailDestination
    public let badge: Badge?

    public init(
        id: String,
        title: String,
        systemImage: String,
        destination: RailDestination,
        badge: Badge? = nil
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.destination = destination
        self.badge = badge
    }
}
