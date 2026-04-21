#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class PurchaseOrderDetailViewModel {
    public private(set) var order: PurchaseOrder?
    public private(set) var supplier: Supplier?
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var showReceiveSheet: Bool = false

    @ObservationIgnored private let repo: PurchaseOrderRepository
    @ObservationIgnored private let supplierRepo: SupplierRepository
    @ObservationIgnored private let orderId: Int64

    public init(orderId: Int64, repo: PurchaseOrderRepository, supplierRepo: SupplierRepository) {
        self.orderId = orderId
        self.repo = repo
        self.supplierRepo = supplierRepo
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await repo.get(id: orderId)
            order = fetched
            supplier = try? await supplierRepo.get(id: fetched.supplierId)
        } catch {
            AppLog.ui.error("PO detail load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func cancelOrder() async {
        guard let order else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await repo.cancel(id: order.id)
            let refreshed = try await repo.get(id: order.id)
            self.order = refreshed
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct PurchaseOrderDetailView: View {
    private let initialOrder: PurchaseOrder
    @State private var vm: PurchaseOrderDetailViewModel
    private let onUpdate: () -> Void
    private let api: APIClient

    public init(order: PurchaseOrder, api: APIClient, onUpdate: @escaping () -> Void) {
        self.initialOrder = order
        self.api = api
        self.onUpdate = onUpdate
        _vm = State(wrappedValue: PurchaseOrderDetailViewModel(
            orderId: order.id,
            repo: LivePurchaseOrderRepository(api: api),
            supplierRepo: LiveSupplierRepository(api: api)
        ))
    }

    private var displayOrder: PurchaseOrder { vm.order ?? initialOrder }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.order == nil {
                ProgressView()
            } else {
                scrollContent
            }
        }
        .navigationTitle("PO #\(displayOrder.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.load() }
        .sheet(isPresented: $vm.showReceiveSheet) {
            PurchaseOrderReceiveSheet(
                order: displayOrder,
                api: api,
                onComplete: {
                    Task {
                        await vm.load()
                        onUpdate()
                    }
                }
            )
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if displayOrder.status.isOpen {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Receive") {
                    vm.showReceiveSheet = true
                }
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOrange)
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityLabel("Receive items for PO #\(displayOrder.id)")
            }
        }
    }

    // MARK: Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: BrandSpacing.md) {
                headerSection
                progressSection
                supplierSection
                lineItemsSection
                if let notes = displayOrder.notes, !notes.isEmpty {
                    notesSection(notes)
                }
            }
            .padding(BrandSpacing.md)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("PO #\(displayOrder.id)")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                statusBadge(displayOrder.status)
            }
            HStack(spacing: BrandSpacing.md) {
                labeledValue("Created", value: displayOrder.createdAt.poDateString)
                if let expected = displayOrder.expectedDate {
                    labeledValue("Expected", value: expected.poDateString)
                }
            }
            Text(displayOrder.totalCents.formattedCents)
                .font(.brandDisplayMedium())
                .monospacedDigit()
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Total \(displayOrder.totalCents.formattedCents)")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Progress

    private var progressSection: some View {
        let progress = PurchaseOrderCalculator.receivedProgress(po: displayOrder)
        return VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Receive Progress")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(progress >= 1 ? .bizarreSuccess : .bizarreOrange)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(progress >= 1 ? .bizarreSuccess : .bizarreOrange)
                .accessibilityLabel("Receive progress \(Int(progress * 100)) percent")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Supplier

    @ViewBuilder
    private var supplierSection: some View {
        if let supplier = vm.supplier {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Supplier")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(supplier.name)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let contact = supplier.contactName {
                        Text(contact).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Text(supplier.email)
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                    Text(supplier.phone)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                    Text("Terms: \(supplier.paymentTerms)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("Lead time: \(supplier.leadTimeDays) day\(supplier.leadTimeDays == 1 ? "" : "s")")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Line items

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Line Items (\(displayOrder.items.count))")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            ForEach(displayOrder.items) { line in
                lineRow(line)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func lineRow(_ line: POLineItem) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(line.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("SKU \(line.sku)")
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                HStack(spacing: BrandSpacing.xs) {
                    Text("Ordered: \(line.qtyOrdered)")
                    Text("·")
                    Text("Received: \(line.qtyReceived)")
                        .foregroundStyle(line.qtyReceived >= line.qtyOrdered ? .bizarreSuccess : .bizarreWarning)
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(line.lineTotalCents.formattedCents)
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOnSurface)
                Text("@ \(line.unitCostCents.formattedCents)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.name), ordered \(line.qtyOrdered), received \(line.qtyReceived), \(line.lineTotalCents.formattedCents)")
    }

    // MARK: Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(notes)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Helpers

    private func labeledValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
        }
    }

    private func statusBadge(_ status: POStatus) -> some View {
        let color: Color = {
            switch status {
            case .draft:      return .bizarreOnSurfaceMuted
            case .submitted:  return .bizarreWarning
            case .partial:    return .bizarreWarning
            case .received:   return .bizarreSuccess
            case .cancelled:  return .bizarreError
            }
        }()
        return Text(status.displayName)
            .font(.brandLabelLarge())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.white)
            .background(color, in: Capsule())
    }
}

// MARK: - Date helper

private extension Date {
    var poDateString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }
}
#endif
