import Foundation
import UIKit
import Networking
import Core

// MARK: - UnreadBadgeService
//
// §12.1 Unread badge — drives `UIApplication.applicationIconBadgeNumber`
// from the lightweight `GET /api/v1/sms/unread-count` endpoint.
// Polling interval: 30 seconds while the app is foregrounded.
// Clears to 0 on explicit user action (markAllRead).
//
// Note: the unread count here covers SMS only. The §13.4 badge aggregation
// (inbox + notifications + SMS) is owned by the Notifications agent;
// this service owns only the SMS contribution.

@MainActor
public final class UnreadBadgeService {
    public static let shared = UnreadBadgeService()

    private var pollTask: Task<Void, Never>?
    private var api: APIClient?

    private init() {}

    // MARK: - Lifecycle

    public func start(api: APIClient) {
        self.api = api
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
            }
        }
    }

    public func stop() {
        stopPolling()
        setBadge(0)
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Refresh

    public func refresh() async {
        guard let api else { return }
        do {
            let result: SmsUnreadCountResponse = try await api.smsUnreadCount()
            setBadge(result.count)
        } catch {
            AppLog.ui.error("UnreadBadgeService refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func setBadge(_ count: Int) {
        // UIApplication.applicationIconBadgeNumber is deprecated in iOS 17 for
        // apps that request notification permission. We update it unconditionally
        // as a fallback; apps with full notification auth use UNUserNotificationCenter.
        // The App already requests notification permission at login.
        UIApplication.shared.applicationIconBadgeNumber = count
    }
}

// Note: smsUnreadCount() extension and SmsUnreadCountResponse live in
// Networking/APIClient+Communications.swift per §20 containment rules.
