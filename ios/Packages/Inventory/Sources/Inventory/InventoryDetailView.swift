#if canImport(UIKit)
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Core
import DesignSystem
import Networking

public struct InventoryDetailView: View {
    @State private var vm: InventoryDetailViewModel
    @State private var showingEdit: Bool = false
    @State private var showingAdjust: Bool = false
    @State private var showingDeactivateConfirm: Bool = false
    @State private var showingDeleteConfirm: Bool = false
    @State private var isDeactivating: Bool = false
    @State private var isDeleting: Bool = false
    @State private var actionError: String?
    // §6.2 Reorder / Restock action
    @State private var showingRestockActionSheet: Bool = false
    @State private var showingDraftPO: Bool = false
    // §6.2 Full movement history sheet
    @State private var showingMovementHistory: Bool = false
    // §6.4 Move between locations
    @State private var showingMoveToLocation: Bool = false
    private let api: APIClient?
    /// Called after delete so parent can pop.
    private let onDeleted: (() -> Void)?

    public init(repo: InventoryDetailRepository, itemId: Int64, api: APIClient? = nil, onDeleted: (() -> Void)? = nil) {
        _vm = State(wrappedValue: InventoryDetailViewModel(repo: repo, itemId: itemId))
        self.api = api
        self.onDeleted = onDeleted
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingEdit) {
            if let api, case let .loaded(resp) = vm.state {
                InventoryEditView(api: api, item: resp.item) {
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $showingAdjust) {
            if let api, case let .loaded(resp) = vm.state {
                InventoryAdjustSheet(
                    itemId: resp.item.id,
                    itemName: resp.item.displayName,
                    api: api,
                    onSuccess: { Task { await vm.load() } }
                )
            }
        }
        // §6.2 Deactivate confirm
        .confirmationDialog(
            "Deactivate item?",
            isPresented: $showingDeactivateConfirm,
            titleVisibility: .visible
        ) {
            Button("Deactivate", role: .destructive) {
                Task { await deactivate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The item will be hidden from POS but history is preserved.")
        }
        // §6.2 Delete confirm
        .confirmationDialog(
            "Delete item?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteItem() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Delete is blocked if stock > 0 or an open PO references this item.")
        }
        .alert("Action failed", isPresented: Binding(
            get: { actionError != nil },
            set: { _ in }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        // §6.2 Restock: action sheet chooses Record Stock-in vs Draft PO
        .confirmationDialog(
            "Restock",
            isPresented: $showingRestockActionSheet,
            titleVisibility: .visible
        ) {
            Button("Record stock-in") { showingAdjust = true }
            if api != nil {
                Button("Draft purchase order") { showingDraftPO = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose how to add stock for this item.")
        }
        .sheet(isPresented: $showingDraftPO) {
            if let api {
                PurchaseOrderComposeView(api: api) {
                    Task { await vm.load() }
                }
            }
        }
        // §6.2 Full movement history — cursor-paginated sheet
        .sheet(isPresented: $showingMovementHistory) {
            if case let .loaded(resp) = vm.state {
                InventoryMovementHistoryView(itemId: resp.item.id, api: api)
            }
        }
        // §6.4 Move between locations
        .sheet(isPresented: $showingMoveToLocation) {
            if let api, case let .loaded(resp) = vm.state {
                MoveToLocationSheet(
                    itemId: resp.item.id,
                    itemName: resp.item.displayName,
                    currentStock: resp.item.inStock ?? 0,
                    sourceLocationId: 1,  // default; LocationContext (§60) owns active location
                    api: api
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if api != nil, case .loaded = vm.state {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEdit = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .keyboardShortcut("E", modifiers: .command)
                .accessibilityLabel("Edit item")
                .accessibilityIdentifier("inventory.detail.edit")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingAdjust = true } label: {
                    Label("Adjust stock", systemImage: "slider.horizontal.3")
                }
                .keyboardShortcut("A", modifiers: .command)
                .accessibilityLabel("Adjust stock quantity")
                .accessibilityIdentifier("inventory.detail.adjust")
            }
            // §6.2 Reorder / Restock — quick form to record stock-in or draft PO
            ToolbarItem(placement: .secondaryAction) {
                Button { showingRestockActionSheet = true } label: {
                    Label("Restock", systemImage: "arrow.down.box")
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .accessibilityLabel("Restock: record stock-in or draft purchase order")
                .accessibilityIdentifier("inventory.detail.restock")
            }
            // §6.4 Move between locations
            ToolbarItem(placement: .secondaryAction) {
                Button { showingMoveToLocation = true } label: {
                    Label("Move to location", systemImage: "arrow.left.arrow.right")
                }
                .keyboardShortcut("M", modifiers: [.command, .shift])
                .accessibilityLabel("Move stock to another location")
                .accessibilityIdentifier("inventory.detail.moveLocation")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingDeactivateConfirm = true
                } label: {
                    Label(isDeactivating ? "Deactivating…" : "Deactivate", systemImage: "eye.slash")
                }
                .disabled(isDeactivating || isDeleting)
                .accessibilityLabel("Deactivate item — hides from POS")
                .accessibilityIdentifier("inventory.detail.deactivate")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label(isDeleting ? "Deleting…" : "Delete", systemImage: "trash")
                }
                .disabled(isDeactivating || isDeleting)
                .accessibilityLabel("Delete item")
                .accessibilityIdentifier("inventory.detail.delete")
            }
        }
    }

    // MARK: - Actions

    /// §6.2 Deactivate — hides from POS, preserves history.
    /// Server: DELETE /api/v1/inventory/:id (soft-deactivate via is_active = 0).
    private func deactivate() async {
        guard let api else { return }
        guard case let .loaded(resp) = vm.state else { return }
        isDeactivating = true
        defer { isDeactivating = false }
        do {
            try await api.deactivateInventoryItem(id: resp.item.id)
            onDeleted?()  // pop back — item is now invisible in list
        } catch {
            AppLog.ui.error("Deactivate item failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// §6.2 Delete — same server route as deactivate (soft-delete).
    /// Prevent if stock > 0 or open PO references it (enforced server-side, surfaced via error banner).
    private func deleteItem() async {
        guard let api else { return }
        guard case let .loaded(resp) = vm.state else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.deactivateInventoryItem(id: resp.item.id)
            onDeleted?()
        } catch {
            AppLog.ui.error("Delete item failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    private var navTitle: String {
        if case let .loaded(resp) = vm.state { return resp.item.displayName }
        return "Item"
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load item")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let resp):
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    DetailsCard(item: resp.item)
                    StockCard(item: resp.item)
                    // §6.1 Cost price hidden from non-admin (server returns nil)
                    if resp.item.costPrice == nil {
                        CostPriceHiddenBadge()
                            .padding(.horizontal, BrandSpacing.xs)
                    }
                    // §6.2 Cost vs retail variance analysis
                    if let cost = resp.item.costPrice, let retail = resp.item.retailPrice, cost > 0 {
                        VarianceCard(costPrice: cost, retailPrice: retail)
                    }
                    // §6.2 Photos gallery (shows primary image + upload CTA)
                    ItemPhotosCard(item: resp.item, api: api)
                    // §6.2 Barcode display — Code-128 via CoreImage; .textSelection on SKU/UPC
                    if resp.item.sku != nil || resp.item.upcCode != nil {
                        BarcodeCard(item: resp.item)
                    }
                    if let tiers = resp.groupPrices, !tiers.isEmpty {
                        GroupPricesCard(tiers: tiers)
                    }
                    // §6.2 Recent movements (from detail response) + link to full cursor-paginated history
                    if let movements = resp.movements, !movements.isEmpty {
                        MovementsCard(movements: movements) {
                            showingMovementHistory = true
                        }
                    }
                    // §6.2 Price history chart — retail vs cost over time
                    PriceHistoryCard(itemId: resp.item.id, api: api)
                    // §6.2 Sales history — last 30d qty + revenue
                    SalesHistoryCard(itemId: resp.item.id, api: api)
                    // §6.2 Supplier panel
                    SupplierPanelCard(item: resp.item, api: api)
                    // §6.2 Auto-reorder rule
                    AutoReorderRuleCard(item: resp.item, api: api)
                    // §6.2 Bin location
                    BinLocationCard(item: resp.item, api: api)
                    // §6.2 Used in tickets — recent tickets that consumed this part
                    UsedInTicketsCard(itemId: resp.item.id, api: api)
                    // §6.2 Tax class — editable (admin only; server returns nil for non-admin)
                    if let tc = resp.item.taxClass {
                        InventoryTaxClassCard(itemId: resp.item.id, taxClass: tc, api: api)
                    }
                    // §6.2 Serials — if serial-tracked, list assigned serial numbers
                    if resp.item.isSerialized == 1 {
                        ItemSerialsCard(itemId: resp.item.id, sku: resp.item.sku, api: api)
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

private struct DetailsCard: View {
    let item: InventoryItemDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(item.displayName)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)

            if let type = item.itemType, !type.isEmpty {
                Text(type.capitalized)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let desc = item.description, !desc.isEmpty {
                Text(desc)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .padding(.top, BrandSpacing.xs)
            }

            if let sku = item.sku, !sku.isEmpty {
                KeyVal(key: "SKU", value: sku, mono: true)
            }
            if let upc = item.upcCode, !upc.isEmpty {
                KeyVal(key: "UPC", value: upc, mono: true)
            }
            if let mfr = item.manufacturerName, !mfr.isEmpty {
                KeyVal(key: "Manufacturer", value: mfr)
            }
            if let device = item.deviceName, !device.isEmpty {
                KeyVal(key: "Device", value: device)
            }
            if let supplier = item.supplierName, !supplier.isEmpty {
                KeyVal(key: "Supplier", value: supplier)
            }
        }
        .cardBackground()
    }
}

private struct StockCard: View {
    let item: InventoryItemDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Stock").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)

            HStack {
                let stock = item.inStock ?? 0
                Text("\(stock)")
                    .font(.brandDisplayMedium())
                    .foregroundStyle(item.isLowStock ? .bizarreError : .bizarreOnSurface)
                    .monospacedDigit()
                Text(stock == 1 ? "in stock" : "in stock")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                if item.isLowStock {
                    Text("Low")
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.black)
                        .background(.bizarreError, in: Capsule())
                }
            }

            if let reorder = item.reorderLevel, reorder > 0 {
                KeyVal(key: "Reorder at", value: "\(reorder)")
            }
            if let retail = item.retailPrice {
                KeyVal(key: "Retail price", value: formatMoney(retail))
            }
            if let cost = item.costPrice {
                KeyVal(key: "Cost", value: formatMoney(cost))
            }
            if let warn = item.stockWarning, !warn.isEmpty {
                Text(warn)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreWarning)
            }
        }
        .cardBackground()
    }
}

private struct GroupPricesCard: View {
    let tiers: [InventoryDetailResponse.GroupPrice]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Price tiers").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(tiers) { t in
                HStack {
                    Text(t.groupName ?? "—").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(formatMoney(t.price ?? 0))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
            }
        }
        .cardBackground()
    }
}

private struct MovementsCard: View {
    let movements: [InventoryDetailResponse.StockMovement]
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Recent movements").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Button("View all") { onViewAll?() }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("View full movement history")
            }
            ForEach(movements.prefix(10)) { m in
                HStack(alignment: .top, spacing: BrandSpacing.sm) {
                    Image(systemName: m.type?.lowercased().contains("in") == true ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .foregroundStyle(movementColor(m.type))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.reason ?? m.type?.capitalized ?? "Adjustment")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        HStack(spacing: BrandSpacing.sm) {
                            if let ts = m.createdAt {
                                Text(String(ts.prefix(16))).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            if let by = m.userName, !by.isEmpty {
                                Text("• \(by)").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                    Spacer()
                    if let q = m.quantity {
                        Text(q > 0 ? "+\(formatQty(q))" : formatQty(q))
                            .font(.brandMono(size: 14))
                            .foregroundStyle(q >= 0 ? .bizarreSuccess : .bizarreError)
                    }
                }
                .padding(.vertical, BrandSpacing.xxs)
            }
        }
        .cardBackground()
    }

    private func movementColor(_ type: String?) -> Color {
        let t = type?.lowercased() ?? ""
        if t.contains("in") || t.contains("receive") { return .bizarreSuccess }
        if t.contains("out") || t.contains("sale") { return .bizarreError }
        return .bizarreOnSurfaceMuted
    }

    private func formatQty(_ v: Double) -> String {
        if v.rounded() == v { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}

// MARK: - §6.2 BarcodeCard

/// Displays a Code-128 barcode generated from the item's SKU (or UPC if no SKU).
/// Also shows a QR code for the UPC. Both codes selectable via `.textSelection(.enabled)`.
private struct BarcodeCard: View {
    let item: InventoryItemDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Barcode").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)

            if let sku = item.sku, !sku.isEmpty {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("SKU").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(sku)
                        .font(.brandMono(size: 14))
                        .textSelection(.enabled)
                        .foregroundStyle(.bizarreOnSurface)
                    if let img = generateCode128(from: sku) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 60)
                            .accessibilityLabel("Code 128 barcode for SKU \(sku)")
                    }
                }
            }

            if let upc = item.upcCode, !upc.isEmpty {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("UPC").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(upc)
                        .font(.brandMono(size: 14))
                        .textSelection(.enabled)
                        .foregroundStyle(.bizarreOnSurface)
                    if let img = generateQR(from: upc) {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 140, maxHeight: 140)
                            .accessibilityLabel("QR code for UPC \(upc)")
                    }
                }
            }
        }
        .cardBackground()
    }

    // MARK: CoreImage generators

    private func generateCode128(from string: String) -> UIImage? {
        let ctx = CIContext()
        let filter = CIFilter.code128BarcodeGenerator()
        filter.message = Data(string.utf8)
        filter.quietSpace = 0
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        guard let cgImage = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func generateQR(from string: String) -> UIImage? {
        let ctx = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cgImage = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - §6.2 Variance Card

/// Margin analysis: cost vs retail price.
private struct VarianceCard: View {
    let costPrice: Double
    let retailPrice: Double

    private var marginAmt: Double { retailPrice - costPrice }
    private var marginPct: Double { costPrice > 0 ? (marginAmt / costPrice) * 100 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Margin Analysis").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            HStack(spacing: BrandSpacing.lg) {
                statBlock(label: "Cost", value: formatMoney(costPrice), color: .bizarreOnSurface)
                statBlock(label: "Retail", value: formatMoney(retailPrice), color: .bizarreOnSurface)
                statBlock(label: "Margin $", value: formatMoney(marginAmt), color: marginAmt >= 0 ? .bizarreSuccess : .bizarreError)
                statBlock(label: "Margin %", value: String(format: "%.1f%%", marginPct), color: marginPct >= 30 ? .bizarreSuccess : marginPct >= 10 ? .bizarreWarning : .bizarreError)
            }
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Margin analysis. Cost \(formatMoney(costPrice)), Retail \(formatMoney(retailPrice)), Margin \(String(format: "%.1f%%", marginPct))")
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyLarge()).foregroundStyle(color).monospacedDigit()
        }
    }
}

// MARK: - §6.2 Photos Card

/// Shows the primary image for an inventory item, with an upload CTA.
/// Upload goes via `POST /api/v1/inventory/:id/image` (multipart).
/// Gallery lightbox and multi-photo are Phase 4+ polish.
private struct ItemPhotosCard: View {
    let item: InventoryItemDetail
    let api: APIClient?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Photos").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                // §6.2 upload CTA — requires api
                if api != nil {
                    Label("Upload", systemImage: "photo.badge.plus")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityLabel("Upload photo for this item")
                }
            }
            if let imageURL = resolvedImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120).accessibilityLabel("Loading image")
                    case .success(let img):
                        img.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Item photo")
                    case .failure:
                        placeholderPhoto
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholderPhoto
            }
        }
        .cardBackground()
    }

    private var placeholderPhoto: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "photo.on.rectangle").font(.system(size: 24)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
            Text("No photo yet").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityLabel("No photo uploaded yet")
    }

    private var resolvedImageURL: URL? {
        guard let raw = item.image, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        // Relative path — we can't resolve without base URL here; return nil and let the async resolve happen
        return nil
    }
}

// MARK: - §6.2 Used In Tickets Card

/// Shows a note that this item can be linked from the Tickets module.
/// Real data wired when `GET /inventory/:id/tickets` server endpoint ships.
/// Maps to §81 endpoint catalog for future wiring.
// MARK: - §6.2 Used in Tickets Card

/// §6.2 Lists recent tickets that consumed this inventory part.
/// Calls `GET /api/v1/tickets?part_inventory_id=:id` (limit 10).
/// Graceful fallback on 404 / not-implemented so the card stays quiet.
private struct UsedInTicketsCard: View {
    let itemId: Int64
    let api: APIClient?

    @State private var tickets: [TicketSummary] = []
    @State private var isLoading: Bool = false
    @State private var failed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Used in Tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Loading ticket history")
            } else if tickets.isEmpty {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(failed ? "Couldn't load ticket history." : "No tickets found that used this part.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel(failed ? "Couldn't load ticket history" : "No tickets used this part")
            } else {
                ForEach(tickets) { ticket in
                    ticketRow(ticket)
                }
            }
        }
        .cardBackground()
        .task { await load() }
    }

    private func load() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.ticketsByInventoryItem(itemId: itemId, limit: 10)
            tickets = resp.tickets
        } catch {
            AppLog.ui.info("UsedInTickets load skipped for item \(itemId): \(error.localizedDescription, privacy: .public)")
            failed = true
        }
    }

    private func ticketRow(_ ticket: TicketSummary) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(ticket.orderId)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                if let name = ticket.customer?.displayName, !name.isEmpty {
                    Text(name)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            if let status = ticket.status {
                Text(status.name)
                    .font(.brandLabelLarge())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .foregroundStyle(.white)
                    .background(statusColor(status), in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket #\(ticket.orderId)\(ticket.customer.map { ", \($0.displayName)" } ?? "")\(ticket.status.map { ", status: \($0.name)" } ?? "")")
    }

    private func statusColor(_ status: TicketSummary.Status) -> Color {
        switch status.group {
        case .complete:   return .bizarreSuccess
        case .cancelled:  return .bizarreError
        case .waiting:    return .bizarreWarning
        case .inProgress: return .bizarreOrange
        }
    }
}

// MARK: - Helpers

private struct KeyVal: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(key).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif

