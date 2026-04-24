#if canImport(CarPlay)
import CarPlay
import Foundation

// MARK: - CarPlayDashboardItem

/// An immutable value type that describes a single row in a CarPlay list
/// template (e.g. a voicemail entry or a recent-calls row).
///
/// - `title`                 Primary label rendered in the CarPlay list cell.
/// - `subtitle`              Secondary label (caller ID, duration, timestamp).
/// - `imageName`             SF Symbol name used for the leading icon.
/// - `deepLinkDestination`   Where the app should navigate when the row is tapped.
///
/// The type is intentionally free of any CarPlay SDK references so that it
/// remains unit-testable without a simulator entitlement.
public struct CarPlayDashboardItem: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// Primary display label (e.g. caller name, call-log entry).
    public let title: String

    /// Secondary display label (e.g. duration, timestamp). May be empty.
    public let subtitle: String

    /// SF Symbol name for the row's leading icon.
    public let imageName: String

    /// The deep-link destination that the host app opens when the row is selected.
    public let deepLinkDestination: DeepLinkDestination

    // MARK: - Initialiser

    public init(
        title: String,
        subtitle: String,
        imageName: String,
        deepLinkDestination: DeepLinkDestination
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageName = imageName
        self.deepLinkDestination = deepLinkDestination
    }
}

// MARK: - Convenience factory

extension CarPlayDashboardItem {

    /// A blank item useful as a placeholder during async data loading.
    public static func placeholder(deepLinkDestination: DeepLinkDestination) -> CarPlayDashboardItem {
        CarPlayDashboardItem(
            title: "",
            subtitle: "",
            imageName: "ellipsis.circle",
            deepLinkDestination: deepLinkDestination
        )
    }
}

#endif // canImport(CarPlay)
