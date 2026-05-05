import Foundation
import Networking

// §20.6 — Offline banner copy variants
//
// Provides distinct human-readable copy for each connectivity situation so
// the banner text is always accurate and actionable rather than a generic
// "You're offline" fallback.
//
// Cases:
//   .noSignal        — device has no network path at all (airplane mode, dead zone)
//   .cellular        — online but on expensive cellular / Personal Hotspot
//   .constrainedWifi — low-data mode (NWPath.isConstrained, e.g. Low Data Mode)
//   .online          — fully connected, no banner needed (degenerate case)
//
// Usage — consume from ConnectivityBannerModifier or any custom banner view:
//
//   let copy = OfflineBannerCopy.resolve(reachability: reachability)
//   Text(copy.headline)
//   Text(copy.subline)

// MARK: - OfflineBannerCopy

/// Human-readable copy for the three distinct offline / limited-connectivity
/// states surfaced by `Reachability`.
public struct OfflineBannerCopy: Sendable, Equatable {

    // MARK: - Nested kind

    public enum Kind: Sendable, Equatable {
        /// No network path — airplane mode or no signal.
        case noSignal
        /// Path exists but is expensive (cellular / Personal Hotspot).
        case cellular
        /// Path exists but is constrained (iOS Low Data Mode).
        case constrainedWifi
        /// Fully connected — no banner needed.
        case online
    }

    public let kind: Kind

    // MARK: - Copy strings

    /// Short one-line headline shown in the banner chip.
    public var headline: String {
        switch kind {
        case .noSignal:
            return "No internet connection"
        case .cellular:
            return "Using cellular data"
        case .constrainedWifi:
            return "Low Data Mode active"
        case .online:
            return ""
        }
    }

    /// Optional secondary line with more context / guidance.
    public var subline: String {
        switch kind {
        case .noSignal:
            return "Changes will sync when you're back online"
        case .cellular:
            return "Large uploads paused to save data"
        case .constrainedWifi:
            return "Sync limited — turn off Low Data Mode for full sync"
        case .online:
            return ""
        }
    }

    /// System icon name to accompany the headline.
    public var iconName: String {
        switch kind {
        case .noSignal:        return "wifi.slash"
        case .cellular:        return "antenna.radiowaves.left.and.right"
        case .constrainedWifi: return "wifi.exclamationmark"
        case .online:          return "wifi"
        }
    }

    /// VoiceOver-friendly string that combines headline + subline.
    public var accessibilityLabel: String {
        switch kind {
        case .online: return ""
        default:
            return subline.isEmpty ? headline : "\(headline). \(subline)"
        }
    }

    // MARK: - Factory

    /// Derives the correct copy variant from the live `Reachability` object.
    ///
    /// Priority: noSignal > constrainedWifi > cellular > online
    @MainActor
    public static func resolve(reachability: Reachability) -> OfflineBannerCopy {
        if !reachability.isOnline {
            return OfflineBannerCopy(kind: .noSignal)
        }
        // isConstrained is not yet exposed on Reachability; check isExpensive first.
        if reachability.isExpensive {
            return OfflineBannerCopy(kind: .cellular)
        }
        return OfflineBannerCopy(kind: .online)
    }
}

// MARK: - Convenience initialiser

public extension OfflineBannerCopy {
    /// Quick construction by kind — useful in tests and previews.
    static func noSignal()        -> OfflineBannerCopy { .init(kind: .noSignal) }
    static func cellular()        -> OfflineBannerCopy { .init(kind: .cellular) }
    static func constrainedWifi() -> OfflineBannerCopy { .init(kind: .constrainedWifi) }
    static func online()          -> OfflineBannerCopy { .init(kind: .online) }
}
