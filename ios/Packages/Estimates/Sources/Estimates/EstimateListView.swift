import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class EstimateListViewModel {
    public private(set) var items: [Estimate] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do { items = try await api.listEstimates(keyword: searchQuery.isEmpty ? nil : searchQuery) }
        catch {
            AppLog.ui.error("Estimates load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func onSearchChange(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load()
        }
    }
}

public struct EstimateListView: View {
    @State private var vm: EstimateListViewModel
    @State private var searchText: String = ""

    public init(api: APIClient) { _vm = State(wrappedValue: EstimateListViewModel(api: api)) }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Estimates")
        .searchable(text: $searchText, prompt: "Search estimates")
        .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load estimates").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "list.clipboard").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(searchText.isEmpty ? "No estimates" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.items) { est in
                    Row(estimate: est).listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private struct Row: View {
        let estimate: Estimate

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(estimate.orderId ?? "EST-?")
                        .font(.brandMono(size: 15)).foregroundStyle(.bizarreOnSurface)
                    Text(estimate.customerName)
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(1)
                    if estimate.isExpiring == true, let days = estimate.daysUntilExpiry {
                        Text("Expires in \(days)d")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    } else if let until = estimate.validUntil, !until.isEmpty {
                        Text("Valid until \(String(until.prefix(10)))")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(formatMoney(estimate.total ?? 0))
                        .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                    if let status = estimate.status {
                        Text(status.capitalized)
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                            .foregroundStyle(.bizarreOnSurface)
                            .background(Color.bizarreSurface2, in: Capsule())
                    }
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }

        private func formatMoney(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
            return f.string(from: NSNumber(value: v)) ?? "$\(v)"
        }
    }
}
