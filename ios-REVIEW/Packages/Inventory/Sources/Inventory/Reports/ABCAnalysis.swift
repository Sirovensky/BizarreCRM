#if canImport(UIKit)
import SwiftUI
import Charts
import DesignSystem
import Networking
import Core

// MARK: - §6.8 ABC Analysis

// MARK: Model

public enum ABCClass: String, CaseIterable, Sendable, Identifiable {
    case a = "A", b = "B", c = "C"
    public var id: String { rawValue }

    /// Standard Pareto thresholds.
    /// A = top 80% of cumulative revenue; B = next 15%; C = bottom 5%.
    public var description: String {
        switch self {
        case .a: return "High-value (top 80% revenue)"
        case .b: return "Mid-value (next 15% revenue)"
        case .c: return "Low-value (bottom 5% revenue)"
        }
    }
    public var color: Color {
        switch self {
        case .a: return .bizarrePrimary
        case .b: return .bizarreWarning
        case .c: return .bizarreTextSecondary
        }
    }
}

public struct ABCItem: Identifiable, Sendable {
    public let id: Int64
    public let sku: String
    public let name: String
    public let revenueCents: Int
    public let abcClass: ABCClass
    public var revenueFormatted: String {
        String(format: "$%.0f", Double(revenueCents) / 100.0)
    }
}

// MARK: Pure Classifier

public enum ABCClassifier {
    public static func classify(items: [InventoryListItem], revenues: [Int64: Int]) -> [ABCItem] {
        let sorted = items.sorted {
            (revenues[$0.id] ?? 0) > (revenues[$1.id] ?? 0)
        }
        let totalRevenue = revenues.values.reduce(0, +)
        guard totalRevenue > 0 else {
            return sorted.map { item in
                ABCItem(
                    id: item.id, sku: item.sku ?? "", name: item.displayName,
                    revenueCents: 0, abcClass: .c
                )
            }
        }
        var cumulative = 0
        return sorted.map { item in
            let rev = revenues[item.id] ?? 0
            cumulative += rev
            let pct = Double(cumulative) / Double(totalRevenue) * 100.0
            let cls: ABCClass = pct <= 80 ? .a : pct <= 95 ? .b : .c
            return ABCItem(
                id: item.id, sku: item.sku ?? "", name: item.displayName,
                revenueCents: rev, abcClass: cls
            )
        }
    }

    public static func groupCounts(from items: [ABCItem]) -> [(ABCClass, Int)] {
        ABCClass.allCases.map { cls in
            (cls, items.filter { $0.abcClass == cls }.count)
        }
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class ABCAnalysisViewModel {
    public private(set) var items: [ABCItem] = []
    public private(set) var groupCounts: [(ABCClass, Int)] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var filter: ABCClass? = nil

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await api.abcAnalysis()
            items = response
            groupCounts = ABCClassifier.groupCounts(from: response)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var filteredItems: [ABCItem] {
        guard let cls = filter else { return items }
        return items.filter { $0.abcClass == cls }
    }
}

// MARK: View

public struct ABCAnalysisView: View {
    @State private var vm: ABCAnalysisViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: ABCAnalysisViewModel(api: api))
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
        .navigationTitle("ABC Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    // MARK: Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                classificationChart
                classFilter
                itemList
            }
            .padding()
        }
    }

    // MARK: Chart

    private var classificationChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Item classification")
                .font(.bizarreHeadline)
            Chart {
                ForEach(vm.groupCounts, id: \.0) { cls, count in
                    BarMark(
                        x: .value("Class", "Class \(cls.rawValue)"),
                        y: .value("Items", count)
                    )
                    .foregroundStyle(cls.color)
                    .annotation(position: .top) {
                        Text("\(count)")
                            .font(.bizarreCaption)
                            .foregroundStyle(cls.color)
                    }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("ABC classification bar chart")
        }
        .padding()
        .background(Color.bizarreSurfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Filter

    private var classFilter: some View {
        HStack(spacing: 8) {
            filterChip(label: "All", value: nil)
            ForEach(ABCClass.allCases) { cls in
                filterChip(label: "Class \(cls.rawValue)", value: cls)
            }
        }
        .padding(.horizontal, 4)
    }

    private func filterChip(label: String, value: ABCClass?) -> some View {
        Button(label) { vm.filter = value }
            .font(.bizarreCaption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(vm.filter == value ? Color.bizarrePrimary : Color.bizarreSurfaceElevated)
            .foregroundStyle(vm.filter == value ? Color.white : Color.bizarreTextPrimary)
            .clipShape(Capsule())
            .accessibilityLabel("Filter by \(label)")
    }

    // MARK: Item List

    private var itemList: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.filteredItems) { item in
                HStack(spacing: 12) {
                    Text(item.abcClass.rawValue)
                        .font(.bizarreHeadline)
                        .foregroundStyle(item.abcClass.color)
                        .frame(width: 24)
                        .accessibilityLabel("Class \(item.abcClass.rawValue)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.bizarreBody)
                            .lineLimit(1)
                        Text(item.sku)
                            .font(.bizarreCaption)
                            .foregroundStyle(Color.bizarreTextSecondary)
                    }
                    Spacer()
                    Text(item.revenueFormatted)
                        .font(.bizarreBody)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.bizarreSurfaceElevated)
                Divider()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(Color.bizarrePrimary)
            Text("No data yet")
                .font(.bizarreHeadline)
            Text("ABC analysis needs sales data. Come back after your first sale.")
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.bizarreError)
            Text("Can't load ABC analysis")
                .font(.bizarreHeadline)
            Text(message)
                .font(.bizarreBody)
                .foregroundStyle(Color.bizarreTextSecondary)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - APIClient extension (§6.8 ABC)

public struct ABCItemResponse: Decodable, Sendable {
    public let id: Int64
    public let sku: String?
    public let name: String
    public let revenueCents: Int
    public let abcClass: String

    enum CodingKeys: String, CodingKey {
        case id, sku, name
        case revenueCents = "revenue_cents"
        case abcClass = "abc_class"
    }
}

extension APIClient {
    func abcAnalysis() async throws -> [ABCItem] {
        let resp = try await get("/api/v1/inventory/reports/abc", as: [ABCItemResponse].self)
        return resp.map { r in
            ABCItem(
                id: r.id,
                sku: r.sku ?? "",
                name: r.name,
                revenueCents: r.revenueCents,
                abcClass: ABCClass(rawValue: r.abcClass) ?? .c
            )
        }
    }
}
#endif
