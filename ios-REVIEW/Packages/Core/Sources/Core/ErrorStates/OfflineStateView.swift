import SwiftUI

// §63 — Offline-specific empty state with cached-data indicator.
//
// Wraps `EmptyStateView` but adds an optional "Cached data from <date>"
// banner when stale data is available. The banner uses a plain
// `.ultraThinMaterial` background — it lives on content, so no Liquid Glass.

/// Specialised empty/offline state that optionally surfaces a cached-data
/// indicator when stale data is available.
///
/// ```swift
/// OfflineStateView(
///     cachedAt: viewModel.lastSyncDate,
///     onRetry: { await viewModel.refresh() }
/// )
/// ```
public struct OfflineStateView: View {

    // MARK: — Properties

    /// When non-nil, a "Cached data from …" banner is shown.
    public let cachedAt: Date?

    /// Called when the user taps "Try Again".
    public let onRetry: (() -> Void)?

    // MARK: — Init

    public init(cachedAt: Date? = nil, onRetry: (() -> Void)? = nil) {
        self.cachedAt = cachedAt
        self.onRetry = onRetry
    }

    // MARK: — Body

    public var body: some View {
        VStack(spacing: 20) {
            EmptyStateView(
                symbol: "wifi.slash",
                title: "You're Offline",
                subtitle: "Check your Wi-Fi or cellular connection.",
                ctaLabel: onRetry != nil ? "Try Again" : nil,
                onCTA: onRetry
            )

            if let cachedAt {
                CachedDataBanner(date: cachedAt)
            }
        }
    }
}

// MARK: — Cached data banner

/// Inline banner shown when stale cached data is available.
struct CachedDataBanner: View {
    let date: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .accessibilityHidden(true)

            Text("Cached data from \(date, format: relativeDateStyle)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.background.secondary)
        )
        .accessibilityLabel("Showing cached data from \(date, format: relativeDateStyle)")
    }

    private var relativeDateStyle: Date.FormatStyle {
        .dateTime.day().month().hour().minute()
    }
}

#if DEBUG
#Preview("Offline — no cache") {
    OfflineStateView()
}

#Preview("Offline — with cached data") {
    OfflineStateView(
        cachedAt: Date(timeIntervalSinceNow: -3600),
        onRetry: { }
    )
}

#Preview("Offline — old cache") {
    OfflineStateView(
        cachedAt: Calendar.current.date(byAdding: .day, value: -2, to: Date()),
        onRetry: { }
    )
}
#endif
