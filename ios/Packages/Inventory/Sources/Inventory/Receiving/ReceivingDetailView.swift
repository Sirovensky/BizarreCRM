#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §6.3 — Detail view for a single purchase order.
/// Operator scans or manually enters received quantities per line item.
public struct ReceivingDetailView: View {
    @State private var vm: ReceivingDetailViewModel
    @State private var showingBarcodeScanner: Bool = false
    @State private var barcodeFeedback: String?

    public init(api: APIClient, orderId: Int64) {
        _vm = State(wrappedValue: ReceivingDetailViewModel(api: api, orderId: orderId))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            mainContent
        }
        .navigationTitle(vm.order?.supplierName ?? "Receiving")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .toolbar { detailToolbar }
        .sheet(isPresented: $showingBarcodeScanner) {
            InventoryBarcodeScanSheet { value in
                let found = vm.applyBarcode(value)
                barcodeFeedback = found
                    ? "Found: \(value)"
                    : "SKU \(value) not in this order"
                BrandHaptics.tap()
                showingBarcodeScanner = false
            }
        }
        .sheet(isPresented: $vm.showReconciliation) {
            ReceivingReconciliationSheet(entries: vm.finalizeResult)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(message: err)
        } else if let order = vm.order {
            lineItemsList(order: order)
        }
    }

    @ViewBuilder
    private func lineItemsList(order: ReceivingOrder) -> some View {
        List {
            if let feedback = barcodeFeedback {
                Section {
                    Text(feedback)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreSuccess)
                }
                .onAppear {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        barcodeFeedback = nil
                    }
                }
            }

            if vm.hasOverReceipt {
                Section {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                        Text("One or more items exceed the ordered quantity.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
                .accessibilityLabel("Warning: quantity exceeds order for one or more items")
            }

            Section("Line items") {
                ForEach(order.lineItems) { line in
                    ReceivingLineRow(
                        line: line,
                        receivedText: Binding(
                            get: { vm.receivedQty[line.id] ?? String(line.receivedQty) },
                            set: { vm.receivedQty[line.id] = $0 }
                        )
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.finalize() }
            } label: {
                if vm.isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Complete")
                        .fontWeight(.semibold)
                }
            }
            .disabled(vm.isSubmitting || vm.order == nil)
            .accessibilityLabel(vm.isSubmitting ? "Completing receiving" : "Complete receiving")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingBarcodeScanner = true
            } label: {
                Label("Scan", systemImage: "barcode.viewfinder")
            }
            .accessibilityLabel("Scan barcode to find line item")
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
            Text("Couldn't load order").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Line item row

private struct ReceivingLineRow: View {
    let line: ReceivingLineItem
    @Binding var receivedText: String

    private var isOver: Bool {
        guard let received = Int(receivedText) else { return false }
        return received > line.orderedQty
    }

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.base) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(line.productName ?? line.sku)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("SKU: \(line.sku)")
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                Text("Ordered: \(line.orderedQty)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                TextField("Received", text: $receivedText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.brandTitleMedium())
                    .foregroundStyle(isOver ? .bizarreError : .bizarreOnSurface)
                    .frame(width: 72)
                    .accessibilityLabel("Received quantity for \(line.productName ?? line.sku)")
                if isOver {
                    Text("Over!")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}
#endif
