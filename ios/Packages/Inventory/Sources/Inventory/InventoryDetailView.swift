import SwiftUI
import Core
import DesignSystem
import Networking

public struct InventoryDetailView: View {
    @State private var vm: InventoryDetailViewModel

    public init(repo: InventoryDetailRepository, itemId: Int64) {
        _vm = State(wrappedValue: InventoryDetailViewModel(repo: repo, itemId: itemId))
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
                    if let tiers = resp.groupPrices, !tiers.isEmpty {
                        GroupPricesCard(tiers: tiers)
                    }
                    if let movements = resp.movements, !movements.isEmpty {
                        MovementsCard(movements: movements)
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

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent movements").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(movements.prefix(25)) { m in
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
