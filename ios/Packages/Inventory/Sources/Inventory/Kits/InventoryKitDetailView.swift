#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6 InventoryKitDetailView
//
// Shows a kit's component table and total-cost breakdown.
// GET /api/v1/inventory/kits/:id returns:
//   { id, name, description, created_at,
//     items: [{ id, kit_id, inventory_item_id, quantity,
//               item_name, sku, retail_price, cost_price, in_stock }] }
// Liquid Glass on navigation chrome only (per CLAUDE.md).

public struct InventoryKitDetailView: View {
    @State private var vm: InventoryKitDetailViewModel

    public init(kitId: Int64, repo: InventoryKitsRepository) {
        _vm = State(wrappedValue: InventoryKitDetailViewModel(kitId: kitId, repo: repo))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView("Loading kit…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let kit = vm.kit {
                    kitDetailBody(kit)
                } else if let error = vm.errorMessage {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                }
            }
        }
        .navigationTitle(vm.kit?.name ?? "Kit Detail")
        .navigationBarTitleDisplayMode(.inline)
        .brandGlass()
        .task { await vm.load() }
        .refreshable { await vm.reload() }
    }

    // MARK: - Main body

    @ViewBuilder
    private func kitDetailBody(_ kit: InventoryKit) -> some View {
        if Platform.isCompact {
            kitDetailList(kit)
        } else {
            kitDetailTable(kit)
        }
    }

    // MARK: - iPhone: list layout

    private func kitDetailList(_ kit: InventoryKit) -> some View {
        List {
            metaSection(kit)
            componentsSection(kit)
            costSection(kit)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - iPad: table layout

    private func kitDetailTable(_ kit: InventoryKit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Meta card
                GroupBox {
                    metaSectionContent(kit)
                } label: {
                    Label("Kit Info", systemImage: "info.circle")
                        .font(.brandLabelLarge())
                }
                .padding(.horizontal, BrandSpacing.md)

                // Components table
                GroupBox {
                    if let items = kit.items, !items.isEmpty {
                        componentsTable(items)
                    }
                } label: {
                    Label("Components", systemImage: "list.bullet")
                        .font(.brandLabelLarge())
                }
                .padding(.horizontal, BrandSpacing.md)

                // Cost summary card
                GroupBox {
                    costSummaryContent(kit)
                } label: {
                    Label("Cost Breakdown", systemImage: "dollarsign.circle")
                        .font(.brandLabelLarge())
                }
                .padding(.horizontal, BrandSpacing.md)
            }
            .padding(.vertical, BrandSpacing.md)
        }
    }

    // MARK: - List sections

    private func metaSection(_ kit: InventoryKit) -> some View {
        Section("Kit Info") {
            metaSectionContent(kit)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    @ViewBuilder
    private func metaSectionContent(_ kit: InventoryKit) -> some View {
        LabeledContent("Name", value: kit.name)
            .font(.brandBodyMedium())
        if let desc = kit.description, !desc.isEmpty {
            LabeledContent("Description", value: desc)
                .font(.brandBodyMedium())
        }
        if let count = kit.items?.count {
            LabeledContent("Components", value: "\(count)")
                .font(.brandBodyMedium())
        }
        if let createdAt = kit.createdAt {
            LabeledContent("Created", value: createdAt)
                .font(.brandCaption())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private func componentsSection(_ kit: InventoryKit) -> some View {
        Section {
            if let items = kit.items, !items.isEmpty {
                ForEach(items) { component in
                    componentRow(component)
                }
            } else {
                Text("No components")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        } header: {
            Text("Components (\(kit.items?.count ?? 0))")
                .font(.brandLabelLarge())
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private func componentRow(_ component: InventoryKitComponent) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.itemName ?? "Unknown item")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let sku = component.sku {
                    Text(sku)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("×\(component.quantity)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
                if let stock = component.inStock {
                    Text("Stock: \(stock)")
                        .font(.brandCaption())
                        .foregroundStyle(
                            (component.isStockInsufficient ?? false)
                                ? .bizarreError
                                : .bizarreOnSurfaceMuted
                        )
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(component.itemName ?? "Unknown"), quantity \(component.quantity)"
            + (component.inStock.map { ", \($0) in stock" } ?? "")
        )
    }

    private func costSection(_ kit: InventoryKit) -> some View {
        Section("Cost Breakdown") {
            costSummaryContent(kit)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    @ViewBuilder
    private func costSummaryContent(_ kit: InventoryKit) -> some View {
        if let items = kit.items {
            ForEach(items) { component in
                if let extCost = component.extendedCostCents {
                    HStack {
                        Text(component.itemName ?? "—")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(formatCents(extCost))
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
            }

            Divider()

            HStack {
                Text("Total Kit Cost")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                if let totalCost = kit.totalCostCents {
                    Text(formatCents(totalCost))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                } else {
                    Text("—")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            if let totalRetail = kit.totalRetailCents {
                HStack {
                    Text("Total Retail Value")
                        .font(.brandCaption())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(formatCents(totalRetail))
                        .font(.brandCaption())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        } else {
            Text("Load kit detail to see cost breakdown.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - iPad components table

    private func componentsTable(_ items: [InventoryKitComponent]) -> some View {
        Table(items) {
            TableColumn("Item") { component in
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.itemName ?? "—")
                        .font(.brandBodyMedium())
                    if let sku = component.sku {
                        Text(sku)
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            TableColumn("Qty") { component in
                Text("\(component.quantity)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
            }
            TableColumn("In Stock") { component in
                if let stock = component.inStock {
                    Text("\(stock)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(
                            (component.isStockInsufficient ?? false)
                                ? .bizarreError
                                : .bizarreSuccess
                        )
                } else {
                    Text("—")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            TableColumn("Ext. Cost") { component in
                if let ext = component.extendedCostCents {
                    Text(formatCents(ext))
                        .font(.brandMono(size: 13))
                } else {
                    Text("—")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            TableColumn("Ext. Retail") { component in
                if let ext = component.extendedRetailCents {
                    Text(formatCents(ext))
                        .font(.brandMono(size: 13))
                } else {
                    Text("—")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Helpers

    private func formatCents(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }
}

// MARK: - Color extensions

private extension Color {
    static var bizarreSuccess: Color { .green }
    static var bizarreError: Color { Color(red: 0.9, green: 0.2, blue: 0.2) }
}

// MARK: - ViewModel

@MainActor
@Observable
final class InventoryKitDetailViewModel {
    var kit: InventoryKit?
    var isLoading: Bool = false
    var errorMessage: String?

    @ObservationIgnored private let kitId: Int64
    @ObservationIgnored private let repo: InventoryKitsRepository

    init(kitId: Int64, repo: InventoryKitsRepository) {
        self.kitId = kitId
        self.repo = repo
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            kit = try await repo.getKit(id: kitId)
        } catch {
            errorMessage = "Failed to load kit: \(error.localizedDescription)"
        }
    }

    func reload() async {
        isLoading = false
        await load()
    }
}
#endif
