#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - Reorder Suggestion entry

public struct ReorderSuggestion: Sendable, Identifiable {
    public let id: UUID = UUID()
    public let item: LowStockItem
    public var reorderQty: Int
    public var supplierId: Int64?
    public var unitCostCents: Int

    public init(item: LowStockItem, reorderQty: Int, supplierId: Int64? = nil, unitCostCents: Int = 0) {
        self.item = item
        self.reorderQty = reorderQty
        self.supplierId = supplierId
        self.unitCostCents = unitCostCents
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PurchaseOrderReorderSuggestionViewModel {

    public enum State: Sendable {
        case loading
        case loaded([ReorderSuggestion])
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var suppliers: [Supplier] = []
    public private(set) var isCreating: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdPOId: Int64?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let poRepo: PurchaseOrderRepository
    @ObservationIgnored private let supplierRepo: SupplierRepository

    public init(api: APIClient) {
        self.api = api
        self.poRepo = LivePurchaseOrderRepository(api: api)
        self.supplierRepo = LiveSupplierRepository(api: api)
    }

    public func load() async {
        state = .loading
        errorMessage = nil
        async let lowStockTask = fetchLowStock()
        async let suppliersTask = (try? supplierRepo.list()) ?? []

        let (fetchedItems, fetchedSuppliers) = await (lowStockTask, suppliersTask)
        suppliers = fetchedSuppliers

        switch fetchedItems {
        case .success(let items):
            let suggestions = items.map { item in
                let qty = max(item.reorderThreshold - item.currentQty, 1) + item.reorderThreshold
                return ReorderSuggestion(
                    item: item,
                    reorderQty: qty,
                    supplierId: fetchedSuppliers.first?.id,
                    unitCostCents: 0
                )
            }
            state = .loaded(suggestions)
        case .notImplemented:
            state = .comingSoon
        case .failure(let msg):
            state = .failed(msg)
        }
    }

    private enum FetchResult: Sendable {
        case success([LowStockItem])
        case notImplemented
        case failure(String)
    }

    private func fetchLowStock() async -> FetchResult {
        do {
            let items = try await api.listLowStock()
            return .success(items)
        } catch APITransportError.notImplemented {
            return .notImplemented
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Create a single draft PO from all suggestions.
    public func createPOFromSuggestions(_ suggestions: [ReorderSuggestion]) async {
        guard !isCreating else { return }
        guard let supplierId = suggestions.first?.supplierId ?? suppliers.first?.id else {
            errorMessage = "Select a supplier first."
            return
        }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        let lines = suggestions.map { s in
            POLineItemRequest(
                sku: s.item.sku ?? s.item.name,
                name: s.item.name,
                qtyOrdered: s.reorderQty,
                unitCostCents: s.unitCostCents
            )
        }
        let body = CreatePurchaseOrderRequest(
            supplierId: supplierId,
            expectedDate: nil,
            items: lines,
            notes: "Auto-generated from low-stock suggestions"
        )
        do {
            let po = try await poRepo.create(body)
            createdPOId = po.id
            await load() // refresh
        } catch {
            AppLog.ui.error("Reorder PO creation failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct PurchaseOrderReorderSuggestionView: View {
    @State private var vm: PurchaseOrderReorderSuggestionViewModel
    @State private var showSuccessBanner: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: PurchaseOrderReorderSuggestionViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            mainContent
        }
        .navigationTitle("Reorder Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onChange(of: vm.createdPOId) { _, newId in
            if newId != nil { showSuccessBanner = true }
        }
        .overlay(alignment: .top) {
            if showSuccessBanner, let poId = vm.createdPOId {
                successBanner(poId: poId)
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .comingSoon:
            comingSoonView

        case .failed(let msg):
            errorView(msg)

        case .loaded(let suggestions):
            if suggestions.isEmpty {
                emptyState
            } else {
                suggestionList(suggestions)
            }
        }
    }

    // MARK: Suggestion list

    private func suggestionList(_ suggestions: [ReorderSuggestion]) -> some View {
        VStack(spacing: 0) {
            supplierPicker
            List {
                ForEach(suggestions) { suggestion in
                    suggestionRow(suggestion)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            createPOButton(suggestions)
        }
    }

    private var supplierPicker: some View {
        HStack {
            Text("Supplier:")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            // This is a simplified picker; in a full build, each suggestion would
            // allow per-item supplier assignment.
            if vm.suppliers.isEmpty {
                Text("None").foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                Text(vm.suppliers.first?.name ?? "—")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1)
    }

    private func suggestionRow(_ s: ReorderSuggestion) -> some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(s.item.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let sku = s.item.sku, !sku.isEmpty {
                    Text("SKU \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text("On hand: \(s.item.currentQty) · Reorder at: \(s.item.reorderThreshold)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Suggest \(s.reorderQty)")
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOrange)
                Text("units")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.item.name), suggest reorder of \(s.reorderQty) units")
    }

    private func createPOButton(_ suggestions: [ReorderSuggestion]) -> some View {
        Button {
            Task { await vm.createPOFromSuggestions(suggestions) }
        } label: {
            if vm.isCreating {
                ProgressView()
            } else {
                Label("Create Draft PO from \(suggestions.count) item\(suggestions.count == 1 ? "" : "s")",
                      systemImage: "shippingbox.and.arrow.backward")
                    .font(.brandTitleMedium())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(vm.isCreating || vm.suppliers.isEmpty)
        .padding(BrandSpacing.md)
        .accessibilityLabel("Create draft purchase order from all suggestions")
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
            Text("All stock levels healthy")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No items need reordering right now.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("All stock levels are healthy, no reorder needed")
    }

    private var comingSoonView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Coming soon")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Server endpoint for low-stock data is pending.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load suggestions")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func successBanner(poId: Int64) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.bizarreSuccess)
            Text("Draft PO #\(poId) created")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button { showSuccessBanner = false } label: {
                Image(systemName: "xmark").imageScale(.small)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, BrandSpacing.md)
        .padding(.top, BrandSpacing.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: showSuccessBanner)
    }
}
#endif
