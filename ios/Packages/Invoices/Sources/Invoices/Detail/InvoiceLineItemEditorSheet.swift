#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - InvoiceLineItemEditorSheet
//
// §7.2: Editable line items — presented when invoice status allows editing
// (draft or unpaid). Lets staff change description / qty / unit price / discount
// / tax on each line, then PATCH the invoice via PUT /api/v1/invoices/:id.
//
// Only rendered when canEditLines is true (invoice is draft or unpaid with no payments).

// MARK: - EditableLineItem

struct EditableLineItem: Identifiable {
    let id: Int64
    var description: String
    var quantity: Double
    var unitPrice: Double
    var lineDiscount: Double
    var taxAmount: Double

    var lineTotal: Double {
        (unitPrice * quantity) - lineDiscount + taxAmount
    }

    init(from item: InvoiceDetail.LineItem) {
        self.id = item.id
        self.description = item.displayName
        self.quantity = item.quantity ?? 1
        self.unitPrice = item.unitPrice ?? 0
        self.lineDiscount = item.lineDiscount ?? 0
        self.taxAmount = item.taxAmount ?? 0
    }
}

// MARK: - InvoiceLineItemEditorViewModel

@Observable
@MainActor
final class InvoiceLineItemEditorViewModel {
    var lines: [EditableLineItem]
    var isSubmitting = false
    var errorMessage: String?
    var saved = false

    private let api: APIClient
    private let invoiceId: Int64

    init(api: APIClient, invoiceId: Int64, items: [InvoiceDetail.LineItem]) {
        self.api = api
        self.invoiceId = invoiceId
        self.lines = items.map { EditableLineItem(from: $0) }
    }

    var subtotal: Double {
        lines.reduce(0) { $0 + $1.lineTotal }
    }

    func save() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let body = UpdateInvoiceLinesRequest(lineItems: lines.map { line in
                UpdateInvoiceLinesRequest.LineItemUpdate(
                    id: line.id,
                    description: line.description,
                    quantity: line.quantity,
                    unitPrice: line.unitPrice,
                    lineDiscount: line.lineDiscount,
                    taxAmount: line.taxAmount
                )
            })
            try await api.updateInvoiceLines(invoiceId: invoiceId, body: body)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Networking request models

public struct UpdateInvoiceLinesRequest: Encodable, Sendable {
    public let lineItems: [LineItemUpdate]

    public struct LineItemUpdate: Encodable, Sendable {
        public let id: Int64
        public let description: String
        public let quantity: Double
        public let unitPrice: Double
        public let lineDiscount: Double
        public let taxAmount: Double

        enum CodingKeys: String, CodingKey {
            case id, description, quantity
            case unitPrice   = "unit_price"
            case lineDiscount = "line_discount"
            case taxAmount   = "tax_amount"
        }
    }

    enum CodingKeys: String, CodingKey {
        case lineItems = "line_items"
    }
}

public extension APIClient {
    /// PUT /api/v1/invoices/:id/lines — update all line items in place.
    /// Server is expected to recalculate subtotal / tax / total and return the
    /// updated invoice. We discard the response and let the caller reload.
    func updateInvoiceLines(invoiceId: Int64, body: UpdateInvoiceLinesRequest) async throws {
        _ = try await put("/api/v1/invoices/\(invoiceId)/lines", body: body, as: EmptyResponse.self)
    }
}

// MARK: - InvoiceLineItemEditorSheet

public struct InvoiceLineItemEditorSheet: View {
    @State private var vm: InvoiceLineItemEditorViewModel
    private let onSaved: () -> Void

    public init(api: APIClient,
                invoiceId: Int64,
                items: [InvoiceDetail.LineItem],
                onSaved: @escaping () -> Void) {
        _vm = State(wrappedValue: InvoiceLineItemEditorViewModel(api: api, invoiceId: invoiceId, items: items))
        self.onSaved = onSaved
    }

    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                List {
                    ForEach($vm.lines) { $line in
                        lineEditorRow(line: $line)
                    }
                    .onDelete { indices in
                        vm.lines.remove(atOffsets: indices)
                    }

                    Section("Subtotal") {
                        HStack {
                            Text("Subtotal")
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Text(vm.subtotal, format: .currency(code: "USD"))
                                .font(.brandTitleSmall())
                                .foregroundStyle(.bizarreOnSurface)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Subtotal: \(String(format: "$%.2f", vm.subtotal))")
                    }
                }
                .listStyle(.grouped)
            }
            .navigationTitle("Edit Line Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSubmitting {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await vm.save() } }
                            .bold()
                    }
                }
            }
            .alert("Save Failed", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .onChange(of: vm.saved) { _, saved in
                if saved { onSaved(); dismiss() }
            }
        }
        .presentationDetents([.large])
    }

    private func lineEditorRow(line: Binding<EditableLineItem>) -> some View {
        Section {
            // Description
            HStack {
                Text("Description").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                TextField("Item description", text: line.description)
                    .multilineTextAlignment(.trailing)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Line item description")
            }

            // Quantity
            HStack {
                Text("Qty").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                TextField("1", value: line.quantity, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(maxWidth: 80)
                    .accessibilityLabel("Quantity")
            }

            // Unit price
            HStack {
                Text("Unit Price").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                TextField("0.00", value: line.unitPrice, format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Unit price")
            }

            // Line discount
            HStack {
                Text("Discount").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                TextField("0.00", value: line.lineDiscount, format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreSuccess)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Line discount")
            }

            // Tax
            HStack {
                Text("Tax").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                TextField("0.00", value: line.taxAmount, format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .font(.brandMono(size: 15))
                    .foregroundStyle(.bizarreOnSurface)
                    .frame(maxWidth: 100)
                    .accessibilityLabel("Tax amount")
            }

            // Line total (read-only)
            HStack {
                Text("Line Total").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(line.wrappedValue.lineTotal, format: .currency(code: "USD"))
                    .font(.brandBodyMedium()).bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Line total: \(String(format: "$%.2f", line.wrappedValue.lineTotal))")
        } header: {
            Text(line.wrappedValue.description.isEmpty ? "Item" : line.wrappedValue.description)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }
}
#endif
