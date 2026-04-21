#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §6.3 — List of open purchase orders / incoming inventory receipts.
/// iPhone: `NavigationStack`. iPad: passes selection up.
public struct ReceivingListView: View {
    @State private var vm: ReceivingListViewModel
    @State private var selectedId: Int64?
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: ReceivingListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Receiving")
                .navigationBarTitleDisplayMode(.large)
                .task { await vm.load() }
                .refreshable { await vm.load() }
                .toolbar { toolbarContent }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            content
                .navigationTitle("Receiving")
                .task { await vm.load() }
                .refreshable { await vm.load() }
                .toolbar { toolbarContent }
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            if let id = selectedId {
                NavigationStack {
                    ReceivingDetailView(api: api, orderId: id)
                }
            } else {
                receivingDetailPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            receivingErrorState(message: err)
        } else if vm.orders.isEmpty {
            receivingEmptyState
        } else {
            List(vm.orders) { order in
                receivingRow(order)
                    .listRowBackground(Color.bizarreSurface1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func receivingRow(_ order: ReceivingOrder) -> some View {
        if Platform.isCompact {
            NavigationLink {
                ReceivingDetailView(api: api, orderId: order.id)
            } label: {
                ReceivingOrderRow(order: order)
            }
            .hoverEffect(.highlight)
        } else {
            Button { selectedId = order.id } label: {
                ReceivingOrderRow(order: order)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await vm.load() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("R", modifiers: .command)
            .accessibilityLabel("Refresh receiving orders")
        }
    }

    private var receivingEmptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No open orders").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text("Open purchase orders will appear here when ready to receive.")
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func receivingErrorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
            Text("Couldn't load orders").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var receivingDetailPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.system(size: 56)).foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select an order")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
        }
    }
}

// MARK: - Row

private struct ReceivingOrderRow: View {
    let order: ReceivingOrder

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(order.supplierName ?? "PO #\(order.id)")
                    .font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurface)
                Text("\(order.lineItems.count) line\(order.lineItems.count == 1 ? "" : "s")")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
            statusChip
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(order.supplierName ?? "PO \(order.id)"), \(order.lineItems.count) lines, \(order.status)"
        )
    }

    private var statusChip: some View {
        Text(order.status.capitalized)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(statusColor)
            .background(statusColor.opacity(0.15), in: Capsule())
    }

    private var statusColor: Color {
        switch order.status {
        case "complete": return .bizarreSuccess
        case "partial":  return .bizarreOrange
        default:         return .bizarreOnSurfaceMuted
        }
    }
}
#endif
