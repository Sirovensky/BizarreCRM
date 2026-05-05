import SwiftUI
import DesignSystem
import Networking

// MARK: - ShiftSwapOfferViewModel

@MainActor
@Observable
public final class ShiftSwapOfferViewModel {

    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }
    public enum ActionState: Sendable, Equatable {
        case idle, processing, done, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var actionState: ActionState = .idle
    public private(set) var incomingRequests: [ShiftSwapRequest] = []
    public var selectedOfferShiftId: Int64 = 0
    public var availableShifts: [Shift] = []

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func loadRequests() async {
        loadState = .loading
        do {
            let all = try await api.getSwapRequests()
            incomingRequests = all.filter { $0.status == .pending }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func offer(requestId: Int64) async {
        guard selectedOfferShiftId > 0 else { return }
        actionState = .processing
        do {
            _ = try await api.offerSwap(requestId: requestId, body: SwapOfferBody(targetShiftId: selectedOfferShiftId))
            actionState = .done
            await loadRequests()
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }

    public func decline(requestId: Int64) async {
        actionState = .processing
        do {
            _ = try await api.approveSwap(requestId: requestId, approved: false)
            actionState = .done
            await loadRequests()
        } catch {
            actionState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - ShiftSwapOfferView

/// Shows incoming swap requests to the prospective swap receiver.
public struct ShiftSwapOfferView: View {

    @Bindable var vm: ShiftSwapOfferViewModel

    public init(vm: ShiftSwapOfferViewModel) {
        self.vm = vm
    }

    public var body: some View {
        List {
            ForEach(vm.incomingRequests) { request in
                SwapOfferRow(
                    request: request,
                    availableShifts: vm.availableShifts,
                    selectedShiftId: $vm.selectedOfferShiftId,
                    onOffer: { Task { await vm.offer(requestId: request.id) } },
                    onDecline: { Task { await vm.decline(requestId: request.id) } }
                )
            }
        }
        .navigationTitle("Swap Requests")
        .refreshable { await vm.loadRequests() }
        .task { await vm.loadRequests() }
        .overlay { stateOverlay }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading requests…")
        case let .failed(msg):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(msg))
        default:
            EmptyView()
        }
    }
}

// MARK: - SwapOfferRow

private struct SwapOfferRow: View {
    let request: ShiftSwapRequest
    let availableShifts: [Shift]
    @Binding var selectedShiftId: Int64
    let onOffer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("From employee \(request.requesterId)")
                .font(.subheadline.weight(.medium))
            Text("Shift ID: \(request.requesterShiftId)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note = request.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Offer") { onOffer() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Offer to swap shift \(request.requesterShiftId)")
                Button("Decline", role: .destructive) { onDecline() }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Decline swap request from employee \(request.requesterId)")
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}
