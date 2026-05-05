import SwiftUI
import Observation
import DesignSystem
import Networking

// MARK: - NotificationBadgeCounterViewModel

/// Polls `GET /api/v1/notifications/unread-count` and publishes the live
/// unread count so any badge-bearing chrome (tab bars, nav icons) stays
/// in sync without coupling to the full notification list.
///
/// Polling is self-throttled: a background `Task` with `Task.sleep` avoids
/// a `Timer`-based approach that would require explicit cancellation plumbing.
/// The task is cancelled automatically when the `deinit` fires via `taskHandle`.
@MainActor
@Observable
public final class NotificationBadgeCounterViewModel {

    // MARK: - Public state

    /// Current unread count. 0 means "all caught up" — badge hidden.
    public private(set) var unreadCount: Int = 0

    /// Whether an in-flight poll is running (for shimmer / skeleton badge).
    public private(set) var isLoading: Bool = false

    /// Formatted label for accessibility ("3 unread notifications").
    public var accessibilityLabel: String {
        switch unreadCount {
        case 0:  return "No unread notifications"
        case 1:  return "1 unread notification"
        default: return "\(unreadCount) unread notifications"
        }
    }

    /// Badge label — capped at "99+" to match iOS Mail convention.
    public var badgeLabel: String? {
        guard unreadCount > 0 else { return nil }
        return unreadCount > 99 ? "99+" : "\(unreadCount)"
    }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let pollIntervalSeconds: Double
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    // MARK: - Init

    /// - Parameters:
    ///   - api: `APIClient` from the DI container.
    ///   - pollIntervalSeconds: How often to hit the unread-count endpoint.
    ///     Default 30 s balances freshness with battery / network.
    public init(api: APIClient, pollIntervalSeconds: Double = 30) {
        self.api = api
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Begin polling. Call from `.task { await vm.start() }` so the task
    /// is bound to the view's lifetime and cancelled on disappear.
    public func start() async {
        await fetchOnce()
        startPolling()
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Manual refresh (e.g. after mark-all-read)

    /// Force an immediate count refresh. Call after `markAllRead` so the
    /// badge drops to 0 without waiting for the next poll cycle.
    public func refresh() async {
        await fetchOnce()
    }

    // MARK: - Private

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self, pollIntervalSeconds] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.fetchOnce()
            }
        }
    }

    private func fetchOnce() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let count = try await api.fetchUnreadNotificationCount()
            unreadCount = max(0, count)
        } catch {
            // Silent failure — stale badge is better than a crash or error toast
            // for a background counter. The list view's own error state handles
            // deeper failures.
        }
    }
}

// MARK: - NotificationBadgeView

/// A compact Liquid-Glass badge overlay — place over any navigation icon
/// or tab-bar item that should display the live unread count.
///
/// Usage:
/// ```swift
/// Image(systemName: "bell")
///     .overlay(alignment: .topTrailing) {
///         NotificationBadgeView(vm: badgeVM)
///     }
/// ```
public struct NotificationBadgeView: View {

    @State private var vm: NotificationBadgeCounterViewModel

    public init(vm: NotificationBadgeCounterViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        Group {
            if let label = vm.badgeLabel {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.xs)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreMagenta, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(vm.accessibilityLabel)
                    .accessibilityIdentifier("notif.badge")
            }
        }
        .animation(.spring(response: DesignTokens.Motion.snappy, dampingFraction: 0.7), value: vm.badgeLabel)
        .task { await vm.start() }
    }
}

// MARK: - TabBarBadge convenience modifier

public extension View {
    /// Attaches a `NotificationBadgeView` overlay to any view (tab icon, bell icon).
    func notificationBadge(_ vm: NotificationBadgeCounterViewModel) -> some View {
        overlay(alignment: .topTrailing) {
            NotificationBadgeView(vm: vm)
                .offset(x: 6, y: -6)
        }
    }
}
