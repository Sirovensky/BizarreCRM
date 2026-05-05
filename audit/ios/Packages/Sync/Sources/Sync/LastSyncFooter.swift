import SwiftUI
import DesignSystem

// §20.8 — Last-sync timestamp footer
//
// A compact footer row showing the last successful sync time relative to now
// (e.g. "Last synced 3 min ago") with a secondary line noting any pending
// unsynced changes. Intended for:
//
//   - Settings → Data & Sync bottom of section
//   - Dashboard footer (compact variant)
//   - Any screen that surfaces sync health at a glance
//
// Usage:
//
//   LastSyncFooter()           // auto-observes SyncManager
//   LastSyncFooter(style: .compact)

// MARK: - LastSyncFooterStyle

public enum LastSyncFooterStyle: Sendable {
    /// Two-line row with relative time + pending-count note.
    case full
    /// Single-line "Synced N min ago" label (for list footers).
    case compact
}

// MARK: - LastSyncFooter

/// §20.8 — Footer showing last-sync delta and unsynced write count.
///
/// Reads `SyncManager.shared.lastSyncedAt` and `pendingCount` directly.
/// Refreshes every minute via a `TimelineView` so the relative label stays
/// accurate without a manual timer.
public struct LastSyncFooter: View {

    public let style: LastSyncFooterStyle

    @State private var lastSyncedAt: Date? = nil
    @State private var pendingCount: Int = 0

    public init(style: LastSyncFooterStyle = .full) {
        self.style = style
    }

    public var body: some View {
        // TimelineView with 1-minute cadence keeps relative labels fresh.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let logic = StalenessLogic(lastSyncedAt: lastSyncedAt, now: context.date)
            footerContent(logic: logic)
        }
        .task { await observeManager() }
    }

    // MARK: - Layout

    @ViewBuilder
    private func footerContent(logic: StalenessLogic) -> some View {
        switch style {
        case .full:
            fullFooter(logic: logic)
        case .compact:
            compactFooter(logic: logic)
        }
    }

    private func fullFooter(logic: StalenessLogic) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: syncIconName(logic: logic))
                    .imageScale(.small)
                    .foregroundStyle(logic.stalenessLevel.color)
                    .accessibilityHidden(true)
                Text(syncLabel(logic: logic))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if pendingCount > 0 {
                Text(pendingLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(logic: logic))
    }

    private func compactFooter(logic: StalenessLogic) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: syncIconName(logic: logic))
                .imageScale(.small)
                .foregroundStyle(logic.stalenessLevel.color)
                .accessibilityHidden(true)
            Text(syncLabel(logic: logic))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if pendingCount > 0 {
                Text("·")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(pendingLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreWarning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(logic: logic))
    }

    // MARK: - Copy helpers

    private func syncLabel(logic: StalenessLogic) -> String {
        guard lastSyncedAt != nil else { return "Never synced" }
        return "Last synced \(logic.label)"
    }

    private var pendingLabel: String {
        pendingCount == 1
            ? "1 change not yet synced"
            : "\(pendingCount) changes not yet synced"
    }

    private func syncIconName(logic: StalenessLogic) -> String {
        switch logic.stalenessLevel {
        case .fresh:   return "checkmark.circle"
        case .warning: return "clock"
        case .stale:   return "exclamationmark.triangle"
        case .never:   return "exclamationmark.triangle"
        }
    }

    private func accessibilityLabel(logic: StalenessLogic) -> String {
        let syncPart = logic.a11yLabel
        if pendingCount > 0 {
            return "\(syncPart). \(pendingLabel)."
        }
        return "\(syncPart)."
    }

    // MARK: - Observation

    @MainActor
    private func observeManager() async {
        lastSyncedAt = SyncManager.shared.lastSyncedAt
        pendingCount = SyncManager.shared.pendingCount
        for await _ in NotificationCenter.default
            .notifications(named: SyncManager.pendingCountDidChange)
            .map({ _ in () }) {
            lastSyncedAt = SyncManager.shared.lastSyncedAt
            pendingCount = SyncManager.shared.pendingCount
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Last sync footer — full style") {
    List {
        Section {
            Text("Some settings row")
        } footer: {
            LastSyncFooter(style: .full)
        }
        Section {
            Text("Another row")
        } footer: {
            LastSyncFooter(style: .compact)
        }
    }
    .listStyle(.insetGrouped)
}
#endif
