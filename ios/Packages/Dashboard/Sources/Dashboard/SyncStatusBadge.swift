import SwiftUI
import Observation
import Core
import Networking
import DesignSystem

// MARK: - §3.10 Sync-status badge
//
// Small glass pill on dashboard header showing:
//   "Synced 2 min ago" / "Pending 3" / "Offline"
// Tap → Settings → Data → Sync Issues.

// MARK: - ViewModel

@MainActor
@Observable
public final class SyncStatusViewModel {
    public enum Status: Sendable {
        case synced(Date?)          // last sync time
        case pending(Int)           // count of pending writes
        case offline
    }

    public private(set) var status: Status = .synced(nil)
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init() {}

    /// Called by Dashboard on appear; updates every 30s.
    public func startPolling() {
        timer?.cancel()
        update()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                self?.update()
            }
        }
    }

    public func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    private func update() {
        if !Reachability.shared.isOnline {
            status = .offline
            return
        }
        // Pending count can be provided by SyncQueueStore in the future.
        // For now derive from Reachability and a UserDefaults hint set by
        // the Sync package when it drains the queue.
        let pendingKey = "sync.queue.pendingCount"
        let pending = UserDefaults.standard.integer(forKey: pendingKey)
        if pending > 0 {
            status = .pending(pending)
        } else {
            let lastSync = UserDefaults.standard.object(forKey: "sync.lastSyncedAt") as? Date
            status = .synced(lastSync)
        }
    }
}

// MARK: - View

/// §3.10 — Small glass pill; tap goes to Settings → Data → Sync Issues.
public struct SyncStatusBadge: View {
    @State private var vm = SyncStatusViewModel()
    /// Called when the badge is tapped — App layer should navigate to Settings > Data.
    public var onTapSyncSettings: (() -> Void)?

    public init(onTapSyncSettings: (() -> Void)? = nil) {
        self.onTapSyncSettings = onTapSyncSettings
    }

    public var body: some View {
        Button {
            onTapSyncSettings?()
        } label: {
            pillContent
        }
        .buttonStyle(.plain)
        .task { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
    }

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(pillLabel)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.brandGlass(), in: Capsule())
        .accessibilityLabel(accessibilityLabel)
    }

    private var dotColor: Color {
        switch vm.status {
        case .synced:    return .bizarreTeal
        case .pending:   return .bizarreWarning
        case .offline:   return .bizarreOnSurfaceMuted
        }
    }

    private var pillLabel: String {
        switch vm.status {
        case .synced(let date):
            guard let date else { return "Synced" }
            let mins = Int(-date.timeIntervalSinceNow / 60)
            if mins < 1 { return "Just synced" }
            if mins == 1 { return "Synced 1 min ago" }
            if mins < 60 { return "Synced \(mins) min ago" }
            return "Synced \(mins / 60)h ago"
        case .pending(let n):
            return "Pending \(n)"
        case .offline:
            return "Offline"
        }
    }

    private var accessibilityLabel: String {
        switch vm.status {
        case .synced(let date):
            guard let date else { return "Synced" }
            let mins = Int(-date.timeIntervalSinceNow / 60)
            return "Synced \(mins) minutes ago. Tap to view sync settings."
        case .pending(let n):
            return "\(n) pending sync writes. Tap to view sync settings."
        case .offline:
            return "Offline. Tap to view sync settings."
        }
    }
}
