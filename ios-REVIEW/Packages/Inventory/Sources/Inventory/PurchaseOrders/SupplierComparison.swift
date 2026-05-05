#if canImport(UIKit)
import SwiftUI
import Charts
import Core
import DesignSystem
import Networking

// MARK: - §58 Supplier Comparison Side-by-Side
//
// Endpoint: GET /api/v1/suppliers/:id/analytics
// Returns per-supplier PO performance metrics: avg cost trend, lead time,
// on-time delivery %. When endpoint is absent (404/501), falls back to
// static data from the Supplier model (lead_time_days only).

// MARK: - Model

public struct SupplierAnalytics: Decodable, Sendable, Identifiable {
    public let supplierId: Int64
    public let supplierName: String
    /// Average cost per unit across the last 12 months in cents.
    public let avgCostCents: Int?
    /// Lead-time average in days (weighted by PO count).
    public let avgLeadTimeDays: Double
    /// On-time delivery rate 0.0–1.0.
    public let onTimeRate: Double?
    /// Total POs in the trailing 12 months.
    public let poCount: Int
    /// Cost trend: positive = rising, negative = falling.
    public let costTrendPct: Double?

    public var id: Int64 { supplierId }

    public var onTimePct: String {
        guard let r = onTimeRate else { return "—" }
        return String(format: "%.0f%%", r * 100)
    }

    public var costFormatted: String {
        guard let c = avgCostCents else { return "—" }
        return String(format: "$%.2f", Double(c) / 100.0)
    }

    public var leadTimeFormatted: String {
        String(format: "%.1fd", avgLeadTimeDays)
    }

    public var onTimeColor: Color {
        guard let r = onTimeRate else { return .bizarreOnSurfaceMuted }
        if r >= 0.9 { return .bizarreSuccess }
        if r >= 0.7 { return .bizarreWarning }
        return .bizarreError
    }

    enum CodingKeys: String, CodingKey {
        case supplierId = "supplier_id"
        case supplierName = "supplier_name"
        case avgCostCents = "avg_cost_cents"
        case avgLeadTimeDays = "avg_lead_time_days"
        case onTimeRate = "on_time_rate"
        case poCount = "po_count"
        case costTrendPct = "cost_trend_pct"
    }

    /// Fallback constructor when server endpoint is unavailable — uses Supplier static data.
    public static func fromSupplier(_ s: Supplier) -> SupplierAnalytics {
        SupplierAnalytics(
            supplierId: s.id,
            supplierName: s.name,
            avgCostCents: nil,
            avgLeadTimeDays: Double(s.leadTimeDays),
            onTimeRate: nil,
            poCount: 0,
            costTrendPct: nil
        )
    }

    public init(
        supplierId: Int64,
        supplierName: String,
        avgCostCents: Int?,
        avgLeadTimeDays: Double,
        onTimeRate: Double?,
        poCount: Int,
        costTrendPct: Double?
    ) {
        self.supplierId = supplierId
        self.supplierName = supplierName
        self.avgCostCents = avgCostCents
        self.avgLeadTimeDays = avgLeadTimeDays
        self.onTimeRate = onTimeRate
        self.poCount = poCount
        self.costTrendPct = costTrendPct
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// GET /api/v1/suppliers/:id/analytics
    /// 404/501 → nil (server may not have shipped this route yet).
    func supplierAnalytics(id: Int64) async throws -> SupplierAnalytics? {
        do {
            return try await get("/api/v1/suppliers/\(id)/analytics", as: SupplierAnalytics.self)
        } catch let err as URLError where err.code == .fileDoesNotExist {
            return nil
        } catch {
            // Treat HTTP 404/501 as missing — check status code via localizedDescription heuristic
            let msg = error.localizedDescription.lowercased()
            if msg.contains("404") || msg.contains("501") || msg.contains("not found") {
                return nil
            }
            throw error
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SupplierComparisonViewModel {
    public private(set) var rows: [SupplierAnalytics] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    /// Metric axis for the comparison chart.
    public enum CompareMetric: String, CaseIterable {
        case leadTime = "Lead Time"
        case onTimeRate = "On-Time %"
        case poCount = "PO Volume"
    }
    public var metric: CompareMetric = .onTimeRate

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let suppliers = try await api.listSuppliers()
            // Fetch analytics for each supplier concurrently, fall back to static data.
            rows = try await withThrowingTaskGroup(of: SupplierAnalytics.self) { group in
                for s in suppliers {
                    group.addTask { [api] in
                        if let analytics = try await api.supplierAnalytics(id: s.id) {
                            return analytics
                        }
                        return SupplierAnalytics.fromSupplier(s)
                    }
                }
                var result: [SupplierAnalytics] = []
                for try await item in group { result.append(item) }
                return result.sorted { $0.supplierName < $1.supplierName }
            }
        } catch {
            AppLog.ui.error("Supplier comparison load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Chart helpers

    public var chartEntries: [(name: String, value: Double)] {
        rows.compactMap { row in
            let v: Double?
            switch metric {
            case .leadTime:   v = row.avgLeadTimeDays
            case .onTimeRate: v = row.onTimeRate.map { $0 * 100 }
            case .poCount:    v = Double(row.poCount)
            }
            guard let value = v else { return nil }
            return (name: row.supplierName, value: value)
        }
        .sorted { $0.name < $1.name }
    }

    public var bestOnTimeSupplier: SupplierAnalytics? {
        rows.filter { $0.onTimeRate != nil }.max { ($0.onTimeRate ?? 0) < ($1.onTimeRate ?? 0) }
    }

    public var fastestLeadTime: SupplierAnalytics? {
        rows.min { $0.avgLeadTimeDays < $1.avgLeadTimeDays }
    }
}

// MARK: - View

public struct SupplierComparisonView: View {
    @State private var vm: SupplierComparisonViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: SupplierComparisonViewModel(api: api))
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
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Supplier Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { metricPicker }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    // MARK: iPad

    private var regularLayout: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    metricPickerInline
                    kpiRow
                    chartCard
                    comparisonGrid
                }
                .padding(BrandSpacing.lg)
            }
        }
        .navigationTitle("Supplier Comparison")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.rows.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = vm.errorMessage {
            errorState(msg)
        } else if vm.rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    kpiRow
                    chartCard
                    comparisonList
                }
                .padding(BrandSpacing.base)
            }
        }
    }

    // MARK: KPI Highlights

    private var kpiRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            if let best = vm.bestOnTimeSupplier {
                kpiCard(
                    icon: "checkmark.seal.fill",
                    label: "Best On-Time",
                    value: best.supplierName,
                    sub: best.onTimePct,
                    color: .bizarreSuccess
                )
            }
            if let fastest = vm.fastestLeadTime {
                kpiCard(
                    icon: "bolt.fill",
                    label: "Fastest Lead",
                    value: fastest.supplierName,
                    sub: fastest.leadTimeFormatted,
                    color: .bizarreOrange
                )
            }
        }
    }

    private func kpiCard(icon: String, label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .imageScale(.small)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
            Text(sub)
                .font(.brandMono(size: 13))
                .foregroundStyle(color)
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Comparison: \(vm.metric.rawValue)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            let entries = vm.chartEntries
            if entries.isEmpty {
                Text("No data for this metric")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(entries, id: \.name) { entry in
                        BarMark(
                            x: .value("Supplier", entry.name),
                            y: .value(vm.metric.rawValue, entry.value)
                        )
                        .foregroundStyle(.bizarreOrange.gradient)
                        .annotation(position: .top) {
                            Text(annotationLabel(entry.value))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Supplier comparison chart: \(vm.metric.rawValue)")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func annotationLabel(_ v: Double) -> String {
        switch vm.metric {
        case .leadTime:   return String(format: "%.0fd", v)
        case .onTimeRate: return String(format: "%.0f%%", v)
        case .poCount:    return "\(Int(v))"
        }
    }

    // MARK: Compact list (iPhone)

    private var comparisonList: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.rows) { row in
                supplierRow(row)
                Divider().padding(.leading, BrandSpacing.base)
            }
        }
        .background(Color.bizarreSurface1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func supplierRow(_ row: SupplierAnalytics) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(row.supplierName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
            HStack(spacing: BrandSpacing.base) {
                metricCell(icon: "clock", label: "Lead", value: row.leadTimeFormatted, color: .bizarreOnSurfaceMuted)
                metricCell(icon: "checkmark.circle", label: "On-time", value: row.onTimePct, color: row.onTimeColor)
                metricCell(icon: "cart", label: "POs", value: "\(row.poCount)", color: .bizarreOnSurfaceMuted)
                if let cost = row.avgCostCents {
                    let formatted = String(format: "$%.2f", Double(cost) / 100.0)
                    metricCell(icon: "dollarsign.circle", label: "Avg cost", value: formatted, color: .bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.supplierName), lead time \(row.leadTimeFormatted), on-time \(row.onTimePct)")
    }

    private func metricCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(value)
                .font(.brandMono(size: 13))
                .foregroundStyle(color)
        }
    }

    // MARK: iPad grid (side-by-side table)

    private var comparisonGrid: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("All Suppliers")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            if #available(iOS 16.0, *) {
                Table(vm.rows) {
                    TableColumn("Supplier") { r in
                        Text(r.supplierName)
                            .font(.brandBodyMedium())
                            .textSelection(.enabled)
                    }
                    TableColumn("Lead Time") { r in
                        Text(r.leadTimeFormatted)
                            .font(.brandMono(size: 13))
                            .monospacedDigit()
                    }
                    TableColumn("On-Time") { r in
                        Text(r.onTimePct)
                            .font(.brandMono(size: 13))
                            .foregroundStyle(r.onTimeColor)
                            .monospacedDigit()
                    }
                    TableColumn("Avg Cost") { r in
                        Text(r.avgCostCents.map { String(format: "$%.2f", Double($0) / 100.0) } ?? "—")
                            .font(.brandMono(size: 13))
                            .monospacedDigit()
                    }
                    TableColumn("POs") { r in
                        Text("\(r.poCount)")
                            .font(.brandMono(size: 13))
                            .monospacedDigit()
                    }
                }
                .tableStyle(.inset)
                .frame(minHeight: 200)
            } else {
                comparisonList
            }
        }
    }

    // MARK: Metric picker

    @ToolbarContentBuilder
    private var metricPicker: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(SupplierComparisonViewModel.CompareMetric.allCases, id: \.rawValue) { m in
                    Button(m.rawValue) { vm.metric = m }
                }
            } label: {
                Label("Metric: \(vm.metric.rawValue)", systemImage: "chart.bar")
            }
            .accessibilityLabel("Change chart metric, currently \(vm.metric.rawValue)")
        }
    }

    private var metricPickerInline: some View {
        Picker("Metric", selection: $vm.metric) {
            ForEach(SupplierComparisonViewModel.CompareMetric.allCases, id: \.rawValue) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 500)
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No suppliers to compare")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Add suppliers to see a side-by-side comparison.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
            Text("Couldn't load comparison")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
#endif
