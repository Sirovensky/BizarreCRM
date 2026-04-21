import Foundation
import Observation
import Core
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryLowStockViewModel {
    public enum State: Sendable {
        case loading
        case loaded([LowStockItem])
        case comingSoon
        case failed(String)
    }

    public private(set) var state: State = .loading
    /// Item whose adjust sheet should be presented (sheet binding).
    public var adjustTarget: LowStockItem?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        state = .loading
        do {
            let items = try await api.listLowStock()
            state = .loaded(items)
        } catch APITransportError.notImplemented {
            state = .comingSoon
        } catch {
            AppLog.ui.error("Low-stock load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct InventoryLowStockView: View {
    @State private var vm: InventoryLowStockViewModel
    @State private var selectedItem: LowStockItem?  // iPad split detail
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: InventoryLowStockViewModel(api: api))
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

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Low stock")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .sheet(item: $vm.adjustTarget) { item in
                InventoryAdjustSheet(
                    itemId: item.id,
                    itemName: item.name,
                    api: api,
                    onSuccess: { Task { await vm.load() } }
                )
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Low stock")
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
            .sheet(item: $vm.adjustTarget) { item in
                InventoryAdjustSheet(
                    itemId: item.id,
                    itemName: item.name,
                    api: api,
                    onSuccess: { Task { await vm.load() } }
                )
            }
        } detail: {
            if let item = selectedItem {
                lowStockDetail(item)
            } else {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("Select an item to adjust")
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                .navigationTitle("Low stock detail")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .comingSoon:
            comingSoonState

        case .failed(let msg):
            failedState(msg)

        case .loaded(let items):
            if items.isEmpty {
                emptyState
            } else {
                itemList(items)
            }
        }
    }

    // MARK: - Item list

    private func itemList(_ items: [LowStockItem]) -> some View {
        List {
            ForEach(items) { item in
                lowStockRow(item)
                    .listRowBackground(Color.bizarreSurface1)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            vm.adjustTarget = item
                        } label: {
                            Label("Adjust stock", systemImage: "slider.horizontal.3")
                        }
                        .tint(.bizarreOrange)
                    }
                    .contextMenu {
                        Button {
                            vm.adjustTarget = item
                        } label: {
                            Label("Adjust stock", systemImage: "slider.horizontal.3")
                        }
                    }
                    .onTapGesture {
                        if !Platform.isCompact { selectedItem = item }
                    }
                    .hoverEffect(.highlight)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func lowStockRow(_ item: LowStockItem) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(item.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if let sku = item.sku, !sku.isEmpty {
                    Text("SKU \(sku)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                HStack(spacing: BrandSpacing.xs) {
                    Text("On hand: \(item.currentQty)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("·")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Reorder at: \(item.reorderThreshold)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: BrandSpacing.sm)
            shortageBadge(item.shortageBy)
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), on hand \(item.currentQty), reorder at \(item.reorderThreshold), short by \(item.shortageBy)")
    }

    private func shortageBadge(_ shortage: Int) -> some View {
        let isCritical = shortage > 5
        return Text("–\(shortage)")
            .font(.brandTitleMedium())
            .monospacedDigit()
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.white)
            .background(isCritical ? Color.bizarreError : Color.bizarreWarning,
                        in: Capsule())
            .accessibilityLabel("Short by \(shortage) units")
    }

    // MARK: - iPad detail panel

    private func lowStockDetail(_ item: LowStockItem) -> some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                VStack(spacing: BrandSpacing.sm) {
                    Text(item.name)
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .multilineTextAlignment(.center)
                    if let sku = item.sku {
                        Text("SKU \(sku)")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                HStack(spacing: BrandSpacing.xl) {
                    metricTile(label: "On hand", value: "\(item.currentQty)",
                               color: .bizarreOnSurface)
                    metricTile(label: "Reorder at", value: "\(item.reorderThreshold)",
                               color: .bizarreWarning)
                    metricTile(label: "Short by", value: "\(item.shortageBy)",
                               color: item.shortageBy > 5 ? .bizarreError : .bizarreWarning)
                }
                Button {
                    vm.adjustTarget = item
                } label: {
                    Label("Adjust stock", systemImage: "slider.horizontal.3")
                        .font(.brandTitleMedium())
                        .frame(maxWidth: 280)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .keyboardShortcut("A", modifiers: .command)
                .accessibilityLabel("Adjust stock for \(item.name)")
                Spacer()
            }
            .padding(BrandSpacing.xl)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metricTile(label: String, value: String, color: Color) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Text(value)
                .font(.brandDisplayMedium())
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Empty / error / coming-soon

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
            Text("All stock levels healthy")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("No items are below their reorder threshold.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("All stock levels healthy")
    }

    private var comingSoonState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Coming soon")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Coming soon — server endpoint pending")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Coming soon — server endpoint pending")
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load low-stock items")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
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
#endif
