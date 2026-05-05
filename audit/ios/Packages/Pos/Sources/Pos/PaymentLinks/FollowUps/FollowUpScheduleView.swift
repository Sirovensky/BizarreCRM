#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §41.3 Follow-up schedule per payment link

/// Shows all planned + sent follow-ups for a single payment link.
/// Admin can add new rules via `FollowUpPolicyEditorSheet`.
public struct FollowUpScheduleView: View {
    @State private var vm: FollowUpScheduleViewModel
    @State private var showEditor: Bool = false

    public init(link: PaymentLink, api: APIClient) {
        _vm = State(wrappedValue: FollowUpScheduleViewModel(link: link, api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Follow-ups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add follow-up rule")
                .brandGlass(.regular, in: Circle(), interactive: true)
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showEditor, onDismiss: {
            Task { await vm.load() }
        }) {
            FollowUpPolicyEditorSheet(linkId: vm.link.id, api: vm.api)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.followUps.isEmpty {
            ProgressView()
        } else if vm.followUps.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(vm.followUps) { followUp in
                FollowUpRow(followUp: followUp, linkCreatedAt: vm.link.createdAt)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(vm.accessibilityLabel(for: followUp))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "bell.badge.slash")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No follow-ups scheduled")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap + to set up automated reminders.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

struct FollowUpRow: View {
    let followUp: PaymentLinkFollowUp
    let linkCreatedAt: String?

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            channelIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(timing)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                statusLabel
            }
            Spacer()
            statusChip
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private var channelIcon: some View {
        Image(systemName: followUp.channel == .sms ? "message" : "envelope")
            .font(.system(size: 20))
            .foregroundStyle(.bizarreOrange)
            .frame(width: 32, height: 32)
    }

    private var timing: String {
        let h = followUp.triggerAfterHours
        if h >= 168, h % 168 == 0 { return "\(h / 168)w after creation" }
        if h >= 24,  h % 24 == 0  { return "\(h / 24)d after creation" }
        return "\(h)h after creation"
    }

    private var statusLabel: some View {
        Group {
            if let sent = followUp.sentAt {
                Text("Sent \(sent)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Text("Scheduled")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var statusChip: some View {
        let (label, color): (String, Color) = {
            switch followUp.status {
            case .scheduled:  return ("PENDING", .bizarreWarning)
            case .sent:       return ("SENT", .blue)
            case .delivered:  return ("DELIVERED", .green)
            case .failed:     return ("FAILED", .red)
            case .cancelled:  return ("CANCELLED", .secondary)
            case .unknown:    return ("—", .secondary)
            }
        }()
        return Text(label)
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class FollowUpScheduleViewModel {
    public private(set) var followUps: [PaymentLinkFollowUp] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    public let link: PaymentLink
    public let api: APIClient

    public init(link: PaymentLink, api: APIClient) {
        self.link = link
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            followUps = try await api.listFollowUps(linkId: link.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load follow-ups."
        }
    }

    /// Timing label for a follow-up relative to `link.createdAt`.
    /// Returns an absolute date string when available, relative offset otherwise.
    public func scheduledDate(for followUp: PaymentLinkFollowUp) -> Date? {
        guard let createdAt = link.createdAt else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let base = fmt.date(from: createdAt)
            ?? { fmt.formatOptions = [.withInternetDateTime]; return fmt.date(from: createdAt) }()
        guard let base else { return nil }
        return base.addingTimeInterval(Double(followUp.triggerAfterHours) * 3600)
    }

    public func accessibilityLabel(for followUp: PaymentLinkFollowUp) -> String {
        let channel = followUp.channel.rawValue
        let h = followUp.triggerAfterHours
        return "\(channel) reminder after \(h) hours, status: \(followUp.status.rawValue)"
    }
}
#endif
