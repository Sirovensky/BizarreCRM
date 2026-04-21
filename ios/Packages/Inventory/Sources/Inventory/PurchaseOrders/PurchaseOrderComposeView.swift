#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - Draft line item

public struct DraftPOLine: Identifiable, Sendable {
    public let id: UUID
    public var sku: String
    public var name: String
    public var qty: String
    public var unitCostCents: String

    public init(sku: String = "", name: String = "", qty: String = "1", unitCostCents: String = "0") {
        self.id = UUID()
        self.sku = sku
        self.name = name
        self.qty = qty
        self.unitCostCents = unitCostCents
    }

    var asRequest: POLineItemRequest {
        POLineItemRequest(
            sku: sku,
            name: name,
            qtyOrdered: Int(qty) ?? 1,
            unitCostCents: Int(unitCostCents) ?? 0
        )
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PurchaseOrderComposeViewModel {
    public private(set) var suppliers: [Supplier] = []
    public var selectedSupplierId: Int64?
    public var lines: [DraftPOLine] = [DraftPOLine()]
    public var expectedDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    public var hasExpectedDate: Bool = false
    public var notes: String = ""

    public private(set) var isLoading: Bool = false
    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: PurchaseOrderRepository
    @ObservationIgnored private let supplierRepo: SupplierRepository

    public init(repo: PurchaseOrderRepository, supplierRepo: SupplierRepository) {
        self.repo = repo
        self.supplierRepo = supplierRepo
    }

    public func loadSuppliers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            suppliers = try await supplierRepo.list()
            if selectedSupplierId == nil { selectedSupplierId = suppliers.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addLine() {
        lines.append(DraftPOLine())
    }

    public func removeLine(at offsets: IndexSet) {
        lines.remove(atOffsets: offsets)
    }

    public var estimatedTotal: Int {
        lines.reduce(0) { sum, line in
            sum + PurchaseOrderCalculator.lineTotal(
                unitCostCents: Int(line.unitCostCents) ?? 0,
                qty: Int(line.qty) ?? 0
            )
        }
    }

    public var isValid: Bool {
        selectedSupplierId != nil && !lines.isEmpty &&
        lines.allSatisfy { !$0.sku.isEmpty && !$0.name.isEmpty }
    }

    public func submit() async -> Bool {
        guard !isSubmitting, isValid, let supplierId = selectedSupplierId else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let body = CreatePurchaseOrderRequest(
            supplierId: supplierId,
            expectedDate: hasExpectedDate ? expectedDate : nil,
            items: lines.map(\.asRequest),
            notes: notes.isEmpty ? nil : notes
        )
        do {
            _ = try await repo.create(body)
            return true
        } catch {
            AppLog.ui.error("PO compose submit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - View

public struct PurchaseOrderComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: PurchaseOrderComposeViewModel
    private let onSuccess: () -> Void

    public init(api: APIClient, onSuccess: @escaping () -> Void) {
        self.onSuccess = onSuccess
        _vm = State(wrappedValue: PurchaseOrderComposeViewModel(
            repo: LivePurchaseOrderRepository(api: api),
            supplierRepo: LiveSupplierRepository(api: api)
        ))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    supplierSection
                    lineItemsSection
                    dateSection
                    notesSection
                    totalSection
                    if let msg = vm.errorMessage {
                        Section {
                            Text(msg).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Purchase Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.loadSuppliers() }
        }
        .presentationDetents([.large])
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isSubmitting {
                ProgressView()
            } else {
                Button("Create") {
                    Task {
                        let ok = await vm.submit()
                        if ok { onSuccess(); dismiss() }
                    }
                }
                .disabled(!vm.isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: Sections

    private var supplierSection: some View {
        Section("Supplier") {
            if vm.isLoading {
                ProgressView()
            } else if vm.suppliers.isEmpty {
                Text("No suppliers. Add one in Supplier management.")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .font(.brandBodyMedium())
            } else {
                Picker("Supplier", selection: $vm.selectedSupplierId) {
                    ForEach(vm.suppliers) { supplier in
                        Text(supplier.name).tag(Optional(supplier.id))
                    }
                }
                .accessibilityLabel("Select supplier")
            }
        }
    }

    private var lineItemsSection: some View {
        Section {
            ForEach($vm.lines) { $line in
                lineEditor(line: $line)
            }
            .onDelete { vm.removeLine(at: $0) }
            Button {
                vm.addLine()
            } label: {
                Label("Add Line Item", systemImage: "plus.circle")
                    .foregroundStyle(.bizarreOrange)
            }
        } header: {
            Text("Line Items")
        }
    }

    private func lineEditor(line: Binding<DraftPOLine>) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            TextField("SKU", text: line.sku)
                .font(.brandMono(size: 14))
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .accessibilityLabel("SKU")
            TextField("Name", text: line.name)
                .font(.brandBodyMedium())
                .accessibilityLabel("Item name")
            HStack(spacing: BrandSpacing.md) {
                TextField("Qty", text: line.qty)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 80)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Quantity")
                TextField("Unit cost (¢)", text: line.unitCostCents)
                    .keyboardType(.numberPad)
                    .font(.brandBodyMedium())
                    .accessibilityLabel("Unit cost in cents")
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
    }

    private var dateSection: some View {
        Section("Expected Delivery") {
            Toggle("Set expected date", isOn: $vm.hasExpectedDate)
            if vm.hasExpectedDate {
                DatePicker(
                    "Expected date",
                    selection: $vm.expectedDate,
                    in: Date()...,
                    displayedComponents: [.date]
                )
                .accessibilityLabel("Expected delivery date")
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes", text: $vm.notes, axis: .vertical)
                .lineLimit(3...6)
                .font(.brandBodyMedium())
        }
    }

    private var totalSection: some View {
        Section {
            HStack {
                Text("Estimated Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(vm.estimatedTotal.formattedCents)
                    .font(.brandTitleMedium())
                    .monospacedDigit()
                    .foregroundStyle(.bizarreOrange)
            }
        }
    }
}

// MARK: - Cents formatter

private extension Int {
    var formattedCents: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: Double(self) / 100.0)) ?? "$0.00"
    }
}
#endif
