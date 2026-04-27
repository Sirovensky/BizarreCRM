import SwiftUI
import Observation
import Core
import Networking
import DesignSystem

// MARK: - §3.12 Unread-SMS / team-inbox tile
//
// GET /sms/unread-count drives a pill badge; tap → SMS tab.
// Also shows GET /inbox count when tenant has team inbox enabled.

// MARK: - ViewModel

@MainActor
@Observable
public final class UnreadSMSViewModel {
    public private(set) var unreadCount = 0
    public private(set) var inboxCount = 0
    public private(set) var isLoading = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            unreadCount = try await api.smsUnreadCount()
        } catch {
            AppLog.ui.error("SMS unread count failed: \(error.localizedDescription, privacy: .public)")
        }
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

/// §3.12 — Small SMS unread badge tile on Dashboard.
/// Tap → SMS tab (callback provided by App layer).
public struct UnreadSMSTile: View {
    @State private var vm: UnreadSMSViewModel
    public var onTapSMSTab: (() -> Void)?

    public init(api: APIClient, onTapSMSTab: (() -> Void)? = nil) {
        _vm = State(wrappedValue: UnreadSMSViewModel(api: api))
        self.onTapSMSTab = onTapSMSTab
    }

    public var body: some View {
        Button {
            onTapSMSTab?()
        } label: {
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
        .buttonStyle(.plain)
        .task { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(vm.unreadCount) unread SMS messages. Tap to open messages.")
        .accessibilityAddTraits(.isButton)
    }
}
