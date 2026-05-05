import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43 Bulk Edit — Bulk Price Adjustment Sheet

/// Sheet allowing an admin/manager to increase or decrease all repair prices
/// by a percentage or fixed dollar amount.
///
/// Workflow:
///   1. Enter kind (% or $) + value → tap "Preview Changes"
///   2. Review per-row preview table → tap "Apply All"
///   3. VM fires PUTs in sequence; result banner shown on completion.
///
/// iPad primary: preview panel shows a sortable `Table` side-by-side with
/// the form when the horizontal size class is regular. iPhone falls back to
/// a stacked sheet layout.
@MainActor
public struct BulkPriceAdjustmentSheet: View {
    @State private var vm: BulkPriceAdjustmentViewModel
    @Environment(\.dismiss) private var dismiss
    #if canImport(UIKit)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif

    private let onApplied: (Int) -> Void

    public init(
        api: APIClient,
        categoryFilter: String? = nil,
        onApplied: @escaping (Int) -> Void = { _ in }
    ) {
        self.onApplied = onApplied
        _vm = State(wrappedValue: BulkPriceAdjustmentViewModel(api: api))
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Bulk Price Adjustment")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar { toolbarContent }
            .task { await vm.loadPrices() }
            .onChange(of: vm.phase) { _, newPhase in
                if case .applied(let count) = newPhase {
                    onApplied(count)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Content Router

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loadingPrices:
            loadingView
        case .failed(let msg):
            errorView(message: msg)
        case .preview:
            #if canImport(UIKit)
            if hSizeClass == .regular {
                iPadPreviewLayout
            } else {
                phonePreviewLayout
            }
            #else
            iPadPreviewLayout
            #endif
        case .applying(let progress, let total):
            applyingView(progress: progress, total: total)
        case .applied(let count):
            appliedView(count: count)
        case .idle:
            adjustmentForm
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView()
                .tint(.bizarreOrange)
                .scaleEffect(1.5)
            Text("Loading prices…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading repair prices")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Retry") { Task { await vm.loadPrices() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("bulkEdit.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Adjustment Form

    private var adjustmentForm: some View {
        Form {
            // Kind picker
            Section {
                Picker("Type", selection: $vm.adjustmentKind) {
                    Text("Percentage (%)").tag(PricingAdjustmentKind.percentage)
                    Text("Fixed ($)").tag(PricingAdjustmentKind.fixed)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Adjustment type")
                .accessibilityIdentifier("bulkEdit.kind")
            } header: {
                Text("Adjustment Type")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Value entry
            Section {
                HStack {
                    Text(vm.adjustmentKind == .percentage ? "%" : "$")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    TextField(
                        vm.adjustmentKind == .percentage ? "e.g. 10 or -5" : "e.g. 2.50 or -1.00",
                        text: $vm.rawValue
                    )
                    #if canImport(UIKit)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Adjustment value")
                    .accessibilityIdentifier("bulkEdit.value")
                }
                if let msg = vm.valueValidationMessage {
                    Text(msg)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Validation: \(msg)")
                }
            } header: {
                Text("Value")
            } footer: {
                Group {
                    if vm.adjustmentKind == .percentage {
                        Text("Enter a positive value to increase prices or negative to decrease (max ±50%).")
                    } else {
                        Text("Enter a dollar amount to add or subtract from each repair price.")
                    }
                }
                .font(.brandLabelSmall())
            }
            .listRowBackground(Color.bizarreSurface1)

            // Scope summary
            Section {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(vm.priceRows.count) price rows loaded")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        if let cat = vm.categoryFilter {
                            Text("Category: \(cat)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
            } header: {
                Text("Scope")
            }
            .listRowBackground(Color.bizarreSurface1)
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Preview Layouts

    /// iPad: form left, preview table right.
    private var iPadPreviewLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            adjustmentForm
                .frame(maxWidth: 340)
            Divider()
            previewPanel
        }
    }

    /// iPhone: stacked, form scrolled up, table below.
    private var phonePreviewLayout: some View {
        VStack(spacing: 0) {
            adjustmentForm
                .frame(maxHeight: 260)
            Divider()
            previewPanel
        }
    }

    // MARK: - Preview Panel (iPad Table)

    private var previewPanel: some View {
        VStack(spacing: 0) {
            previewSummaryBanner
            Divider()
            #if canImport(UIKit)
            if hSizeClass == .regular {
                previewTable
            } else {
                previewList
            }
            #else
            previewTable
            #endif
        }
    }

    private var previewSummaryBanner: some View {
        let summary = vm.previewSummary
        return HStack(spacing: BrandSpacing.lg) {
            statChip(label: "Rows", value: "\(summary.count)")
            statChip(
                label: "Avg Δ",
                value: String(format: "%+.2f", summary.avgDelta),
                valueColor: summary.avgDelta >= 0 ? .green : .bizarreError
            )
            statChip(
                label: "Total Δ",
                value: String(format: "%+.2f", summary.totalIncrease),
                valueColor: summary.totalIncrease >= 0 ? .green : .bizarreError
            )
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(summary.count) rows, avg change \(String(format: "%+.2f", summary.avgDelta))")
    }

    private func statChip(label: String, value: String, valueColor: Color = .bizarreOnSurface) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.brandLabelLarge().monospacedDigit())
                .foregroundStyle(valueColor)
                .bold()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 8))
    }

    /// iPad sortable Table.
    private var previewTable: some View {
        Table(vm.previewResults) {
            TableColumn("Service") { row in
                Text(row.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            TableColumn("Original") { row in
                Text(String(format: "$ %.2f", row.originalPrice))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            TableColumn("New Price") { row in
                Text(String(format: "$ %.2f", row.newPrice))
                    .font(.brandBodyMedium().monospacedDigit())
                    .foregroundStyle(row.delta >= 0 ? .green : .bizarreError)
            }
            TableColumn("Change") { row in
                Text(String(format: "%+.2f", row.delta))
                    .font(.brandLabelLarge().monospacedDigit())
                    .foregroundStyle(row.delta >= 0 ? .green : .bizarreError)
            }
        }
        .accessibilityLabel("Price preview table")
    }

    /// iPhone list fallback.
    private var previewList: some View {
        List(vm.previewResults) { row in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(String(format: "$ %.2f → $ %.2f", row.originalPrice, row.newPrice))
                        .font(.brandLabelLarge().monospacedDigit())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Text(String(format: "%+.2f", row.delta))
                    .font(.brandLabelLarge().monospacedDigit())
                    .foregroundStyle(row.delta >= 0 ? .green : .bizarreError)
            }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("\(row.name): \(String(format: "%.2f", row.originalPrice)) to \(String(format: "%.2f", row.newPrice))")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Applying / Applied

    private func applyingView(progress: Int, total: Int) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            ProgressView(value: Double(progress), total: Double(total))
                .tint(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.xl)
            Text("Applying \(progress) / \(total)…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Applying changes \(progress) of \(total)")
    }

    private func appliedView(count: Int) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("\(count) price\(count == 1 ? "" : "s") updated successfully.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("bulkEdit.done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("\(count) prices updated")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("bulkEdit.cancel")
                .disabled(vm.isBusy)
        }

        ToolbarItem(placement: .confirmationAction) {
            if vm.isBusy {
                ProgressView().tint(.bizarreOrange)
            } else if case .preview = vm.phase {
                Button("Apply All") {
                    Task { await vm.applyChanges() }
                }
                .bold()
                .foregroundStyle(.bizarreOrange)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("bulkEdit.applyAll")
            } else if case .idle = vm.phase {
                Button("Preview") {
                    vm.generatePreview()
                }
                .bold()
                .disabled(!vm.canPreview)
                .foregroundStyle(vm.canPreview ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("bulkEdit.preview")
            }
        }

        // Back-to-form during preview
        if case .preview = vm.phase {
            ToolbarItem(placement: .topBarLeading) {
                Button("Edit") { vm.cancelPreview() }
                    .accessibilityIdentifier("bulkEdit.backToForm")
            }
        }
    }
}
