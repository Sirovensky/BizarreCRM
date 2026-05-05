import SwiftUI
import DesignSystem

// §20.8 — Retry-now / Sync-now button
//
// A tappable button that immediately drains the sync queue by calling
// `SyncManager.shared.syncNow()`. Shows a spinner while syncing and
// displays a brief success indicator on completion.
//
// Intended for:
//   - Settings → Data & Sync row
//   - Error banners with a "Retry" CTA
//   - Pull-down debug overlay
//
// Usage:
//
//   RetryNowButton()
//
//   // Compact label-only style for inline use:
//   RetryNowButton(style: .compact)

// MARK: - RetryNowButtonStyle

public enum RetryNowButtonStyle: Sendable {
    /// Full-width row with title + subtitle + icon (for Settings).
    case full
    /// Single-line compact CTA (for inline banners).
    case compact
}

// MARK: - RetryNowButton

/// §20.8 — "Sync now" button that triggers an immediate queue drain.
///
/// Observes `SyncManager.shared.isSyncing` and `pendingCount`; disables
/// itself while a drain is already in progress.
public struct RetryNowButton: View {

    public let style: RetryNowButtonStyle

    @State private var isSyncing: Bool = false
    @State private var pendingCount: Int = 0
    @State private var showSuccess: Bool = false

    public init(style: RetryNowButtonStyle = .full) {
        self.style = style
    }

    public var body: some View {
        Button(action: triggerSync) {
            buttonContent
        }
        .disabled(isSyncing)
        .task { await observeManager() }
    }

    // MARK: - Layout

    @ViewBuilder
    private var buttonContent: some View {
        switch style {
        case .full:
            fullRow
        case .compact:
            compactRow
        }
    }

    private var fullRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync Now")
                    .font(.brandBodyMedium())
                    .foregroundStyle(isSyncing ? .bizarreOnSurfaceMuted : .bizarreOnSurface)
                Text(subtitleText)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            trailingIcon
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to sync pending changes now")
        .accessibilityAddTraits(isSyncing ? .updatesFrequently : [])
    }

    private var compactRow: some View {
        Label {
            Text(isSyncing ? "Syncing…" : "Retry now")
                .font(.brandLabelSmall().weight(.medium))
        } icon: {
            trailingIcon
        }
        .foregroundStyle(isSyncing ? .bizarreOnSurfaceMuted : .bizarreTeal)
        .accessibilityLabel(isSyncing ? "Syncing" : "Retry sync now")
    }

    @ViewBuilder
    private var trailingIcon: some View {
        if showSuccess {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.bizarreSuccess)
                .imageScale(.medium)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        } else if isSyncing {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(pendingCount > 0 ? Color.bizarreWarning : Color.bizarreTeal)
                .imageScale(.medium)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Copy

    private var subtitleText: String {
        if isSyncing { return "Syncing…" }
        if pendingCount == 0 { return "All changes synced" }
        return pendingCount == 1
            ? "1 change waiting to sync"
            : "\(pendingCount) changes waiting to sync"
    }

    private var accessibilityLabel: String {
        if isSyncing { return "Syncing in progress" }
        if showSuccess { return "Sync complete" }
        return subtitleText + ". Sync now button."
    }

    // MARK: - Actions

    private func triggerSync() {
        Task { @MainActor in
            await SyncManager.shared.syncNow()
            withAnimation(BrandMotion.snappy) { showSuccess = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(BrandMotion.snappy) { showSuccess = false }
        }
    }

    // MARK: - Observation

    @MainActor
    private func observeManager() async {
        // Reflect SyncManager state on every pendingCountDidChange notification.
        isSyncing = SyncManager.shared.isSyncing
        pendingCount = SyncManager.shared.pendingCount
        for await _ in NotificationCenter.default
            .notifications(named: SyncManager.pendingCountDidChange)
            .map({ _ in () }) {
            isSyncing = SyncManager.shared.isSyncing
            pendingCount = SyncManager.shared.pendingCount
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Retry button — full style") {
    List {
        RetryNowButton(style: .full)
        RetryNowButton(style: .compact)
    }
    .listStyle(.insetGrouped)
}
#endif
