import SwiftUI
import DesignSystem
import Networking

// §20.6 — Stale-cache banner
//
// Shown when:
//   - the device is offline,
//   - AND the screen's last successful sync was more than `threshold` ago.
//
// Distinct from the §20.6 connectivity banner (which only says "you're offline"):
// this banner warns the user that the data they're looking at is materially
// out of date — typical case is a tech in a basement on a long ticket,
// looking at customer notes that haven't refreshed in hours.
//
// Usage:
//
//   InventoryListView()
//       .staleCacheBanner(lastSyncedAt: vm.lastSyncedAt)
//
// Threshold defaults to 1h per the ActionPlan; override with
// `.staleCacheBanner(lastSyncedAt:threshold:)` when needed.

// MARK: - StaleCacheBannerModifier

public struct StaleCacheBannerModifier: ViewModifier {

    @Environment(Reachability.self) private var reachability

    /// When the data on this screen was last refreshed from the server.
    /// `nil` is treated as "never synced" → banner shown if offline.
    public let lastSyncedAt: Date?

    /// How long offline + stale before we surface the warning (default 1h).
    public let threshold: TimeInterval

    /// Re-evaluate every minute so the banner appears without a state poke
    /// once the threshold is crossed during the user's session.
    @State private var now: Date = .now

    public init(lastSyncedAt: Date?, threshold: TimeInterval = 3600) {
        self.lastSyncedAt = lastSyncedAt
        self.threshold = threshold
    }

    private var shouldShow: Bool {
        guard !reachability.isOnline else { return false }
        guard let last = lastSyncedAt else { return true }   // never synced + offline
        return now.timeIntervalSince(last) > threshold
    }

    private var ageDescription: String {
        guard let last = lastSyncedAt else { return "Never synced" }
        let interval = now.timeIntervalSince(last)
        if interval < 7200 {
            let mins = Int(interval / 60)
            return "Last synced \(mins) min ago"
        }
        let hours = Int(interval / 3600)
        return "Last synced \(hours)h ago"
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShow {
                    StaleCacheBanner(ageDescription: ageDescription)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(BrandMotion.banner, value: shouldShow)
                }
            }
            .task(id: lastSyncedAt) {
                // Refresh `now` once per minute so the threshold trips live.
                while !Task.isCancelled {
                    now = .now
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
    }
}

// MARK: - StaleCacheBanner

struct StaleCacheBanner: View {
    let ageDescription: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing offline data")
                    .font(.brandLabelLarge())
                    .lineLimit(1)
                Text(ageDescription)
                    .font(.brandLabelSmall())
                    .lineLimit(1)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Color.bizarreOnSurface)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreWarning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Showing offline data. \(ageDescription).")
    }
}

// MARK: - View extension

public extension View {
    /// Attach the §20.6 stale-cache banner. Visible only when offline and the
    /// last successful sync exceeds `threshold` (default 1h).
    func staleCacheBanner(lastSyncedAt: Date?, threshold: TimeInterval = 3600) -> some View {
        modifier(StaleCacheBannerModifier(lastSyncedAt: lastSyncedAt, threshold: threshold))
    }
}
