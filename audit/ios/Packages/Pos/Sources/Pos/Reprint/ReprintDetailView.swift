#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16 Reprint — detail view for a selected past sale.
///
/// Shows the full payment breakdown and offers a "Reprint" button that
/// opens the reason picker. Audit: `ReprintViewModel.confirmReprint` posts
/// `POST /sales/:id/reprint-event` so the shrinkage team can flag abuse.
///
/// The view fetches the full `SaleRecord` from `GET /sales/:id` when it
/// first appears (the list only provides a `SaleSummary`).
/// API calls go through `ReprintRepository` (§20 containment).
public struct ReprintDetailView: View {
    let summary: SaleSummary
    let repository: any ReprintRepository

    @State private var saleRecord: SaleRecord? = nil
    @State private var loadError: String? = nil
    @State private var isLoading = true
    @State private var reprintVM: ReprintViewModel? = nil
    @State private var showReasonPicker = false
    @Environment(\.dismiss) private var dismiss

    /// Convenience init accepting a live `APIClient` — wraps it in `ReprintRepositoryImpl`.
    public init(summary: SaleSummary, api: APIClient) {
        self.summary    = summary
        self.repository = ReprintRepositoryImpl(api: api)
    }

    /// Designated init for testing / dependency injection.
    public init(summary: SaleSummary, repository: any ReprintRepository) {
        self.summary    = summary
        self.repository = repository
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("reprint.detail.spinner")
            } else if let error = loadError {
                errorView(message: error)
            } else if let record = saleRecord {
                detailContent(record: record)
            }
        }
        .navigationTitle(summary.receiptNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFullSale() }
        .sheet(isPresented: $showReasonPicker) {
            if let vm = reprintVM {
                ReprintReasonSheet(vm: vm) {
                    showReasonPicker = false
                }
            }
        }
    }

    // MARK: - Full sale detail

    private func detailContent(record: SaleRecord) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                // Summary card
                summaryCard(record: record)
                    .padding(.horizontal, BrandSpacing.base)

                // Line items
                linesSection(record: record)
                    .padding(.horizontal, BrandSpacing.base)

                // Tenders / payment breakdown
                if !record.tenders.isEmpty {
                    tendersSection(record: record)
                        .padding(.horizontal, BrandSpacing.base)
                }

                // Reprint button
                reprintButton(record: record)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.xl)
            }
            .padding(.top, BrandSpacing.lg)
        }
        .accessibilityIdentifier("reprint.detail.content")
    }

    private func summaryCard(record: SaleRecord) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack {
                Text("Total")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(CartMath.formatCents(record.totalCents))
                    .font(.brandHeadlineLarge())
                    .foregroundStyle(.bizarreOrange)
                    .monospacedDigit()
            }
            Divider()
            if record.taxCents > 0 {
                totalsRow(label: "Tax", cents: record.taxCents)
            }
            if record.tipCents > 0 {
                totalsRow(label: "Tip", cents: record.tipCents)
            }
            if record.discountCents > 0 {
                totalsRow(label: "Discount", cents: -record.discountCents)
            }
            if let customer = record.customerName {
                HStack {
                    Text("Customer").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(customer).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }

    private func totalsRow(label: String, cents: Int) -> some View {
        HStack {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(CartMath.formatCents(cents)).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
        }
    }

    private func linesSection(record: SaleRecord) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Items")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.xxs)
            ForEach(record.lines) { line in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if let sku = line.sku {
                            Text("SKU \(sku)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                    Text("×\(line.quantity)")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(CartMath.formatCents(line.lineTotalCents))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(.vertical, BrandSpacing.xxs)
                Divider()
            }
        }
    }

    private func tendersSection(record: SaleRecord) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Payment")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.xxs)
            ForEach(record.tenders) { tender in
                HStack {
                    var label = tender.method
                    Text(tender.last4.map { "\(tender.method) •\($0)" } ?? tender.method)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(CartMath.formatCents(tender.amountCents))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .padding(.vertical, BrandSpacing.xxs)
            }
        }
    }

    private func reprintButton(record: SaleRecord) -> some View {
        Button {
            let vm = ReprintViewModel(
                sale: record,
                repository: repository,
                onDispatchPrintJob: { payload in
                    // §17.4 print driver receives the payload.
                    // NullReceiptPrinter stub until Hardware pkg wires the driver.
                    AppLog.pos.info("ReprintDetailView: dispatching print job for receipt \(record.receiptNumber, privacy: .public)")
                    _ = PosReceiptRenderer.text(payload)
                }
            )
            reprintVM = vm
            vm.beginReprint()
            showReasonPicker = true
        } label: {
            Label("Reprint Receipt", systemImage: "printer.fill")
                .font(.brandTitleMedium())
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.md)
                .foregroundStyle(.black)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .controlSize(.large)
        .accessibilityIdentifier("reprint.detail.reprintButton")
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadFullSale() } }
                .buttonStyle(BrandGlassButtonStyle())
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reprint.detail.error")
    }

    // MARK: - Data load (via ReprintRepository — §20 containment)

    private func loadFullSale() async {
        isLoading = true
        loadError = nil
        do {
            saleRecord = try await repository.fetchSale(id: summary.id)
        } catch {
            loadError = (error as? AppError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - ReprintReasonSheet

private struct ReprintReasonSheet: View {
    @Bindable var vm: ReprintViewModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List(ReprintViewModel.ReprintReason.allCases) { reason in
                Button {
                    vm.confirmReprint(reason: reason)
                    onDismiss()
                } label: {
                    Label(reason.displayName, systemImage: reason.systemImage)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .accessibilityIdentifier("reprint.reason.\(reason.rawValue)")
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reason for Reprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.cancelReprint()
                        onDismiss()
                    }
                    .accessibilityIdentifier("reprint.reason.cancel")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
#endif
