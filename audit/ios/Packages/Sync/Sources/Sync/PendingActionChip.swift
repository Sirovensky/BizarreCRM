import SwiftUI
import DesignSystem

// §20.8 — Pending-action count chip
//
// A small capsule badge that shows how many writes are waiting in the
// sync_queue. Intended for tab bars, navigation titles, or Settings rows
// where the user needs a quick glance at unsynced work.
//
// Usage:
//
//   HStack {
//       Text("Data & Sync")
//       Spacer()
//       PendingActionChip()
//   }
//
// When `pendingCount` is 0 the chip is hidden (zero-size, no layout impact).

// MARK: - PendingActionChip

/// Capsule badge displaying the current unsynced-write count.
///
/// Observes `SyncManager.shared.pendingCount` directly; no extra state
/// needed in the parent view. Hides itself when the count reaches zero.
public struct PendingActionChip: View {

    @State private var pendingCount: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        if pendingCount > 0 {
            chipLabel
                .transition(transition)
                .animation(animation, value: pendingCount)
                .task { await observePendingCount() }
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .task { await observePendingCount() }
        }
    }

    // MARK: - Chip appearance

    private var chipLabel: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: "arrow.up.arrow.down.circle.fill")
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("\(pendingCount)")
                .font(.brandMono(size: 11))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.vertical, 2)
        .background(Color.bizarreWarning, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Motion

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.85))
    }

    private var animation: Animation {
        reduceMotion ? .linear(duration: 0) : BrandMotion.snappy
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        pendingCount == 1
            ? "1 unsynced change pending"
            : "\(pendingCount) unsynced changes pending"
    }

    // MARK: - Observation

    /// Polls `SyncManager.pendingCount` via an AsyncStream so this view
    /// stays in sync without a timer. The stream ends when the task is
    /// cancelled (e.g., view disappears).
    @MainActor
    private func observePendingCount() async {
        pendingCount = SyncManager.shared.pendingCount
        // Re-read whenever isSyncing flips (proxy for queue state change).
        for await _ in NotificationCenter.default
            .notifications(named: SyncManager.pendingCountDidChange)
            .map({ _ in () }) {
            pendingCount = SyncManager.shared.pendingCount
        }
    }
}

// MARK: - SyncManager notification name

public extension SyncManager {
    /// Posted on the main thread whenever `pendingCount` changes.
    static let pendingCountDidChange = Notification.Name(
        "com.bizarrecrm.sync.pendingCountDidChange"
    )

    /// Call this from `refreshPendingCount()` to broadcast the change.
    func postPendingCountChanged() {
        NotificationCenter.default.post(name: Self.pendingCountDidChange, object: nil)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Pending chip — 3 items") {
    HStack {
        Text("Data & Sync")
            .font(.brandBodyMedium())
        Spacer()
        PendingActionChip()
    }
    .padding()
}
#endif
