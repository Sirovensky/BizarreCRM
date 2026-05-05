#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16 Reprint — search surface for looking up past sales.
///
/// Accessed from the POS toolbar via ⌘⇧R. Supports search by:
/// - Receipt number (e.g. "R-20240420-0001")
/// - Customer phone
/// - Customer name
///
/// On iPad the view is presented as a sheet; on iPhone it fills the screen.
/// The toolbar uses Liquid Glass per the chrome-only rule.
public struct ReprintSearchView: View {
    @Bindable var vm: ReprintSearchViewModel
    @State private var selectedSummary: SaleSummary? = nil
    @Environment(\.dismiss) private var dismiss
    private let api: APIClient

    public init(vm: ReprintSearchViewModel, api: APIClient) {
        self.vm  = vm
        self.api = api
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Reprint Receipt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("reprint.search.cancel")
                    }
                }
                .searchable(
                    text: $vm.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Receipt #, name, or phone"
                )
                .onSubmit(of: .search) { vm.search() }
                .navigationDestination(item: $selectedSummary) { summary in
                    ReprintDetailView(summary: summary, api: api)
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.searchState {
        case .idle:
            idlePrompt
        case .searching:
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("reprint.search.spinner")
        case .results(let summaries):
            if summaries.isEmpty {
                emptyResults
            } else {
                resultsList(summaries)
            }
        case .error(let message):
            errorView(message: message)
        }
    }

    private var idlePrompt: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "printer.filled.and.paper")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Search for a past sale to reprint its receipt.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reprint.search.idle")
    }

    private var emptyResults: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No sales found")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Try a different receipt number, name, or phone.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reprint.search.empty")
    }

    private func resultsList(_ summaries: [SaleSummary]) -> some View {
        List(summaries) { summary in
            Button {
                selectedSummary = summary
            } label: {
                SaleSummaryRow(summary: summary)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityIdentifier("reprint.result.\(summary.id)")
        }
        .listStyle(.plain)
        .accessibilityIdentifier("reprint.search.results")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Search failed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Retry") { vm.search() }
                .buttonStyle(BrandGlassButtonStyle())
                .tint(.bizarreOrange)
                .accessibilityIdentifier("reprint.search.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reprint.search.error")
    }
}

// MARK: - SaleSummaryRow

private struct SaleSummaryRow: View {
    let summary: SaleSummary

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: summary.date)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(summary.receiptNumber)
                    .font(.brandMono())
                    .foregroundStyle(.bizarreOnSurface)
                if let name = summary.customerName, !name.isEmpty {
                    Text(name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text(formattedDate)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(CartMath.formatCents(summary.totalCents))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.receiptNumber), \(summary.customerName ?? "Walk-in"), \(CartMath.formatCents(summary.totalCents))")
    }
}
#endif
