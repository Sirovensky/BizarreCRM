import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateVersionsView (§8.2 Versioning)
//
// Lists all versions of an estimate (GET /api/v1/estimates/:id/versions).
// Tapping a version loads the read-only snapshot.
// Highlights: version number, total, status, created date.
// iPad: side-by-side list + detail via NavigationSplitView.
// iPhone: NavigationStack.

@MainActor
@Observable
public final class EstimateVersionsViewModel {
    public private(set) var versions: [EstimateVersion] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var selectedVersion: Estimate?
    public private(set) var isLoadingVersion: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let estimateId: Int64
    /// Current approved version id — used to highlight which version the customer approved.
    public let currentVersionNumber: Int?

    public init(api: APIClient, estimateId: Int64, currentVersionNumber: Int?) {
        self.api = api
        self.estimateId = estimateId
        self.currentVersionNumber = currentVersionNumber
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            versions = try await api.estimateVersions(estimateId: estimateId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectVersion(_ version: EstimateVersion) async {
        isLoadingVersion = true
        defer { isLoadingVersion = false }
        do {
            selectedVersion = try await api.estimateVersion(estimateId: estimateId, versionId: version.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// §8 — Fetches a specific version for diff comparison. Returns nil on error.
    public func fetchVersion(_ version: EstimateVersion) async throws -> Estimate? {
        try? await api.estimateVersion(estimateId: estimateId, versionId: version.id)
    }
}

// MARK: - EstimateVersionsView

public struct EstimateVersionsView: View {
    @State private var vm: EstimateVersionsViewModel
    // §8 — Side-by-side diff state
    @State private var diffCompareVersion: EstimateVersion? = nil
    @State private var showingDiff: Bool = false
    @State private var activeDiff: EstimateVersionDiff? = nil
    @State private var isLoadingDiff: Bool = false

    public init(api: APIClient, estimateId: Int64, currentVersionNumber: Int?) {
        _vm = State(wrappedValue: EstimateVersionsViewModel(
            api: api,
            estimateId: estimateId,
            currentVersionNumber: currentVersionNumber
        ))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        // §8 — Version diff sheet
        .sheet(isPresented: $showingDiff) {
            if let diff = activeDiff {
                NavigationStack {
                    EstimateVersionDiffView(diff: diff)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingDiff = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        List {
            versionRows
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase)
        .navigationTitle("Versions")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { loadingOverlay }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                versionRows
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Versions")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let est = vm.selectedVersion {
                VersionDetailCard(estimate: est)
            } else {
                ZStack {
                    Color.bizarreSurfaceBase.ignoresSafeArea()
                    Text("Select a version")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay { loadingOverlay }
    }

    // MARK: - Rows

    @ViewBuilder
    private var versionRows: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            Text(err)
                .foregroundStyle(.bizarreError)
                .font(.brandBodyMedium())
                .padding(BrandSpacing.lg)
        } else {
            ForEach(vm.versions) { version in
                Button { Task { await vm.selectVersion(version) } } label: {
                    VersionRow(
                        version: version,
                        isCurrentApproved: version.versionNumber == vm.currentVersionNumber
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
                .accessibilityLabel(versionA11y(version))
                // §8 — Context menu: "Compare with next version" shortcut
                .contextMenu {
                    if vm.versions.count >= 2 {
                        Button {
                            Task { await loadDiff(for: version) }
                        } label: {
                            Label("Compare with latest", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
            }
        }
    }

    private var loadingOverlay: some View {
        Group {
            if vm.isLoadingVersion {
                ProgressView("Loading version…")
                    .padding(BrandSpacing.xl)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            }
        }
    }

    private func versionA11y(_ v: EstimateVersion) -> String {
        var parts: [String] = ["Version \(v.versionNumber)"]
        if let total = v.total { parts.append(formatMoney(total)) }
        if let status = v.status { parts.append("Status: \(status.capitalized)") }
        if let date = v.createdAt { parts.append("Created \(String(date.prefix(10)))") }
        if v.versionNumber == vm.currentVersionNumber { parts.append("Customer-approved version") }
        return parts.joined(separator: ". ")
    }

    // §8 — Load two estimates and compute diff for the diff sheet
    private func loadDiff(for older: EstimateVersion) async {
        guard let latest = vm.versions.last, latest.id != older.id else { return }
        isLoadingDiff = true
        defer { isLoadingDiff = false }
        do {
            async let olderEst = vm.fetchVersion(older)
            async let newerEst = vm.fetchVersion(latest)
            let (o, n) = try await (olderEst, newerEst)
            guard let o, let n else { return }
            activeDiff = EstimateVersionDiff.compute(older: o, newer: n)
            showingDiff = true
        } catch {
            AppLog.ui.warning("Version diff load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - VersionRow

private struct VersionRow: View {
    let version: EstimateVersion
    let isCurrentApproved: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text("v\(version.versionNumber)")
                        .font(.brandMono(size: 15))
                        .foregroundStyle(.bizarreOnSurface)
                    if isCurrentApproved {
                        Text("Approved")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreSuccess)
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.bizarreSuccess.opacity(0.15), in: Capsule())
                    }
                }
                if let date = version.createdAt {
                    Text(String(date.prefix(10)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            if let total = version.total {
                Text(formatMoney(total))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

// MARK: - VersionDetailCard

private struct VersionDetailCard: View {
    let estimate: Estimate

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    headerCard
                    if let items = estimate.lineItems, !items.isEmpty {
                        lineItemsCard(items)
                    }
                    totalsCard
                }
                .padding(BrandSpacing.xl)
            }
        }
        .navigationTitle("v\(estimate.versionNumber ?? 0)")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Version \(estimate.versionNumber ?? 0)")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if let status = estimate.status {
                Text(status.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let date = estimate.validUntil {
                Text("Valid until \(String(date.prefix(10)))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    @ViewBuilder
    private func lineItemsCard(_ items: [EstimateLineItem]) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Line Items")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Divider()
            ForEach(items) { item in
                HStack {
                    Text(item.description ?? item.itemName ?? "Item")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    if let total = item.total {
                        Text(formatMoney(total))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var totalsCard: some View {
        HStack {
            Text("Total")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text(formatMoney(estimate.total ?? 0))
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total: \(formatMoney(estimate.total ?? 0))")
    }
}

private func formatMoney(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: v)) ?? "$\(v)"
}
