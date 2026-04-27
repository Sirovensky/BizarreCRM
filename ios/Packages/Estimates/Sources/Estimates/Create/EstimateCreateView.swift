#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §8 Phase 4 — EstimateCreateView
// Full create form: customer, line items, expiry date, discount.
// Glass chrome on toolbar/sheet header only; content on plain surface.
// iPhone: NavigationStack + sheet bottom-detent.
// iPad: NavigationSplitView inline form (takes advantage of wider canvas).

public struct EstimateCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: EstimateCreateViewModel
    // §8.3 — catalog picker
    @State private var showingCatalogPicker: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: EstimateCreateViewModel(api: api))
    }

    /// §8.3 — Create an estimate prefilled from a lead detail (has customerId).
    public init(api: APIClient, prefillFromLeadDetail lead: LeadDetail) {
        _vm = State(wrappedValue: EstimateCreateViewModel(api: api, prefillFromLeadDetail: lead))
    }

    /// §8.3 — Create an estimate prefilled from a lead summary (no customerId; user picks customer).
    public init(api: APIClient, prefillFromLead lead: Lead) {
        _vm = State(wrappedValue: EstimateCreateViewModel(api: api, prefillFromLead: lead))
    }

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        NavigationStack {
            form
                .navigationTitle("New Estimate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { compactToolbar }
        }
        .task { await vm.onAppear() }
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        NavigationStack {
            HStack(spacing: 0) {
                // Left column: header fields
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                        headerFields
                        discountField
                        totalsCard
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                    }
                    .padding(BrandSpacing.xl)
                }
                .frame(minWidth: 320, maxWidth: 420)
                .background(Color.bizarreSurfaceBase)

                Divider()

                // Right column: line items
                ScrollView {
                    VStack(alignment: .leading, spacing: BrandSpacing.md) {
                        lineItemsSection
                    }
                    .padding(BrandSpacing.xl)
                }
                .background(Color.bizarreSurfaceBase)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ipadToolbar }
        }
        .task { await vm.onAppear() }
    }

    // MARK: - Shared form (iPhone only)

    private var form: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    // Draft recovery banner
                    if let record = vm._draftRecord {
                        DraftRecoveryBanner(record: record) {
                            vm.restoreDraft()
                        } onDiscard: {
                            vm.discardDraft()
                        }
                        .padding(.horizontal, BrandSpacing.lg)
                    }

                    Group {
                        headerFields
                        lineItemsSection
                        discountField
                        totalsCard
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.lg)
                }
                .padding(.vertical, BrandSpacing.md)
            }
        }
    }

    // MARK: - Header fields (customer + notes + expiry)

    private var headerFields: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            sectionHeader("Customer")
            if vm.customerDisplayName.isEmpty {
                Text("No customer selected")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No customer selected. Tap to pick one.")
            } else {
                Text(vm.customerDisplayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Customer: \(vm.customerDisplayName)")
            }

            Divider()

            sectionHeader("Notes")
            TextField("Internal notes", text: $vm.notes, axis: .vertical)
                .lineLimit(2...4)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Notes")
                .onChange(of: vm.notes) { _, _ in vm.scheduleAutoSave() }

            Divider()

            sectionHeader("Valid Until")
            TextField("YYYY-MM-DD", text: $vm.validUntil)
                .keyboardType(.numbersAndPunctuation)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Valid until date, format YYYY-MM-DD")
                .onChange(of: vm.validUntil) { _, _ in vm.scheduleAutoSave() }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Line items section

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            HStack {
                sectionHeader("Line Items")
                Spacer()
                Button {
                    vm.addLineItem()
                } label: {
                    Label("Add item", systemImage: "plus.circle.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add line item")
                .accessibilityHint("Adds a new line item row to the estimate")
                .keyboardShortcut("+", modifiers: [.command])
            }

            if vm.lineItems.isEmpty {
                Text("No items yet — tap + to add a part or service.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.md)
            } else {
                ForEach($vm.lineItems) { $item in
                    LineItemRow(item: $item, onDelete: {
                        vm.removeLineItem(id: item.id)
                    }, onChange: {
                        vm.scheduleAutoSave()
                    })
                }
            }

            // §8.3 — catalog button
            Button {
                showingCatalogPicker = true
            } label: {
                Label("Add from catalog", systemImage: "list.bullet.rectangle.portrait")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Add line items from repair-pricing catalog")
            .sheet(isPresented: $showingCatalogPicker) {
                RepairServicePickerSheet(api: vm.apiForPicker) { items in
                    items.forEach { vm.lineItems.append($0) }
                    vm.scheduleAutoSave()
                }
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Discount field

    private var discountField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Discount ($)")
            TextField("0.00", text: $vm.discountText)
                .keyboardType(.decimalPad)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Discount amount in dollars")
                .onChange(of: vm.discountText) { _, _ in vm.scheduleAutoSave() }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Totals summary card

    private var totalsCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            totalsRow("Subtotal", formatMoney(vm.computedSubtotal))
            if vm.computedDiscount > 0 {
                totalsRow("Discount", "−\(formatMoney(vm.computedDiscount))")
            }
            if vm.computedTax > 0 {
                totalsRow("Tax", formatMoney(vm.computedTax))
            }
            Divider()
            HStack {
                Text("Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(vm.computedTotal))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total: \(formatMoney(vm.computedTotal))")
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - Toolbars

    @ToolbarContentBuilder
    private var compactToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel new estimate")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSubmitting ? "Saving…" : "Save") {
                Task {
                    await vm.submit()
                    if vm.queuedOffline || vm.createdId != nil { dismiss() }
                }
            }
            .disabled(!vm.isValid || vm.isSubmitting)
            .accessibilityLabel(vm.isSubmitting ? "Saving estimate" : "Save estimate")
        }
    }

    @ToolbarContentBuilder
    private var ipadToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel new estimate")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(vm.isSubmitting ? "Saving…" : "Save Estimate") {
                Task {
                    await vm.submit()
                    if vm.queuedOffline || vm.createdId != nil { dismiss() }
                }
            }
            .disabled(!vm.isValid || vm.isSubmitting)
            .keyboardShortcut("s", modifiers: [.command])
            .accessibilityLabel(vm.isSubmitting ? "Saving estimate" : "Save estimate")
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityAddTraits(.isHeader)
    }

    private func totalsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - LineItemRow

private struct LineItemRow: View {
    @Binding var item: EstimateDraft.LineItemDraft
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                TextField("Description", text: $item.description)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Line item description")
                    .onChange(of: item.description) { _, _ in onChange() }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.bizarreError)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove line item")
            }

            HStack(spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qty").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("1", text: $item.quantity)
                        .keyboardType(.numberPad)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(width: 52)
                        .accessibilityLabel("Quantity")
                        .onChange(of: item.quantity) { _, _ in onChange() }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Price ($)").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", text: $item.unitPrice)
                        .keyboardType(.decimalPad)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Unit price in dollars")
                        .onChange(of: item.unitPrice) { _, _ in onChange() }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tax ($)").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", text: $item.taxAmount)
                        .keyboardType(.decimalPad)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(width: 70)
                        .accessibilityLabel("Tax amount in dollars")
                        .onChange(of: item.taxAmount) { _, _ in onChange() }
                }

                Spacer()

                // Row subtotal
                if let qty = Double(item.quantity), let price = Double(item.unitPrice) {
                    let sub = qty * price
                    Text(formatMoney(sub))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                        .accessibilityLabel("Line subtotal: \(formatMoney(sub))")
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
#endif
