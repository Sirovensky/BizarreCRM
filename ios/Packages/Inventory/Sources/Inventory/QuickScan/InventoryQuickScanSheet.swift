#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §6.5 Tab-bar / Dashboard FAB quick scan
//
// Usage: present as a full-screen sheet from the Inventory tab toolbar or
// from the Dashboard FAB. On a successful scan the sheet automatically
// navigates to `InventoryDetailView` for the matched item.
// If a POS session is active (`posCart` provided), the item is added to cart
// instead (Phase 4+ — guarded by nil check today).

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryQuickScanViewModel {

    public enum ScanState: Sendable {
        case idle
        case scanning
        case loading(code: String)
        case found(InventoryBarcodeItem)
        case notFound(code: String)
        case error(String)
    }

    public private(set) var state: ScanState = .idle

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func handleScan(code: String) async {
        guard case .idle = state else { return }
        state = .loading(code: code)
        do {
            let item = try await api.inventoryItemByBarcode(code)
            state = .found(item)
        } catch {
            // 404 → not found; anything else → error
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("404") || msg.localizedCaseInsensitiveContains("not found") {
                state = .notFound(code: code)
            } else {
                AppLog.ui.error("Quick scan lookup failed for \(code, privacy: .public): \(msg, privacy: .public)")
                state = .error(msg)
            }
        }
    }

    public func reset() {
        state = .idle
    }
}

// MARK: - Sheet

/// Full-screen sheet that opens the camera scanner, looks up the barcode,
/// and either shows a result card (tap → item detail) or a "not found" state.
public struct InventoryQuickScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InventoryQuickScanViewModel
    @State private var foundItem: InventoryBarcodeItem?
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: InventoryQuickScanViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // Camera scanner fills background when idle/loading
                if case .idle = vm.state {
                    scannerBackground
                } else if case .loading = vm.state {
                    scannerBackground
                }

                Color.black.opacity(0.3).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    resultOverlay
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.xl)
                }
            }
            .ignoresSafeArea(edges: .all)
            .navigationTitle("Scan Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.brandBodyLarge())
                        .foregroundStyle(.white)
                        .accessibilityLabel("Close scanner")
                }
                if case .found = vm.state {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Scan Again") { vm.reset() }
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Scan another barcode")
                    }
                }
            }
            // Navigate to item detail when user taps on found card
            .navigationDestination(item: $foundItem) { item in
                InventoryDetailView(
                    repo: LiveInventoryDetailRepository(api: api),
                    itemId: item.id,
                    api: api
                )
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Scanner background

    @ViewBuilder
    private var scannerBackground: some View {
        InventoryDataScannerView { code in
            Task { await vm.handleScan(code: code) }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Barcode camera scanner")
    }

    // MARK: - Result overlay

    @ViewBuilder
    private var resultOverlay: some View {
        switch vm.state {
        case .idle:
            scanHintBanner

        case .scanning:
            EmptyView()

        case .loading(let code):
            loadingBanner(code: code)

        case .found(let item):
            foundCard(item: item)

        case .notFound(let code):
            notFoundBanner(code: code)

        case .error(let msg):
            errorBanner(msg: msg)
        }
    }

    // MARK: - Banner / card views

    private var scanHintBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Point camera at a barcode")
                .font(.brandTitleMedium())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Point camera at a barcode to scan")
    }

    private func loadingBanner(code: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            ProgressView()
                .tint(.bizarreOrange)
            Text("Looking up \(String(code.prefix(16)))…")
                .font(.brandBodyLarge())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Looking up barcode")
    }

    private func foundCard(item: InventoryBarcodeItem) -> some View {
        Button {
            foundItem = item
        } label: {
            HStack(spacing: BrandSpacing.md) {
                // Thumbnail
                if let urlString = item.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            placeholderThumb
                        }
                    }
                } else {
                    placeholderThumb
                }

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let sku = item.sku, !sku.isEmpty {
                        Text("SKU \(sku)")
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    HStack(spacing: BrandSpacing.sm) {
                        let stock = item.inStock ?? 0
                        Text("In stock: \(stock)")
                            .font(.brandLabelLarge())
                            .foregroundStyle(stock > 0 ? .bizarreSuccess : .bizarreError)
                        if let retail = item.retailPrice {
                            Text("$\(String(format: "%.2f", retail))")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOrange)
                                .monospacedDigit()
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Found: \(item.displayName). In stock: \(item.inStock ?? 0). Tap to open detail.")
        .accessibilityHint("Double-tap to view item details")
    }

    private func notFoundBanner(code: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No item found")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.white)
                Text(String(code.prefix(20)))
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button("Scan Again") { vm.reset() }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Scan again")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("No inventory item found for barcode \(code)")
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lookup failed")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.white)
                Text(msg)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer()
            Button("Retry") { vm.reset() }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .brandGlass(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Lookup failed: \(msg)")
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.bizarreSurface2)
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "shippingbox")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - brandGlass shim

private extension View {
    func brandGlass(_ material: some ShapeStyle) -> some View {
        background(material)
    }
}

// MARK: - InventoryListView integration helper

/// Convenience modifier: adds a scan FAB (orange barcode button) to the
/// bottom-right corner of any inventory list view.
public extension View {
    /// Attach a quick-scan FAB that presents `InventoryQuickScanSheet` as a sheet.
    /// `api` is the `APIClient` forwarded from the enclosing view.
    func inventoryQuickScanFAB(api: APIClient, isPresented: Binding<Bool>) -> some View {
        overlay(alignment: .bottomTrailing) {
            Button {
                isPresented.wrappedValue = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(BrandSpacing.md)
                    .background(Color.bizarreOrange, in: Circle())
                    .shadow(color: Color.bizarreOrange.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.base + 56) // above Tab bar
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .accessibilityLabel("Quick scan barcode")
            .accessibilityIdentifier("inventory.quickscan.fab")
        }
        .sheet(isPresented: isPresented) {
            InventoryQuickScanSheet(api: api)
        }
    }
}
#endif
