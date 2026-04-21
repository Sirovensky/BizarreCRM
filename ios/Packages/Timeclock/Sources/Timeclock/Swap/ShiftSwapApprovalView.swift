import SwiftUI
import DesignSystem
import Networking

// MARK: - ShiftSwapApprovalViewModel

@MainActor
@Observable
public final class ShiftSwapApprovalViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }
    public enum ActionState: Sendable, Equatable {
        case idle, processing, done, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var actionState: ActionState = .idle
    public private(set) var pendingRequests: [ShiftSwapRequest] = []

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func loadPendingApprovals() async {
        loadState = .loading
        do {
            let all = try await api.getSwapRequests()
            pendingRequests = all.filter { $0.status == .offered }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func approve(requestId: Int64) async {
        actionState = .processing
        do {
            _ = try await api.approveSwap(requestId: requestId, approved: true)
            actionState = .done
            await loadPendingApprovals()
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func deny(requestId: Int64) async {
        actionState = .processing
        do {
            _ = try await api.approveSwap(requestId: requestId, approved: false)
            actionState = .done
            await loadPendingApprovals()
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - ShiftSwapApprovalView

/// Manager view: approve or deny offered shift swaps. Actions are audit-logged server-side.
public struct ShiftSwapApprovalView: View {

    @Bindable var vm: ShiftSwapApprovalViewModel

    public init(vm: ShiftSwapApprovalViewModel) {
        self.vm = vm
    }

    public var body: some View {
        List {
            ForEach(vm.pendingRequests) { request in
                SwapApprovalRow(
                    request: request,
                    onApprove: { Task { await vm.approve(requestId: request.id) } },
                    onDeny: { Task { await vm.deny(requestId: request.id) } }
                )
            }
        }
        .navigationTitle("Approve Swaps")
        .refreshable { await vm.loadPendingApprovals() }
        .task { await vm.loadPendingApprovals() }
        .overlay { stateOverlay }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading approvals…")
        case let .failed(msg):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(msg))
        default:
            EmptyView()
        }
    }
}

// MARK: - SwapApprovalRow

private struct SwapApprovalRow: View {
    let request: ShiftSwapRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Swap Request #\(request.id)")
                .font(.subheadline.weight(.medium))
            Text("Requester: \(request.requesterId) ↔ Target: \(request.targetEmployeeId ?? 0)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Approve swap request \(request.id)")
                Button("Deny", role: .destructive) { onDeny() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Deny swap request \(request.id)")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .brandHover()
        .contextMenu {
            Button("Approve") { onApprove() }
            Button("Deny", role: .destructive) { onDeny() }
        }
    }
}
