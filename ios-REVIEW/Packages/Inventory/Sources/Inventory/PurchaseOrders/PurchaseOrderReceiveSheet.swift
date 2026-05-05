#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class PurchaseOrderReceiveViewModel {
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    /// Qty input keyed by line item id.
    public var receivedQty: [Int64: String] = [:]

    @ObservationIgnored private let repo: PurchaseOrderRepository
    @ObservationIgnored private let po: PurchaseOrder

    public init(po: PurchaseOrder, repo: PurchaseOrderRepository) {
        self.po = po
        self.repo = repo
        for line in po.items {
            receivedQty[line.id] = String(line.qtyReceived)
        }
    }

    public func submit() async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let lines = po.items.map { line in
            ReceivePOLine(
                lineItemId: line.id,
                qtyReceived: Int(receivedQty[line.id] ?? "") ?? line.qtyReceived
            )
        }
        do {
            _ = try await repo.receive(id: po.id, ReceivePORequest(lines: lines))
            return true
        } catch {
            AppLog.ui.error("PO receive failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Sheet

public struct PurchaseOrderReceiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PurchaseOrderReceiveViewModel
    private let order: PurchaseOrder
    private let onComplete: () -> Void

    public init(order: PurchaseOrder, api: APIClient, onComplete: @escaping () -> Void) {
        self.order = order
        self.onComplete = onComplete
        _vm = State(wrappedValue: PurchaseOrderReceiveViewModel(
            po: order,
            repo: LivePurchaseOrderRepository(api: api)
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("PO #\(order.id) — Receive Items") {
                        ForEach(order.items) { line in
                            receiveRow(line)
                        }
                    }
                    if let msg = vm.errorMessage {
                        Section {
                            Text(msg)
                                .foregroundStyle(.bizarreError)
                                .font(.brandBodyMedium())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Receive Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Confirm") {
                            Task {
                                let success = await vm.submit()
                                if success {
                                    onComplete()
                                    dismiss()
                                }
                            }
                        }
                        .font(.brandTitleMedium())
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func receiveRow(_ line: POLineItem) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("SKU \(line.sku) · Ordered: \(line.qtyOrdered)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            TextField("Qty", text: Binding(
                get: { vm.receivedQty[line.id] ?? "" },
                set: { vm.receivedQty[line.id] = $0 }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
            .font(.brandBodyLarge())
            .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.name), ordered \(line.qtyOrdered), enter received quantity")
    }
}
#endif
