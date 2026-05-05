import SwiftUI
import Observation
import DesignSystem

// MARK: - MissingPartsAlertWidget
//
// §3.2 Missing parts alert — parts with low stock blocking open tickets.
// Tap → Inventory filtered to affected items.
// Source: GET /api/v1/tickets/missing-parts

// MARK: - ViewModel

@MainActor
@Observable
public final class MissingPartsViewModel {
    public let title = "Missing Parts"
    public private(set) var state: BIWidgetState<MissingPartsPayload> = .idle

    private let repo: DashboardBIRepository

    public init(repo: DashboardBIRepository) {
        self.repo = repo
    }

    public func load() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let payload = try await repo.fetchMissingParts()
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reload() async {
        state = .idle
        await load()
    }
}

// MARK: - View

public struct MissingPartsAlertWidget: View, BIWidgetView {
    public let widgetTitle = "Missing Parts"
    @State private var vm: MissingPartsViewModel
    /// Called when the user taps — should navigate to Inventory filtered to missing parts.
    public var onTapInventory: (() -> Void)?

    public init(vm: MissingPartsViewModel, onTapInventory: (() -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onTapInventory = onTapInventory
    }

    public var body: some View {
        BIWidgetChrome(title: widgetTitle, systemImage: "exclamationmark.triangle.fill") {
            switch vm.state {
            case .idle:
                EmptyView()
            case .loading:
                BIWidgetLoadingOverlay()
            case .loaded(let data):
                MissingPartsContent(data: data, onTapInventory: onTapInventory)
            case .failed(let msg):
                BIWidgetErrorState(message: msg) { Task { await vm.reload() } }
            }
        }
        .task { await vm.load() }
    }
}

// MARK: - Content

private struct MissingPartsContent: View {
    let data: MissingPartsPayload
    var onTapInventory: (() -> Void)?

    var body: some View {
        Button {
            onTapInventory?()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header count
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(data.totalBlocked)")
                        .font(.brandDisplaySmall())
                        .foregroundStyle(data.totalBlocked > 0 ? .bizarreError : .bizarreOnSurface)
                        .monospacedDigit()
                    Text("ticket\(data.totalBlocked == 1 ? "" : "s") blocked")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                if data.tickets.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.bizarreTeal)
                        Text("No blocked tickets")
                            .font(.brandBodySmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                } else {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(data.tickets.prefix(3)) { ticket in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ticket.orderId)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOrange)
                                        .monospacedDigit()
                                    if let parts = ticket.missingParts.first {
                                        Text(parts + (ticket.missingParts.count > 1 ? " +\(ticket.missingParts.count - 1)" : ""))
                                            .font(.brandBodySmall())
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                                if let name = ticket.customerName {
                                    Text(name)
                                        .font(.brandBodySmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Label("View Inventory", systemImage: "chevron.right")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                    }
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Missing parts alert: \(data.totalBlocked) tickets blocked. Tap to view affected inventory.")
    }
}
