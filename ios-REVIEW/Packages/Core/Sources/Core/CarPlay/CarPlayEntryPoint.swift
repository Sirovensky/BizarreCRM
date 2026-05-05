#if canImport(CarPlay)
import CarPlay
import Foundation

// MARK: - CarPlayEntryPoint

/// Marks a feature type as eligible to appear in the CarPlay interface.
///
/// Conforming types (e.g. voicemail list items, call-log entries) supply a
/// ``carPlayItem`` representation that the CarPlay template layer can render
/// without depending on the full feature module.
///
/// ## Usage
/// ```swift
/// extension VoicemailEntry: CarPlayEntryPoint {
///     public var carPlayItem: CarPlayDashboardItem {
///         CarPlayDashboardItem(
///             title: callerName,
///             subtitle: formattedDuration,
///             imageName: "phone.fill",
///             deepLinkDestination: .voicemail(tenantSlug: tenantSlug, id: id)
///         )
///     }
/// }
/// ```
public protocol CarPlayEntryPoint: Sendable {
    /// The dashboard item that represents this entry inside CarPlay.
    var carPlayItem: CarPlayDashboardItem { get }
}

#endif // canImport(CarPlay)
