#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - §6.1 Receive by PO
//
// Allows picking a purchase order from a list, scanning or manually entering
// received quantities per line, and closing the PO on completion.

// MARK: ViewModel

@MainActor
@Observable
public final class ReceiveByPOViewModel {
    public private(set) var openPOs: [PurchaseOrder] = []
    public var selectedPO: PurchaseOrder?
    public private(set) var isLoading = false
    public private(set) var isReceiving = false
    public private(set) var errorMessage: String?
    public private(set) var completedPO: PurchaseOrder?

    @ObservationIgnored private let poRepo: PurchaseOrderRepository
    @ObservationIgnored private let receiveRepo: ReceivingRepositoryProtocol
    public init(poRepo: PurchaseOrderRepository, receiveRepo: ReceivingRepositoryProtocol) {
        self.poRepo = poRepo
        self.receiveRepo = receiveRepo
    }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            openPOs = try await poRepo.list(status: "open")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func receive(po: PurchaseOrder, lines: [ReceivePOLine]) async -> Bool {
        isReceiving = true; errorMessage = nil
        defer { isReceiving = false }
        do {
            _ = try await poRepo.receive(id: po.id, ReceivePORequest(lines: lines))
            // Reload POs and remove the completed one
            openPOs.removeAll { $0.id == po.id }
            completedPO = po
            selectedPO = nil
            BrandHaptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: Protocol for testability

public protocol ReceivingRepositoryProtocol: Sendable {}

// MARK: Main Sheet

public struct ReceiveByPOSheet: View {
    @State private var vm: ReceiveByPOViewModel
    @State private var showReceiveDetail = false
    @Environment(\.dismiss) private var dismiss

    public init(poRepo: PurchaseOrderRepository, receiveRepo: ReceivingRepositoryProtocol) {
        _vm = State(wrappedValue: ReceiveByPOViewModel(poRepo: poRepo, receiveRepo: receiveRepo))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Receive by PO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showReceiveDetail) {
                if let po = vm.selectedPO {
                    POReceiveDetailSheet(po: po) { lines in
                        Task {
                            if await vm.receive(po: po, lines: lines) {
                                showReceiveDetail = false
                            }
                        }
                    }
                }
            }
            .alert("Received!", isPresented: .init(
                get: { vm.completedPO != nil },
                set: { if !$0 { vm.completedPO = nil } }
            )) {
                Button("Done") { dismiss() }
                Button("Receive another", role: .cancel) { vm.completedPO = nil }
            } message: {
                Text("PO \(vm.completedPO.map { "from \($0.supplierName)" } ?? "") has been closed and stock updated.")
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(message: err)
        } else if vm.openPOs.isEmpty {
            emptyState
        } else {
            poList
        }
    }

    private var poList: some View {
        List(vm.openPOs) { po in
            Button {
                vm.selectedPO = po
                showReceiveDetail = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PO #\(po.id)")
                            .font(.bizarreBody)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.bizarreTextPrimary)
                        Text(po.supplierName)
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(po.expectedDateFormatted ?? "No date")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                        Label("\(po.items.count) lines", systemImage: "list.bullet")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.bizarreTextTertiary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("PO from \(po.supplierName), \(po.items.count) lines")
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No open purchase orders")
                .font(.bizarreHeadline)
            Text("Create a purchase order first, then come back to receive stock.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreError)
            Text("Can't load purchase orders")
                .font(.bizarreHeadline)
            Text(message).font(.bizarreBody).foregroundStyle(Color.bizarreTextSecondary)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.brandPrimary)
        }
        .padding()
    }
}

// MARK: - PO Receive Detail Sheet

struct POReceiveDetailSheet: View {
    let po: PurchaseOrder
    let onConfirm: ([ReceivePOLine]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quantities: [Int64: String] = [:]

    init(po: PurchaseOrder, onConfirm: @escaping ([ReceivePOLine]) -> Void) {
        self.po = po
        self.onConfirm = onConfirm
        var q: [Int64: String] = [:]
        for line in po.items {
            q[line.id] = String(line.qty - line.qtyReceived)
        }
        _quantities = State(wrappedValue: q)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase Order from \(po.supplierName)") {
                    ForEach(po.items) { line in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.inventoryName)
                                    .font(.bizarreBody)
                                Text("Ordered: \(line.qty) · Received: \(line.qtyReceived)")
                                    .font(.bizarreCaption)
                                    .foregroundStyle(Color.bizarreTextSecondary)
                            }
                            Spacer()
                            TextField("Qty", text: .init(
                                get: { quantities[line.id] ?? "0" },
                                set: { quantities[line.id] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .accessibilityLabel("Quantity to receive for \(line.inventoryName)")
                        }
                    }
                }
                if po.isPartiallyReceived {
                    Section {
                        Label(
                            "Partial receipt: some items already received.",
                            systemImage: "info.circle"
                        )
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreWarning)
                    }
                }
            }
            .navigationTitle("Receive Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        let lines = po.items.map { line in
                            ReceivePOLine(
                                lineItemId: line.id,
                                qtyReceived: Int(quantities[line.id] ?? "0") ?? 0
                            )
                        }
                        onConfirm(lines)
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif
