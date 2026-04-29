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

    // MARK: §6.8 — Stale/dead alert thresholds + bundle hot-seller suggestion

    /// §6.8 — When dead-tier inventory exceeds this share of the fleet (10 %),
    /// the in-app quarterly banner is surfaced so a manager can plan action.
    /// Equivalent to the server-side cron alert (which is Agent 9 domain) but
    /// guarantees iOS users see the call-out without push enabled.
    public static let deadTierAlertFraction: Double = 0.10

    /// Returns true when (dead + obsolete) ≥ `deadTierAlertFraction` of the
    /// items array, with at least 3 such items to avoid noise on tiny fleets.
    public static func shouldShowDeadTierAlert(items: [AgedItem]) -> Bool {
        guard items.count >= 10 else { return false }
        let problemCount = items.filter { $0.tier == .dead || $0.tier == .obsolete }.count
        guard problemCount >= 3 else { return false }
        let fraction = Double(problemCount) / Double(items.count)
        return fraction >= deadTierAlertFraction
    }

    /// §6.8 — Pair each clearance candidate with the *fastest-moving* fresh
    /// item, so the suggestion banner reads
    /// "Bundle with iPhone 15 Case (moving)" rather than the generic line.
    /// Hot seller = the `.fresh` item with the smallest `daysInStock` and at
    /// least one unit in stock. Returns `nil` when no suitable hot seller is
    /// available — caller falls back to the static suggestion text.
    public static func hotSeller(in items: [AgedItem]) -> AgedItem? {
        items
            .filter { $0.tier == .fresh && $0.inStock > 0 }
            .min { lhs, rhs in lhs.daysInStock < rhs.daysInStock }
    }

    /// §6.8 — Compose human-readable bundle suggestion text for `item`,
    /// preferring a concrete hot seller when one exists.
    public static func bundleSuggestionText(for item: AgedItem, hotSeller: AgedItem?) -> String {
        if let hot = hotSeller, hot.id != item.id {
            return "Bundle with \(hot.name) (top mover) at a small discount."
        }
        return "Bundle with a top-selling item at a small discount."
    }
}

// MARK: ViewModel

@MainActor
@Observable
public final class AgeReportViewModel {
    public private(set) var items: [AgedItem] = []
    public private(set) var grouped: [(AgingTier, Int)] = []
    public private(set) var suggestions: [AgedItem] = []
    public private(set) var hotSeller: AgedItem?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var filter: AgingTier? = nil

    /// §6.8 — Snapshot count of (dead + obsolete) items used by the in-app alert.
    public var deadAndObsoleteCount: Int {
        items.filter { $0.tier == .dead || $0.tier == .obsolete }.count
    }

    /// §6.8 — Whether the quarterly dead-stock alert banner should be shown,
    /// after honouring the per-quarter dismiss flag in `UserDefaults`.
    public var shouldShowDeadStockAlert: Bool {
        guard AgingCalculator.shouldShowDeadTierAlert(items: items) else { return false }
        return !DeadStockAlertDismissal.isDismissed(for: Date())
    }

    /// §6.8 — Vendor-return action state for the clearance sheet.
    public private(set) var vendorReturnInFlight: Set<Int64> = []
    public private(set) var vendorReturnSuccess: Int64?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await api.ageReport()
            grouped = AgingCalculator.groupByTier(items: items)
            suggestions = AgingCalculator.clearanceSuggestions(for: items)
            hotSeller = AgingCalculator.hotSeller(in: items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var filteredItems: [AgedItem] {
        guard let f = filter else { return items }
        return items.filter { $0.tier == f }
    }

    /// §6.8 — Persist the dead-stock alert dismissal for the current calendar quarter.
    public func dismissDeadStockAlert() {
        DeadStockAlertDismissal.markDismissed(for: Date())
    }

    /// §6.8 — Initiate a "Return to vendor" flow from the clearance suggestion sheet.
    /// On 200 OK the row is hidden from suggestions to avoid double-submits.
    public func returnToVendor(_ item: AgedItem) async {
        guard !vendorReturnInFlight.contains(item.id) else { return }
        vendorReturnInFlight.insert(item.id)
        defer { vendorReturnInFlight.remove(item.id) }
        do {
            _ = try await api.requestVendorReturn(itemId: item.id, qty: item.inStock)
            // Optimistically drop from local list so the action button disables.
            suggestions.removeAll { $0.id == item.id }
            items.removeAll { $0.id == item.id }
            grouped = AgingCalculator.groupByTier(items: items)
            vendorReturnSuccess = item.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Dismissal persistence (per calendar quarter)

enum DeadStockAlertDismissal {
    static let userDefaultsKey = "ios.inventory.ageReport.deadStockAlert.dismissedQuarter"

    static func quarterKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let month = comps.month ?? 1
        let quarter = ((month - 1) / 3) + 1
        return "\(comps.year ?? 0)-Q\(quarter)"
    }

    static func isDismissed(for date: Date, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: userDefaultsKey) == quarterKey(for: date)
    }

    static func markDismissed(for date: Date, defaults: UserDefaults = .standard) {
        defaults.set(quarterKey(for: date), forKey: userDefaultsKey)
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
                if vm.shouldShowDeadStockAlert {
                    deadStockBanner
                }
                if Platform.isCompact {
                    // iPhone — single column stack
                    agingChart
                    tierFilter
                    agingList
                } else {
                    // iPad — chart + filter side-by-side, list full width below
                    HStack(alignment: .top, spacing: 16) {
                        agingChart
                            .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Filter").font(.bizarreCaption)
                                .foregroundStyle(Color.bizarreTextSecondary)
                            tierFilter
                        }
                        .frame(width: 320)
                    }
                    agingList
                }
            }
            .padding()
        }
    }

    // §6.8 — In-app quarterly dead-stock banner.
    private var deadStockBanner: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(Color.bizarreError)
                .font(.system(size: 22))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("\(vm.deadAndObsoleteCount) items hit the dead tier")
                    .font(.bizarreHeadline)
                Text("Plan clearance, return-to-vendor, or bundle promos this quarter.")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
            Spacer(minLength: 8)
            Button {
                vm.dismissDeadStockAlert()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
            }
            .accessibilityLabel("Dismiss dead-stock alert for this quarter")
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreError.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vm.deadAndObsoleteCount) items hit the dead tier this quarter. Plan action.")
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
                        clearanceRow(item)
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
        // iPad: surface as a wider regular sheet so the action buttons stay one-line.
        .frame(
            minWidth: Platform.isCompact ? nil : 540,
            minHeight: Platform.isCompact ? nil : 480
        )
    }

    @ViewBuilder
    private func clearanceRow(_ item: AgedItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name).font(.bizarreBody)
            HStack {
                Label("\(item.daysInStock)d", systemImage: "clock")
                Text("·")
                Text(item.tier.label).foregroundStyle(item.tier.color)
                Text("·")
                Text("\(item.inStock) units")
            }
            .font(.bizarreCaption)
            .foregroundStyle(Color.bizarreTextSecondary)

            // §6.8 — Bundle suggestion line (concrete hot seller when known).
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.and.arrow.backward")
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarrePrimary)
                Text(AgingCalculator.bundleSuggestionText(for: item, hotSeller: vm.hotSeller))
                    .font(.bizarreCaption)
                    .foregroundStyle(Color.bizarreTextSecondary)
            }
            .accessibilityElement(children: .combine)

            // §6.8 — Per-item Return-to-vendor action.
            HStack(spacing: 8) {
                Button {
                    Task { await vm.returnToVendor(item) }
                } label: {
                    if vm.vendorReturnInFlight.contains(item.id) {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Return to vendor", systemImage: "arrow.uturn.left")
                            .font(.bizarreCaption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(vm.vendorReturnInFlight.contains(item.id))
                .accessibilityLabel("Return \(item.name) to vendor")

                if vm.vendorReturnSuccess == item.id {
                    Label("Requested", systemImage: "checkmark.seal")
                        .font(.bizarreCaption)
                        .foregroundStyle(Color.bizarreSuccess)
                }
            }
        }
        .padding(.vertical, 4)
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

    /// §6.8 — File a "return to vendor" request for an aged inventory item.
    /// Server creates a vendor-return record against the latest PO supplier;
    /// returns 409 when no eligible PO exists (UI surfaces server message).
    func requestVendorReturn(itemId: Int64, qty: Int) async throws -> VendorReturnRequestResponse {
        let body = VendorReturnRequestBody(qty: qty, source: "age_report")
        return try await post(
            "/api/v1/inventory/items/\(itemId)/vendor-return",
            body: body,
            as: VendorReturnRequestResponse.self
        )
    }
}

// MARK: - DTOs (§6.8 vendor-return)

public struct VendorReturnRequestBody: Encodable, Sendable {
    public let qty: Int
    public let source: String

    enum CodingKeys: String, CodingKey { case qty, source }
}

public struct VendorReturnRequestResponse: Decodable, Sendable {
    public let id: Int64
    public let status: String
    public let supplierId: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case supplierId = "supplier_id"
    }
}
#endif
