#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// A `contextMenu` wrapper for inventory item rows (iPad + iPhone).
///
/// Exposes: Open, Adjust Stock, Copy SKU, Print Label, Archive.
///
/// Usage:
/// ```swift
/// InventoryContextMenu(item: item, api: api,
///     onOpen: { … }, onAdjustStock: { … }, onArchive: { … }) {
///     YourRowView(item: item)
/// }
/// ```
///
/// Ownership: §22 iPad polish (Inventory).
public struct InventoryContextMenu<Content: View>: View {

    // MARK: - Inputs

    let item: InventoryListItem
    let api: APIClient?
    let onOpen: () -> Void
    let onAdjustStock: () -> Void
    let onArchive: () -> Void
    @ViewBuilder var content: () -> Content

    // MARK: - Local state

    @State private var skuCopied: Bool = false
    @State private var showPrintUnavailable: Bool = false

    // MARK: - Body

    public var body: some View {
        content()
            .contextMenu {
                contextMenuItems
            } preview: {
                contextMenuPreview
            }
            .alert("Print unavailable", isPresented: $showPrintUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Label printing requires a connected Bluetooth printer.")
            }
    }

    // MARK: - Menu items

    @ViewBuilder
    private var contextMenuItems: some View {
        // 1. Open
        Button {
            onOpen()
        } label: {
            Label("Open", systemImage: "arrow.up.forward.square")
        }
        .accessibilityLabel("Open \(item.displayName)")

        // 2. Adjust Stock
        if api != nil {
            Button {
                onAdjustStock()
            } label: {
                Label("Adjust Stock", systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Adjust stock for \(item.displayName)")
        }

        Divider()

        // 3. Copy SKU
        Button {
            copySKU()
        } label: {
            Label(
                skuCopied ? "Copied!" : "Copy SKU",
                systemImage: skuCopied ? "checkmark" : "doc.on.doc"
            )
        }
        .accessibilityLabel(skuCopied ? "SKU copied" : "Copy SKU for \(item.displayName)")

        // 4. Print Label
        Button {
            printLabel()
        } label: {
            Label("Print Label", systemImage: "printer")
        }
        .accessibilityLabel("Print label for \(item.displayName)")

        Divider()

        // 5. Archive (destructive)
        if api != nil {
            Button(role: .destructive) {
                onArchive()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .accessibilityLabel("Archive \(item.displayName)")
        }
    }

    // MARK: - Preview card

    private var contextMenuPreview: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(item.displayName)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(2)

            if let sku = item.sku, !sku.isEmpty {
                Text("SKU \(sku)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            HStack(spacing: BrandSpacing.sm) {
                stockPreviewBadge
                if let cents = item.priceCents {
                    Text(formatMoney(cents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
            }
        }
        .padding(BrandSpacing.base)
        .frame(minWidth: 220, alignment: .leading)
        .background(Color.bizarreSurface1)
    }

    @ViewBuilder
    private var stockPreviewBadge: some View {
        let stock = item.inStock ?? 0
        if item.isLowStock {
            Text("Low · \(stock)")
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                .foregroundStyle(.black)
                .background(.bizarreError, in: Capsule())
        } else if stock > 0 {
            Text("\(stock) in stock")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreSuccess)
        } else {
            Text("Out of stock")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Actions

    private func copySKU() {
        let text = item.sku ?? item.displayName
        UIPasteboard.general.string = text
        withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
            skuCopied = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: DesignTokens.Motion.quick)) {
                skuCopied = false
            }
        }
    }

    private func printLabel() {
        // §22 stub — Phase 4 will wire Bluetooth label printer
        showPrintUnavailable = true
    }

    // MARK: - Helpers

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}
#endif
