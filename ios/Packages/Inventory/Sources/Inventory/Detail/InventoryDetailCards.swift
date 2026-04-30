#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - §6.2 Price History Chart

/// `AreaMark` chart of retail price over time.
/// Data sourced from `GET /api/v1/inventory/:id/price-history`.
/// Gracefully falls back to "no history" state when empty or endpoint not yet available.
public struct PriceHistoryCard: View {
    let itemId: Int64
    let api: APIClient?

    @State private var history: [PriceHistoryPoint] = []
    @State private var isLoading = false
    @State private var showCost = false

    public struct PriceHistoryPoint: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        public let retailCents: Int
        public let costCents: Int
    }

    public init(itemId: Int64, api: APIClient?) {
        self.itemId = itemId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Price History")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                // Toggle cost vs retail
                Picker("Show", selection: $showCost) {
                    Text("Retail").tag(false)
                    Text("Cost").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 140)
                .accessibilityLabel("Toggle between retail and cost price history")
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityLabel("Loading price history")
            } else if history.isEmpty {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No price history available yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .accessibilityLabel("No price history available")
            } else {
                Chart(history) { pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        y: .value("Price", showCost
                            ? Double(pt.costCents) / 100.0
                            : Double(pt.retailCents) / 100.0
                        )
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.bizarreOrange.opacity(0.6), Color.bizarreOrange.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Price", showCost
                            ? Double(pt.costCents) / 100.0
                            : Double(pt.retailCents) / 100.0
                        )
                    )
                    .foregroundStyle(Color.bizarreOrange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.brandLabelSmall())
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            if let d = val.as(Double.self) {
                                Text("$\(Int(d))")
                                    .font(.brandLabelSmall())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 120)
                .accessibilityLabel("\(showCost ? "Cost" : "Retail") price history chart for the past year")
            }
        }
        .cardBackground()
        .task { await loadHistory() }
    }

    @MainActor
    private func loadHistory() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.inventoryPriceHistory(id: itemId)
            history = resp.map { PriceHistoryPoint(date: $0.date, retailCents: $0.retailCents, costCents: $0.costCents) }
        } catch {
            // Graceful fallback — server endpoint may not be available yet
            AppLog.ui.info("Price history not available for item \(itemId): \(error.localizedDescription, privacy: .public)")
            history = []
        }
    }
}

// MARK: - §6.2 Sales History Chart

/// 30d sold qty × revenue line chart.
/// Data sourced from `GET /api/v1/inventory/:id/sales-history`.
public struct SalesHistoryCard: View {
    let itemId: Int64
    let api: APIClient?

    @State private var history: [SalesDayPoint] = []
    @State private var isLoading = false

    public struct SalesDayPoint: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        public let quantity: Int
        public let revenueCents: Int
    }

    public init(itemId: Int64, api: APIClient?) {
        self.itemId = itemId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Sales — Last 30 Days")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityLabel("Loading sales history")
            } else if history.isEmpty {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "cart.circle")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No sales in the last 30 days.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .accessibilityLabel("No recent sales")
            } else {
                Chart(history) { pt in
                    BarMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("Qty", pt.quantity)
                    )
                    .foregroundStyle(Color.bizarreSuccess)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.brandLabelSmall())
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            if let i = val.as(Int.self) { Text("\(i)").font(.brandLabelSmall()) }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 100)
                .accessibilityLabel("Sales quantity bar chart for the last 30 days")

                let totalRevenue = history.reduce(0) { $0 + $1.revenueCents }
                let totalQty = history.reduce(0) { $0 + $1.quantity }
                HStack(spacing: BrandSpacing.lg) {
                    statBlock("Units sold", value: "\(totalQty)")
                    statBlock("Revenue", value: formatMoney(totalRevenue))
                }
            }
        }
        .cardBackground()
        .task { await loadHistory() }
    }

    @MainActor
    private func loadHistory() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.inventorySalesHistory(id: itemId, days: 30)
            history = resp.map { SalesDayPoint(date: $0.date, quantity: $0.quantity, revenueCents: $0.revenueCents) }
        } catch {
            AppLog.ui.info("Sales history not available for item \(itemId): \(error.localizedDescription, privacy: .public)")
            history = []
        }
    }

    private func statBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0"
    }
}

// MARK: - §6.2 Supplier Panel

/// Shows supplier contact info, last cost, reorder SKU, and lead time.
/// Data sourced from `GET /api/v1/inventory/:id/supplier` — falls back to
/// `supplierName` already on `InventoryItemDetail` if endpoint absent.
public struct SupplierPanelCard: View {
    let item: InventoryItemDetail
    let api: APIClient?

    @State private var detail: SupplierDetail?
    @State private var isLoading = false
    /// §6.9/§58 Vendor degradation: on-time rate < 0.7 → show suggestion banner.
    @State private var vendorOnTimeRate: Double? = nil
    @State private var showingComparison: Bool = false

    public struct SupplierDetail: Sendable {
        public let name: String
        public let contactName: String?
        public let email: String?
        public let phone: String?
        public let lastCostCents: Int?
        public let reorderSKU: String?
        public let leadTimeDays: Int?
        public let supplierId: Int64?
        /// §6 Vendor website URL — displayed with a copy-to-clipboard button.
        public let websiteURL: String?
    }

    public init(item: InventoryItemDetail, api: APIClient?) {
        self.item = item
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Supplier")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Loading supplier details")
            } else if let d = detail {
                supplierRows(d)
                // §6.9/§58 Vendor degradation banner
                if let rate = vendorOnTimeRate, rate < 0.7 {
                    vendorDegradationBanner(onTimePct: Int(rate * 100))
                }
            } else if let name = item.supplierName, !name.isEmpty {
                KeyValRow(key: "Supplier", value: name)
                Text("Detailed supplier info not available.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Detailed supplier information unavailable")
            } else {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No supplier assigned.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("No supplier assigned to this item")
            }
        }
        .cardBackground()
        .task { await loadSupplier() }
        .sheet(isPresented: $showingComparison) {
            if let api {
                NavigationStack {
                    SupplierComparisonView(api: api)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showingComparison = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    /// §6.9/§58 Amber degradation banner — shown when primary vendor on-time % < 70%.
    private func vendorDegradationBanner(onTimePct: Int) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vendor on-time: \(onTimePct)%")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreWarning)
                Text("Consider an alternate supplier.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button("Compare") { showingComparison = true }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vendor on-time rate is \(onTimePct) percent. Tap Compare to view alternatives.")
    }

    @ViewBuilder
    private func supplierRows(_ d: SupplierDetail) -> some View {
        KeyValRow(key: "Name", value: d.name)
        if let contact = d.contactName { KeyValRow(key: "Contact", value: contact) }
        if let email = d.email {
            HStack {
                Text("Email").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Link(email, destination: URL(string: "mailto:\(email)")!)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Email supplier: \(email)")
            }
        }
        if let phone = d.phone {
            HStack {
                Text("Phone").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Link(phone, destination: URL(string: "tel:\(phone.filter { "0123456789+".contains($0) })")!)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Call supplier: \(phone)")
            }
        }
        // §6 Vendor-link copy — copy supplier website URL to clipboard
        if let urlStr = d.websiteURL, !urlStr.isEmpty {
            VendorLinkRow(urlString: urlStr)
        }
        if let cost = d.lastCostCents {
            KeyValRow(key: "Last cost", value: formatMoney(cost))
        }
        if let sku = d.reorderSKU, !sku.isEmpty {
            KeyValRow(key: "Reorder SKU", value: sku, mono: true)
        }
        if let lead = d.leadTimeDays {
            KeyValRow(key: "Lead time", value: "\(lead) day\(lead == 1 ? "" : "s")")
        }
        // §6.9 Supplier-prefer toggle — marks this supplier as the preferred source.
        Divider()
            .padding(.vertical, BrandSpacing.xxs)
        SupplierPreferToggle(itemId: item.id, supplierName: d.name)
    }

    @MainActor
    private func loadSupplier() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let d = try await api.inventorySupplierDetail(id: item.id)
            detail = SupplierDetail(
                name: d.name,
                contactName: d.contactName,
                email: d.email,
                phone: d.phone,
                lastCostCents: d.lastCostCents,
                reorderSKU: d.reorderSku,
                leadTimeDays: d.leadTimeDays,
                supplierId: d.supplierId,
                websiteURL: d.websiteURL
            )
            // §6.9/§58 Load vendor analytics in background for degradation banner.
            if let sid = d.supplierId {
                Task {
                    let analytics = try? await api.supplierAnalytics(id: sid)
                    vendorOnTimeRate = analytics?.onTimeRate
                }
            }
        } catch {
            AppLog.ui.info("Supplier detail not available for item \(item.id): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0"
    }
}

// MARK: - §6.2 Auto-Reorder Rule Card

/// View/edit the per-item auto-reorder threshold, reorder qty, and supplier.
/// Persisted via `PATCH /api/v1/inventory/:id/reorder-rule`.
public struct AutoReorderRuleCard: View {
    let item: InventoryItemDetail
    let api: APIClient?

    @State private var threshold: String
    @State private var reorderQty: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedSuccess = false

    public init(item: InventoryItemDetail, api: APIClient?) {
        self.item = item
        self.api = api
        _threshold = State(initialValue: item.reorderLevel.map { "\($0)" } ?? "")
        _reorderQty = State(initialValue: "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Auto-Reorder Rule")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if savedSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Rule saved")
                }
            }

            HStack(spacing: BrandSpacing.base) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Reorder at (qty)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("e.g. 5", text: $threshold)
                        .keyboardType(.numberPad)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Reorder threshold quantity")
                }
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Reorder qty")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("e.g. 20", text: $reorderQty)
                        .keyboardType(.numberPad)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Quantity to reorder")
                }
            }

            if let err = saveError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }

            if api != nil {
                Button {
                    Task { await saveRule() }
                } label: {
                    Text(isSaving ? "Saving…" : "Save Rule")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.xs)
                        .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSaving || (threshold.isEmpty && reorderQty.isEmpty))
                .accessibilityLabel("Save auto-reorder rule")
                .accessibilityIdentifier("inventory.autoreorder.save")
            }
        }
        .cardBackground()
    }

    @MainActor
    private func saveRule() async {
        guard let api else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let thresholdVal = Int(threshold)
            let reorderQtyVal = Int(reorderQty)
            try await api.updateInventoryReorderRule(
                id: item.id,
                threshold: thresholdVal,
                reorderQty: reorderQtyVal
            )
            withAnimation { savedSuccess = true }
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await MainActor.run { savedSuccess = false } }
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            AppLog.ui.error("Reorder rule save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - §6.2 Bin Location Card

/// Text field to view/edit the bin location (aisle/shelf/position).
/// Persisted via `PATCH /api/v1/inventory/:id` with `{ bin_location }`.
public struct BinLocationCard: View {
    let item: InventoryItemDetail
    let api: APIClient?

    @State private var binText: String
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedSuccess = false

    public init(item: InventoryItemDetail, api: APIClient?) {
        self.item = item
        self.api = api
        // `binLocation` may not be in the detail model yet; start blank
        _binText = State(initialValue: "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Bin Location")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if savedSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Bin location saved")
                }
            }

            TextField("e.g. A-01-03", text: $binText)
                .textInputAutocapitalization(.characters)
                .font(.brandMono(size: 16))
                .foregroundStyle(.bizarreOnSurface)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Bin location code — aisle, shelf, position")

            Text("Format: aisle-shelf-position")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            if let err = saveError {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }

            if api != nil {
                Button {
                    Task { await saveBin() }
                } label: {
                    Text(isSaving ? "Saving…" : "Update Bin")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.xs)
                        .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSaving || binText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Update bin location")
                .accessibilityIdentifier("inventory.bin.save")
            }
        }
        .cardBackground()
    }

    @MainActor
    private func saveBin() async {
        guard let api else { return }
        let trimmed = binText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await api.updateInventoryBinLocation(id: item.id, binLocation: trimmed)
            withAnimation { savedSuccess = true }
            Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await MainActor.run { savedSuccess = false } }
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
            AppLog.ui.error("Bin location save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - §6.1 Cost Price Hidden Indicator

/// When server returns `nil` for `costPrice` (non-admin role),
/// shows an admin-only badge so staff know the field is hidden.
public struct CostPriceHiddenBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Cost price (admin only)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("Cost price is hidden — requires admin role")
    }
}

// MARK: - Shared helpers

private struct KeyValRow: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(key)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 14) : .brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - §6 Vendor-link copy helper

/// Displays a vendor website URL with a copy-to-clipboard button.
/// Tapping "Copy" writes the URL string to `UIPasteboard.general` and shows a brief ✓ badge.
private struct VendorLinkRow: View {
    let urlString: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.sm) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(urlString)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOrange)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: BrandSpacing.xs)
            Button {
                UIPasteboard.general.string = urlString
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    await MainActor.run {
                        withAnimation { copied = false }
                    }
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.brandLabelLarge())
                    .foregroundStyle(copied ? .bizarreSuccess : .bizarreOrange)
            }
            .accessibilityLabel(copied ? "Link copied to clipboard" : "Copy vendor link to clipboard")
            .accessibilityIdentifier("inventory.supplier.copyLink")
        }
    }
}

// MARK: - §6 Stock-Count History Chart

/// `BarMark` chart of on-hand stock quantity over time (last 90 days).
/// Data sourced from `GET /api/v1/inventory/:id/stock-history`.
/// Gracefully falls back to a "no history" empty state when data is unavailable.
public struct StockCountHistoryCard: View {
    let itemId: Int64
    let api: APIClient?

    @State private var history: [StockCountPoint] = []
    @State private var isLoading = false

    public struct StockCountPoint: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        public let quantity: Int
    }

    public init(itemId: Int64, api: APIClient?) {
        self.itemId = itemId
        self.api = api
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Stock Count History")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Last 90 days")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityLabel("Loading stock count history")
            } else if history.isEmpty {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("No stock count history available yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .accessibilityLabel("No stock count history available")
            } else {
                Chart(history) { pt in
                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Qty", pt.quantity)
                    )
                    .foregroundStyle(Color.bizarreOrange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    AreaMark(
                        x: .value("Date", pt.date),
                        y: .value("Qty", pt.quantity)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.bizarreOrange.opacity(0.4), Color.bizarreOrange.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 30)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.brandLabelSmall())
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks { val in
                        AxisValueLabel {
                            if let i = val.as(Int.self) {
                                Text("\(i)").font(.brandLabelSmall())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 110)
                .accessibilityChartDescriptor(StockCountHistoryChartDescriptor(history: history))
            }
        }
        .cardBackground()
        .task { await loadHistory() }
    }

    @MainActor
    private func loadHistory() async {
        guard let api else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.inventoryStockHistory(id: itemId, days: 90)
            history = resp.map { StockCountPoint(date: $0.date, quantity: $0.quantity) }
        } catch {
            AppLog.ui.info("Stock history not available for item \(itemId): \(error.localizedDescription, privacy: .public)")
            history = []
        }
    }
}

private struct StockCountHistoryChartDescriptor: AXChartDescriptorRepresentable {
    let history: [StockCountHistoryCard.StockCountPoint]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Date",
            categoryOrder: history.map { ISO8601DateFormatter().string(from: $0.date) }
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Quantity on hand",
            range: 0...Double(history.map(\.quantity).max() ?? 1),
            gridlinePositions: []
        ) { String(format: "%.0f units", $0) }
        let series = AXDataSeriesDescriptor(
            name: "Stock count",
            isContinuous: true,
            dataPoints: history.map {
                AXDataPoint(
                    x: ISO8601DateFormatter().string(from: $0.date),
                    y: Double($0.quantity),
                    label: "\($0.quantity) units"
                )
            }
        )
        return AXChartDescriptor(
            title: "Stock count history — last 90 days",
            summary: "Line chart of on-hand quantity over time",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - APIClient extensions for new endpoints

// These endpoints may not be live on the server yet — all calls gracefully
// fall back to empty data and log at .info level, never crashing the UI.

public struct InventoryPriceHistoryPoint: Decodable, Sendable {
    public let date: Date
    public let retailCents: Int
    public let costCents: Int

    enum CodingKeys: String, CodingKey {
        case date
        case retailCents = "retail_cents"
        case costCents   = "cost_cents"
    }
}

public struct InventorySalesDayPoint: Decodable, Sendable {
    public let date: Date
    public let quantity: Int
    public let revenueCents: Int

    enum CodingKeys: String, CodingKey {
        case date
        case quantity
        case revenueCents = "revenue_cents"
    }
}

public struct InventorySupplierDetailResponse: Decodable, Sendable {
    public let name: String
    public let contactName: String?
    public let email: String?
    public let phone: String?
    public let lastCostCents: Int?
    public let reorderSku: String?
    public let leadTimeDays: Int?
    /// §6.9/§58 Supplier ID — used to fetch analytics for vendor degradation banner.
    public let supplierId: Int64?
    /// §6 Vendor website URL — shown with copy-to-clipboard button in SupplierPanelCard.
    public let websiteURL: String?

    enum CodingKeys: String, CodingKey {
        case name
        case contactName  = "contact_name"
        case email, phone
        case lastCostCents = "last_cost_cents"
        case reorderSku    = "reorder_sku"
        case leadTimeDays  = "lead_time_days"
        case supplierId    = "supplier_id"
        case websiteURL    = "website_url"
    }
}

public struct InventoryReorderRuleRequest: Encodable, Sendable {
    public let reorderLevel: Int?
    public let reorderQty: Int?

    enum CodingKeys: String, CodingKey {
        case reorderLevel = "reorder_level"
        case reorderQty   = "reorder_qty"
    }
}

public struct InventoryBinLocationRequest: Encodable, Sendable {
    public let binLocation: String
    enum CodingKeys: String, CodingKey { case binLocation = "bin_location" }
}

public extension APIClient {
    // MARK: §6.2 — Price history
    func inventoryPriceHistory(id: Int64) async throws -> [InventoryPriceHistoryPoint] {
        try await get("/api/v1/inventory/\(id)/price-history", as: [InventoryPriceHistoryPoint].self)
    }

    // MARK: §6.2 — Sales history
    func inventorySalesHistory(id: Int64, days: Int) async throws -> [InventorySalesDayPoint] {
        try await get(
            "/api/v1/inventory/\(id)/sales-history",
            query: [URLQueryItem(name: "days", value: "\(days)")],
            as: [InventorySalesDayPoint].self
        )
    }

    // MARK: §6.2 — Supplier detail
    func inventorySupplierDetail(id: Int64) async throws -> InventorySupplierDetailResponse {
        try await get("/api/v1/inventory/\(id)/supplier", as: InventorySupplierDetailResponse.self)
    }

    // MARK: §6.2 — Reorder rule update
    func updateInventoryReorderRule(id: Int64, threshold: Int?, reorderQty: Int?) async throws {
        let body = InventoryReorderRuleRequest(reorderLevel: threshold, reorderQty: reorderQty)
        _ = try await patch("/api/v1/inventory/\(id)/reorder-rule", body: body, as: EmptyBody.self)
    }

    // MARK: §6.2 — Bin location update
    func updateInventoryBinLocation(id: Int64, binLocation: String) async throws {
        let body = InventoryBinLocationRequest(binLocation: binLocation)
        _ = try await patch("/api/v1/inventory/\(id)", body: body, as: EmptyBody.self)
    }

    // MARK: §6 — Stock-count history
    func inventoryStockHistory(id: Int64, days: Int) async throws -> [InventoryStockHistoryPoint] {
        try await get(
            "/api/v1/inventory/\(id)/stock-history",
            query: [URLQueryItem(name: "days", value: "\(days)")],
            as: [InventoryStockHistoryPoint].self
        )
    }
}

public struct InventoryStockHistoryPoint: Decodable, Sendable {
    public let date: Date
    public let quantity: Int

    enum CodingKeys: String, CodingKey {
        case date
        case quantity
    }
}

private struct EmptyBody: Decodable {}
#endif
