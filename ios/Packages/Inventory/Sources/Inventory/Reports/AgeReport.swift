#if canImport(UIKit)
import SwiftUI
import Charts
import DesignSystem
import Networking
import Core

// MARK: - §6.8 Age Report (dead-stock aging)

// MARK: Models

public enum AgingTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case fresh = "fresh"
    case slow = "slow"
    case dead = "dead"
    case obsolete = "obsolete"

    public var id: String { rawValue }
    public var daysThreshold: Int {
        switch self {
        case .fresh: return 60
        case .slow: return 180
        case .dead: return 365
        case .obsolete: return Int.max
        }
    }
    public var label: String {
        switch self {
        case .fresh: return "Moving (<60d)"
        case .slow: return "Slow (60–180d)"
        case .dead: return "Dead (180–365d)"
        case .obsolete: return "Obsolete (>365d)"
        }
    }
    public var color: Color {
        switch self {
        case .fresh: return .bizarrePrimary
        case .slow: return .bizarreWarning
        case .dead: return .bizarreError
        case .obsolete: return Color.gray
        }
    }
}

public struct AgedItem: Identifiable, Sendable, Decodable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let daysInStock: Int
    public let inStock: Int
    public let retailCents: Int
    public let tier: AgingTier

    public var retailFormatted: String {
        String(format: "$%.2f", Double(retailCents) / 100.0)
    }
    public var totalValueFormatted: String {
        String(format: "$%.0f", Double(retailCents * inStock) / 100.0)
    }

    enum CodingKeys: String, CodingKey {
        case id, sku, name, tier
        case daysInStock = "days_in_stock"
        case inStock = "in_stock"
        case retailCents = "retail_cents"
    }
}

// MARK: Pure Calculator

public enum AgingCalculator {
    public static func groupByTier(items: [AgedItem]) -> [(AgingTier, Int)] {
        AgingTier.allCases.map { tier in
            (tier, items.filter { $0.tier == tier }.count)
        }
    }

    public static func clearanceSuggestions(for items: [AgedItem]) -> [AgedItem] {
        items.filter { $0.tier == .dead || $0.tier == .obsolete }
            .sorted { $0.daysInStock > $1.daysInStock }
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class AgeReportViewModel {
    public private(set) var items: [AgedItem] = []
    public private(set) var grouped: [(AgingTier, Int)] = []
    public private(set) var suggestions: [AgedItem] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var filter: AgingTier? = nil

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await api.ageReport()
            grouped = AgingCalculator.groupByTier(items: items)
            suggestions = AgingCalculator.clearanceSuggestions(for: items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var filteredItems: [AgedItem] {
        guard let f = filter else { return items }
        return items.filter { $0.tier == f }
    }
}

// MARK: View

public struct AgeReportView: View {
    @State private var vm: AgeReportViewModel
    @State private var showClearanceSuggestions = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: AgeReportViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                errorState(message: err)
            } else if vm.items.isEmpty {
                emptyState
            } else {
                mainContent
            }
        }
        .navigationTitle("Dead-Stock Aging")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { clearanceSuggestionsButton }
        .task { await vm.load() }
        .sheet(isPresented: $showClearanceSuggestions) {
            clearanceSuggestionsSheet
        }
    }

    // MARK: Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                agingChart
                tierFilter
                agingList
            }
            .padding()
        }
    }

    // MARK: Aging Chart

    private var agingChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stock age distribution")
                .font(.bizarreHeadline)
            Chart {
                ForEach(vm.grouped, id: \.0) { tier, count in
                    BarMark(
                        x: .value("Tier", tier.label),
                        y: .value("Items", count)
                    )
                    .foregroundStyle(tier.color)
                    .annotation(position: .top) {
                        Text("\(count)")
                            .font(.bizarreCaption)
                            .foregroundStyle(tier.color)
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Stock aging distribution bar chart")
        }
        .padding()
        .background(Color.bizarreSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Tier Filter

    private var tierFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", value: nil)
                ForEach(AgingTier.allCases) { tier in
                    filterChip(label: tier.label, value: tier)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func filterChip(label: String, value: AgingTier?) -> some View {
        Button(label) { vm.filter = value }
            .font(.bizarreCaption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(vm.filter == value ? Color.bizarrePrimary : Color.bizarreSurfaceElevated)
            .foregroundStyle(vm.filter == value ? Color.white : Color.bizarreTextPrimary)
            .clipShape(Capsule())
            .accessibilityLabel("Filter \(label)")
    }

    // MARK: Item List

    private var agingList: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.filteredItems.sorted { $0.daysInStock > $1.daysInStock }) { item in
                HStack(spacing: 12) {
                    Circle()
                        .fill(item.tier.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.bizarreBody)
                            .lineLimit(1)
                        Text("\(item.daysInStock)d in stock · \(item.inStock) units")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.retailFormatted)
                            .font(.bizarreBody)
                        Text(item.totalValueFormatted + " total")
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.bizarreSurfaceElevated)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.name), \(item.daysInStock) days in stock, \(item.tier.label)")
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Clearance Suggestions Sheet

    private var clearanceSuggestionsSheet: some View {
        NavigationStack {
            List {
                Section("Items to action") {
                    ForEach(vm.suggestions) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.bizarreBody)
                            HStack {
                                Label("\(item.daysInStock)d", systemImage: "clock")
                                Text("·")
                                Text(item.tier.label)
                                    .foregroundStyle(item.tier.color)
                            }
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                            Text("Suggestion: apply clearance pricing or bundle with \na hot-selling item.")
                                .font(.bizarreCaption)
                                .foregroundStyle(Color.bizarreTextSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Clearance Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showClearanceSuggestions = false }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var clearanceSuggestionsButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showClearanceSuggestions = true
            } label: {
                Label("Clearance", systemImage: "tag.badge.plus")
            }
            .disabled(vm.suggestions.isEmpty)
            .accessibilityLabel("View clearance suggestions")
        }
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No aged stock")
                .font(.bizarreHeadline)
            Text("All inventory is moving well.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreError)
            Text("Can't load age report")
                .font(.bizarreHeadline)
            Text(message).font(.bizarreBody).foregroundStyle(Color.bizarreTextSecondary)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - APIClient extension (§6.8 Age Report)

extension APIClient {
    func ageReport() async throws -> [AgedItem] {
        try await get("/api/v1/inventory/reports/aging", as: [AgedItem].self)
    }
}
#endif
