#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.3 InvoiceCreateView — full create form: customer picker, line items,
// cart-level discount, notes, due date, payment terms, footer text, deposit flag,
// send-now checkbox. Draft autosave (§63 ext).

public struct InvoiceCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: InvoiceCreateViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: InvoiceCreateViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §63 ext — draft recovery banner
                if let record = vm._draftRecord {
                    DraftRecoveryBanner(record: record) {
                        vm.restoreDraft()
                    } onDiscard: {
                        vm.discardDraft()
                    }
                }

                Form {
                    // MARK: — Customer (§7.3)
                    Section("Customer") {
                        if vm.customerDisplayName.isEmpty {
                            Label("No customer selected", systemImage: "person.badge.plus")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityLabel("No customer selected — tap to pick")
                        } else {
                            Label(vm.customerDisplayName, systemImage: "person.fill")
                                .foregroundStyle(.bizarreOnSurface)
                                .accessibilityLabel("Customer: \(vm.customerDisplayName)")
                        }
                        // Caller injects customer by setting vm.customerId / vm.customerDisplayName
                        // via a sheet callback. (e.g. CustomerPickerSheet → binding)
                    }

                    // MARK: — Line items (§7.3)
                    Section {
                        ForEach($vm.lineItems) { $item in
                            LineItemRow(item: $item) {
                                vm.removeLineItem(id: item.id)
                            } onChange: {
                                vm.scheduleAutoSave()
                            }
                        }
                        Button(action: { vm.addLineItem() }) {
                            Label("Add line item", systemImage: "plus.circle")
                                .foregroundStyle(.bizarreOrange)
                        }
                        .accessibilityLabel("Add line item to invoice")
                    } header: {
                        Text("Line items")
                    } footer: {
                        if !vm.lineItems.isEmpty {
                            HStack {
                                Text("Subtotal")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                Spacer()
                                Text(formatMoney(vm.lineItemsSubtotal))
                                    .monospacedDigit()
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                            .font(.brandLabelSmall())
                        }
                    }

                    // MARK: — Cart discount (§7.3)
                    if !vm.lineItems.isEmpty {
                        Section("Discount") {
                            HStack {
                                Text("$")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                TextField("0.00", value: $vm.cartDiscount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .onChange(of: vm.cartDiscount) { _, _ in vm.scheduleAutoSave() }
                                    .accessibilityLabel("Cart-level discount amount in dollars")
                            }
                            if vm.cartDiscount > 0 {
                                HStack {
                                    Text("Total after discount")
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                    Spacer()
                                    Text(formatMoney(vm.computedTotal))
                                        .monospacedDigit()
                                        .bold()
                                        .foregroundStyle(.bizarreOnSurface)
                                }
                                .font(.brandBodyMedium())
                            }
                        }
                    }

                    // MARK: — Details (§7.3)
                    Section("Details") {
                        TextField("Notes", text: $vm.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .onChange(of: vm.notes) { _, _ in vm.scheduleAutoSave() }
                            .accessibilityLabel("Invoice notes")

                        TextField("Due date (YYYY-MM-DD)", text: $vm.dueOn)
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: vm.dueOn) { _, _ in vm.scheduleAutoSave() }
                            .accessibilityLabel("Due date in YYYY-MM-DD format")

                        TextField("Payment terms (e.g. Net 30)", text: $vm.paymentTerms)
                            .onChange(of: vm.paymentTerms) { _, _ in vm.scheduleAutoSave() }
                            .accessibilityLabel("Payment terms")

                        TextField("Footer text", text: $vm.footerText, axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: vm.footerText) { _, _ in vm.scheduleAutoSave() }
                            .accessibilityLabel("Optional footer text on the invoice")
                    }

                    // MARK: — Options (§7.3)
                    Section("Options") {
                        Toggle(isOn: $vm.depositRequired) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Deposit required")
                                    .foregroundStyle(.bizarreOnSurface)
                                Text("Generates a deposit invoice")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .tint(.bizarreOrange)
                        .onChange(of: vm.depositRequired) { _, _ in vm.scheduleAutoSave() }
                        .accessibilityLabel("Deposit required toggle")

                        Toggle(isOn: $vm.sendOnCreate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send now")
                                    .foregroundStyle(.bizarreOnSurface)
                                Text("Email/SMS to customer on save")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Send invoice to customer on save")
                    }

                    if let err = vm.errorMessage {
                        Section { Text(err).foregroundStyle(.bizarreError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.queuedOffline || vm.createdId != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .task { await vm.onAppear() }
        }
    }
}

// MARK: — Line item row (§7.3)

private struct LineItemRow: View {
    @Binding var item: InvoiceCreateViewModel.DraftLineItem
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                TextField("Description", text: $item.description)
                    .font(.brandBodyMedium())
                    .onChange(of: item.description) { _, _ in onChange() }
                    .accessibilityLabel("Line item description")
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Remove line item")
            }
            HStack(spacing: BrandSpacing.base) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qty").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("1", value: $item.quantity, format: .number)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 56)
                        .onChange(of: item.quantity) { _, _ in onChange() }
                        .accessibilityLabel("Quantity")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unit price").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", value: $item.unitPrice, format: .number)
                        .keyboardType(.decimalPad)
                        .onChange(of: item.unitPrice) { _, _ in onChange() }
                        .accessibilityLabel("Unit price")
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Line total").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(formatMoney(item.lineTotal))
                        .font(.brandBodyMedium())
                        .monospacedDigit()
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

// MARK: — Helpers

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
#endif
