import SwiftUI
import Observation
import Core
import Networking
import DesignSystem

// MARK: - §3.12 Unread-SMS / team-inbox tile
//
// GET /sms/unread-count drives a pill badge; tap → SMS tab.
// GET /inbox count shown as a secondary "Team Inbox" badge when tenant has it enabled.

// MARK: - ViewModel

@MainActor
@Observable
public final class UnreadSMSViewModel {
    public private(set) var unreadCount = 0
    /// Nil = tenant has no team inbox feature (endpoint returned 404/error).
    public private(set) var inboxCount: Int? = nil
    public private(set) var isLoading = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        // Fetch SMS unread count and team inbox count in parallel.
        async let smsTask: Int = {
            do { return try await api.smsUnreadCount() }
            catch { AppLog.ui.error("SMS unread count failed: \(error.localizedDescription, privacy: .public)"); return 0 }
        }()
        async let inboxTask: Int? = api.teamInboxCount()
        let (sms, inbox) = await (smsTask, inboxTask)
        unreadCount = sms
        inboxCount = inbox
    }

    /// Auto-refresh every 60s while the dashboard is foregrounded.
    public func startPolling() {
        pollTask?.cancel()
        Task { await load() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Tile View

/// §3.12 — Unread SMS badge tile + Team Inbox count on Dashboard.
/// Tap → SMS tab (callback provided by App layer).
/// Team Inbox count shown when tenant has inbox feature enabled (server returns count).
public struct UnreadSMSTile: View {
    @State private var vm: UnreadSMSViewModel
    public var onTapSMSTab: (() -> Void)?
    public var onTapTeamInbox: (() -> Void)?

    public init(
        api: APIClient,
        onTapSMSTab: (() -> Void)? = nil,
        onTapTeamInbox: (() -> Void)? = nil
    ) {
        _vm = State(wrappedValue: UnreadSMSViewModel(api: api))
        self.onTapSMSTab = onTapSMSTab
        self.onTapTeamInbox = onTapTeamInbox
    }

    public var body: some View {
        // When team inbox is enabled, show two side-by-side tiles.
        // When disabled (inboxCount == nil), show single SMS tile.
        if let inboxCount = vm.inboxCount {
            HStack(spacing: BrandSpacing.sm) {
                smsTileButton
                teamInboxTileButton(inboxCount: inboxCount)
            }
        } else {
            smsTileButton
        }
    }

    private var smsTileButton: some View {
        Button { onTapSMSTab?() } label: { smsTileLabel }
            .buttonStyle(.plain)
            .task { vm.startPolling() }
            .onDisappear { vm.stopPolling() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(vm.unreadCount) unread SMS messages. Tap to open messages.")
            .accessibilityAddTraits(.isButton)
    }

    private var smsTileLabel: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "message.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(vm.unreadCount)")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    if vm.unreadCount > 0 {
                        Circle()
                            .fill(Color.bizarreError)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }
                Text("Unread SMS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    vm.unreadCount > 0 ? Color.bizarreOrange.opacity(0.4) : Color.bizarreOutline.opacity(0.35),
                    lineWidth: vm.unreadCount > 0 ? 1 : 0.5
                )
        )
    }

    private func teamInboxTileButton(inboxCount: Int) -> some View {
        Button { onTapTeamInbox?() } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(inboxCount)")
                            .font(.brandTitleLarge())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                        if inboxCount > 0 {
                            Circle()
                                .fill(Color.bizarreTeal)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                    Text("Team Inbox")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        inboxCount > 0 ? Color.bizarreTeal.opacity(0.4) : Color.bizarreOutline.opacity(0.35),
                        lineWidth: inboxCount > 0 ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(inboxCount) unread team inbox messages. Tap to open team inbox.")
        .accessibilityAddTraits(.isButton)
    }
}
