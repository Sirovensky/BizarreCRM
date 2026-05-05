#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class PurchaseOrderListViewModel {

    /// §58 — PO list status filter matching spec:
    /// "status filter (draft / sent / partial / received / cancelled)"
    /// "sent" maps to "ordered" in the server POStatus enum.
    public enum Filter: String, CaseIterable, Sendable {
        case all       = "All"
        case draft     = "Draft"
        case sent      = "Sent"
        case partial   = "Partial"
        case received  = "Received"
        case cancelled = "Cancelled"

        var apiValue: String? {
            switch self {
            case .all:       return nil
            case .draft:     return "draft"
            case .sent:      return "ordered"  // server uses "ordered" for "sent"
            case .partial:   return "partial"
            case .received:  return "received"
            case .cancelled: return "cancelled"
            }
        }
    }

    public private(set) var orders: [PurchaseOrder] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var filter: Filter = .all

    @ObservationIgnored private let repo: PurchaseOrderRepository

    public init(repo: PurchaseOrderRepository) { self.repo = repo }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            orders = try await repo.list(status: filter.apiValue)
        } catch {
            AppLog.ui.error("PO list load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct PurchaseOrderListView: View {
    @State private var vm: PurchaseOrderListViewModel
    @State private var selectedOrder: PurchaseOrder?
    @State private var showCompose: Bool = false
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: PurchaseOrderListViewModel(
            repo: LivePurchaseOrderRepository(api: api)))
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
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Purchase Orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onChange(of: vm.filter) { _, _ in Task { await vm.load() } }
            .sheet(isPresented: $showCompose) {
                PurchaseOrderComposeView(api: api) { Task { await vm.load() } }
            }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                contentBody
            }
            .navigationTitle("Purchase Orders")
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .onChange(of: vm.filter) { _, _ in Task { await vm.load() } }
            .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 520)
            .sheet(isPresented: $showCompose) {
                PurchaseOrderComposeView(api: api) { Task { await vm.load() } }
            }
        } detail: {
            if let order = selectedOrder {
                PurchaseOrderDetailView(order: order, api: api) {
                    Task { await vm.load() }
                }
            } else {
                emptyDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showCompose = true
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("New Purchase Order")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        // §58 spec: "status filter (draft / sent / partial / received / cancelled)"
        // Use .menu picker so the 6-option list stays compact in the navbar.
        ToolbarItem(placement: .navigationBarLeading) {
            Picker("Status", selection: $vm.filter) {
                ForEach(PurchaseOrderListViewModel.Filter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Filter purchase orders by status: \(vm.filter.rawValue)")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentBody: some View {
        switch (vm.isLoading, vm.errorMessage, vm.orders.isEmpty) {
        case (true, _, _):
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case (_, let msg?, _):
            errorState(msg)
        case (_, _, true):
            emptyState
        default:
            orderList
        }
    }

    private var orderList: some View {
        List {
            ForEach(vm.orders) { order in
                POListRow(order: order)
                    .listRowBackground(Color.bizarreSurface1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if Platform.isCompact {
                            selectedOrder = order
                        } else {
                            selectedOrder = order
                        }
                    }
                    .hoverEffect(.highlight)
                    .contextMenu {
                        Label("PO #\(order.id)", systemImage: "doc.text")
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            // iPhone: NavigationLink for detail push
            Group {
                if Platform.isCompact, let order = selectedOrder {
                    NavigationLink(
                        destination: PurchaseOrderDetailView(order: order, api: api) {
                            Task { await vm.load() }
                        },
                        isActive: Binding(
                            get: { selectedOrder != nil },
                            set: { if !$0 { selectedOrder = nil } }
                        )
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
    }

    private var emptyDetail: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Select a purchase order")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .navigationTitle("Purchase Order")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No purchase orders")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap + to create your first purchase order.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("New PO") { showCompose = true }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No purchase orders. Tap plus to create one.")
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load purchase orders")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - POListRow

private struct POListRow: View {
    let order: PurchaseOrder

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("PO #\(order.id)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Text(Self.dateFormatter.string(from: order.createdAt))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let expected = order.expectedDate {
                    Text("Expected \(Self.dateFormatter.string(from: expected))")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                statusBadge(order.status)
                Text(order.totalCents.formattedCents)
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PO \(order.id), \(order.status.displayName), \(order.totalCents.formattedCents)")
    }

    private func statusBadge(_ status: POStatus) -> some View {
        let color: Color = {
            switch status {
            case .draft:        return .bizarreOnSurfaceMuted
            case .pending:      return .bizarreWarning
            case .ordered:      return .bizarreOrange
            case .backordered:  return .bizarreWarning
            case .partial:      return .bizarreWarning
            case .received:     return .bizarreSuccess
            case .cancelled:    return .bizarreError
            }
        }()
        return Text(status.displayName)
            .font(.brandLabelLarge())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}

// MARK: - Cents formatter helper

extension Int {
    var formattedCents: String {
        let dollars = Double(self) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
#endif
