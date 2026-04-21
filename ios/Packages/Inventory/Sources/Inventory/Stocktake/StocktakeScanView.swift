#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking
import Core

/// §6.4 — Barcode-driven stocktake scanning loop.
/// Expected quantities shown; operator enters actual qty; discrepancies highlighted red.
public struct StocktakeScanView: View {
    @State private var vm: StocktakeScanViewModel
    @State private var showingBarcodeScanner: Bool = false
    @State private var barcodeFeedback: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let api: APIClient

    public init(api: APIClient, sessionId: Int64) {
        self.api = api
        _vm = State(wrappedValue: StocktakeScanViewModel(api: api, sessionId: sessionId))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                if vm.isOffline {
                    OfflineBanner(isOffline: true)
                        .padding(.top, BrandSpacing.xs)
                }
                progressHeader
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                if let feedback = barcodeFeedback {
                    feedbackBanner(text: feedback)
                        .padding(.horizontal, BrandSpacing.base)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                rowsList
            }
        }
        .navigationTitle("Stocktake")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .toolbar { scanToolbar }
        .sheet(isPresented: $showingBarcodeScanner) {
            InventoryBarcodeScanSheet { value in
                let found = vm.applyBarcode(value)
                barcodeFeedback = found ? "Found: \(value)" : "SKU \(value) not in session"
                BrandHaptics.light()
                showingBarcodeScanner = false
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    barcodeFeedback = nil
                }
            }
        }
        .sheet(isPresented: $vm.showReview) {
            StocktakeReviewSheet(
                discrepancies: vm.discrepancies,
                summary: vm.summary,
                isOfflinePending: vm.isOffline
            )
        }
    }

    // MARK: - Progress header (Liquid Glass chrome)

    private var progressHeader: some View {
        let s = vm.summary
        return HStack(spacing: BrandSpacing.lg) {
            progressCell(title: "Counted", value: "\(s.countedRows)/\(s.totalRows)")
            Divider().frame(height: 28)
            progressCell(title: "Discrepancies", value: "\(s.discrepancyCount)",
                         color: s.discrepancyCount > 0 ? .bizarreError : .bizarreSuccess)
            Divider().frame(height: 28)
            progressCell(title: "Net", value: s.netVariance >= 0 ? "+\(s.netVariance)" : "\(s.netVariance)",
                         color: s.netVariance == 0 ? .bizarreSuccess : .bizarreOrange)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreOrange.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Progress: \(s.countedRows) of \(s.totalRows) counted, \(s.discrepancyCount) discrepancies, net variance \(s.netVariance)"
        )
    }

    private func progressCell(title: String, value: String, color: Color = .bizarreOnSurface) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func feedbackBanner(text: String) -> some View {
        Text(text)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity)
            .brandGlass(.regular, tint: .bizarreOrange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityLabel(text)
    }

    // MARK: - Row list

    @ViewBuilder
    private var rowsList: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.rows) { row in
                StocktakeRowView(
                    row: row,
                    actualText: Binding(
                        get: { vm.actualCounts[row.sku] ?? "" },
                        set: { vm.actualCounts[row.sku] = $0 }
                    )
                )
                .listRowBackground(rowBackground(for: row))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func rowBackground(for row: StocktakeRow) -> some View {
        let actual = Int(vm.actualCounts[row.sku] ?? "")
        if let a = actual, a != row.expectedQty {
            Color.bizarreError.opacity(0.08)
        } else {
            Color.bizarreSurface1
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var scanToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.finalize() }
            } label: {
                if vm.isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Finalize")
                        .fontWeight(.semibold)
                }
            }
            .disabled(vm.isSubmitting)
            .accessibilityLabel(vm.isSubmitting ? "Finalizing stocktake" : "Finalize stocktake")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingBarcodeScanner = true
            } label: {
                Label("Scan", systemImage: "barcode.viewfinder")
            }
            .keyboardShortcut("B", modifiers: .command)
            .accessibilityLabel("Scan barcode")
        }
    }
}

// MARK: - Row

private struct StocktakeRowView: View {
    let row: StocktakeRow
    @Binding var actualText: String

    private var actual: Int? { Int(actualText) }
    private var hasDiscrepancy: Bool {
        guard let a = actual else { return false }
        return a != row.expectedQty
    }

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.base) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(row.productName ?? row.sku)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("SKU: \(row.sku)")
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                Text("Expected: \(row.expectedQty)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(hasDiscrepancy ? .bizarreError : .bizarreOnSurfaceMuted)
            }

            Spacer(minLength: BrandSpacing.sm)

            TextField("Actual", text: $actualText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.brandTitleMedium())
                .foregroundStyle(hasDiscrepancy ? .bizarreError : .bizarreOnSurface)
                .frame(width: 72)
                .accessibilityLabel("Actual count for \(row.productName ?? row.sku), expected \(row.expectedQty)")
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
    }
}
#endif
