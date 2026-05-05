#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ChurnCohortView

/// §44.3 — Admin view listing critical/high-risk customers with a
/// "Target campaign" button that integrates with §37 Marketing.
///
/// iPhone: NavigationStack list.
/// iPad: NavigationSplitView with detail pane.
public struct ChurnCohortView: View {
    @State private var vm: ChurnCohortViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: ChurnCohortViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
    }

    // MARK: iPhone

    private var compactLayout: some View {
        NavigationStack {
            cohortContent
                .navigationTitle("At-Risk Customers")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { riskFilterToolbar; campaignToolbar }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        NavigationSplitView {
            cohortContent
                .navigationTitle("At-Risk Customers")
                .toolbar { riskFilterToolbar; campaignToolbar }
                .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
        } detail: {
            if let entry = vm.selectedEntry {
                selectedEntryDetail(entry)
            } else {
                emptyDetail
            }
        }
    }

    // MARK: Shared

    @ViewBuilder
    private var cohortContent: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                errorState(err)
            } else if vm.entries.isEmpty {
                emptyState
            } else {
                cohortList
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var cohortList: some View {
        List(selection: Platform.isCompact ? .constant(nil) : $vm.selectedEntryId) {
            Section {
                ForEach(vm.entries) { entry in
                    ChurnCohortRow(entry: entry)
                        .listRowBackground(Color.bizarreSurface1)
                        .listRowInsets(EdgeInsets(
                            top: BrandSpacing.sm,
                            leading: BrandSpacing.base,
                            bottom: BrandSpacing.sm,
                            trailing: BrandSpacing.base
                        ))
                        .hoverEffect(.highlight)
                        .tag(entry.id)
                }
            } header: {
                Text("\(vm.entries.count) customers at risk")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func selectedEntryDetail(_ entry: ChurnCohortDTO.ChurnCohortEntry) -> some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Text(entry.customerName)
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                ChurnRiskBadge(score: ChurnScore(
                    customerId: entry.customerId,
                    probability0to100: entry.probability,
                    factors: [entry.topFactor].compactMap { $0 },
                    riskLevel: entry.churnRiskLevel
                ))
                if let factor = entry.topFactor {
                    Text(factor)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.xl)
                }
                Spacer()
            }
            .padding(.top, BrandSpacing.xl)
        }
    }

    private var emptyDetail: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Select a customer to see details")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No at-risk customers")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("All customers in the \(vm.riskFilter.label) or higher cohort look healthy.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.bizarreError)
                .font(.system(size: 26))
                .accessibilityHidden(true)
            Text("Couldn't load cohort")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Toolbars

    private var riskFilterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach([ChurnRiskLevel.high, .critical], id: \.self) { level in
                    Button {
                        vm.riskFilter = level
                        Task { await vm.load() }
                    } label: {
                        Label(level.label, systemImage: level.icon)
                    }
                }
            } label: {
                Label(vm.riskFilter.label, systemImage: vm.riskFilter.icon)
                    .font(.brandLabelLarge())
            }
            .accessibilityLabel("Filter by risk level: \(vm.riskFilter.label)")
        }
    }

    private var campaignToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.buildCampaign()
            } label: {
                Label("Target Campaign", systemImage: "megaphone.fill")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .disabled(vm.entries.isEmpty)
            .accessibilityLabel("Create targeted campaign for at-risk customers")
        }
    }
}

// MARK: - Row

private struct ChurnCohortRow: View {
    let entry: ChurnCohortDTO.ChurnCohortEntry

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(riskColor.opacity(0.15))
                Image(systemName: entry.churnRiskLevel.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(riskColor)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.customerName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let factor = entry.topFactor {
                    Text(factor)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            Text("\(entry.probability)%")
                .font(.brandMono(size: 14))
                .foregroundStyle(riskColor)
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.customerName), \(entry.churnRiskLevel.label), \(entry.probability)% churn probability")
    }

    private var riskColor: Color {
        switch entry.churnRiskLevel {
        case .low:      return .bizarreSuccess
        case .medium:   return .bizarreWarning
        case .high:     return .bizarreError
        case .critical: return .bizarreMagenta
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ChurnCohortViewModel {
    var entries: [ChurnCohortDTO.ChurnCohortEntry] = []
    var isLoading = false
    var errorMessage: String?
    var riskFilter: ChurnRiskLevel = .high
    var selectedEntryId: Int64?
    var campaignSpec: ChurnCampaignSpec?

    var selectedEntry: ChurnCohortDTO.ChurnCohortEntry? {
        guard let id = selectedEntryId else { return nil }
        return entries.first { $0.id == id }
    }

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let cohort = try await api.churnCohort(riskLevel: riskFilter)
            entries = cohort.customers
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildCampaign() {
        let cohort = ChurnCohortDTO(customers: entries)
        campaignSpec = ChurnTargetCampaignBuilder.build(from: cohort, riskLevel: riskFilter)
    }
}
#endif
