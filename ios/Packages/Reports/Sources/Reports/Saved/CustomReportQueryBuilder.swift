import SwiftUI
import Core
import Foundation
import DesignSystem

// MARK: - §15.8 Custom Report Query Builder
//
// Pick series + bucket + range; save as favorite per user.
// Visual query builder (no SQL): entity + filters + group + measure + timeframe.

// MARK: - CustomReportQuery

public struct CustomReportQuery: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    /// Entity to query: "sales", "tickets", "inventory", "employees".
    public var entity: ReportEntity
    /// Measure to aggregate.
    public var measure: ReportMeasure
    /// Group-by bucket.
    public var groupBy: ReportGroupBy
    /// Preset or custom date range.
    public var dateRange: DateRangePreset
    public var customFrom: String
    public var customTo: String
    /// Active filters (field → value pairs).
    public var filters: [ReportFilter]
    public var isFavorite: Bool
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String = "Custom Report",
        entity: ReportEntity = .sales,
        measure: ReportMeasure = .revenue,
        groupBy: ReportGroupBy = .day,
        dateRange: DateRangePreset = .thirtyDays,
        customFrom: String = "",
        customTo: String = "",
        filters: [ReportFilter] = [],
        isFavorite: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.entity = entity
        self.measure = measure
        self.groupBy = groupBy
        self.dateRange = dateRange
        self.customFrom = customFrom
        self.customTo = customTo
        self.filters = filters
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}

// MARK: - ReportEntity

public enum ReportEntity: String, Codable, Sendable, CaseIterable, Identifiable {
    case sales      = "sales"
    case tickets    = "tickets"
    case inventory  = "inventory"
    case employees  = "employees"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sales:      return "Sales"
        case .tickets:    return "Tickets"
        case .inventory:  return "Inventory"
        case .employees:  return "Employees"
        }
    }

    public var systemImage: String {
        switch self {
        case .sales:      return "dollarsign.circle"
        case .tickets:    return "wrench.and.screwdriver"
        case .inventory:  return "shippingbox"
        case .employees:  return "person.3"
        }
    }

    public var availableMeasures: [ReportMeasure] {
        switch self {
        case .sales:      return [.revenue, .invoiceCount, .uniqueCustomers, .avgTicketValue]
        case .tickets:    return [.ticketCount, .closeRate, .avgResolutionDays, .revenue]
        case .inventory:  return [.stockValue, .turnoverRate, .lowStockCount]
        case .employees:  return [.revenue, .ticketCount, .hoursWorked, .commissions]
        }
    }
}

// MARK: - ReportMeasure

public enum ReportMeasure: String, Codable, Sendable, CaseIterable, Identifiable {
    case revenue         = "revenue"
    case invoiceCount    = "invoice_count"
    case uniqueCustomers = "unique_customers"
    case avgTicketValue  = "avg_ticket_value"
    case ticketCount     = "ticket_count"
    case closeRate       = "close_rate"
    case avgResolutionDays = "avg_resolution_days"
    case stockValue      = "stock_value"
    case turnoverRate    = "turnover_rate"
    case lowStockCount   = "low_stock_count"
    case hoursWorked     = "hours_worked"
    case commissions     = "commissions"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .revenue:         return "Revenue"
        case .invoiceCount:    return "Invoice Count"
        case .uniqueCustomers: return "Unique Customers"
        case .avgTicketValue:  return "Avg Ticket Value"
        case .ticketCount:     return "Ticket Count"
        case .closeRate:       return "Close Rate"
        case .avgResolutionDays: return "Avg Resolution Days"
        case .stockValue:      return "Stock Value"
        case .turnoverRate:    return "Turnover Rate"
        case .lowStockCount:   return "Low Stock Count"
        case .hoursWorked:     return "Hours Worked"
        case .commissions:     return "Commissions"
        }
    }
}

// MARK: - ReportGroupBy

public enum ReportGroupBy: String, Codable, Sendable, CaseIterable, Identifiable {
    case day      = "day"
    case week     = "week"
    case month    = "month"
    case category = "category"
    case employee = "employee"
    case status   = "status"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .day:      return "Day"
        case .week:     return "Week"
        case .month:    return "Month"
        case .category: return "Category"
        case .employee: return "Employee"
        case .status:   return "Status"
        }
    }
}

// MARK: - ReportFilter

public struct ReportFilter: Codable, Sendable, Identifiable {
    public let id: String
    public var field: String
    public var value: String
    public var displayLabel: String

    public init(field: String, value: String, displayLabel: String) {
        self.id = UUID().uuidString
        self.field = field
        self.value = value
        self.displayLabel = displayLabel
    }
}

// MARK: - CustomReportStore

public final class CustomReportStore: @unchecked Sendable {
    public static let shared = CustomReportStore()

    private let userDefaultsKey = "com.bizarrecrm.customReportQueries"
    private var queries: [CustomReportQuery] = []

    public init() {
        load()
    }

    public func allQueries() -> [CustomReportQuery] { queries }
    public func favorites() -> [CustomReportQuery] { queries.filter(\.isFavorite) }

    public func save(_ query: CustomReportQuery) {
        if let idx = queries.firstIndex(where: { $0.id == query.id }) {
            queries[idx] = query
        } else {
            queries.append(query)
        }
        persist()
    }

    public func delete(id: String) {
        queries.removeAll { $0.id == id }
        persist()
    }

    public func toggleFavorite(id: String) {
        guard let idx = queries.firstIndex(where: { $0.id == id }) else { return }
        queries[idx].isFavorite.toggle()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([CustomReportQuery].self, from: data)
        else { return }
        queries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(queries) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}

// MARK: - CustomReportQueryBuilderView (§15.8)

public struct CustomReportQueryBuilderView: View {
    @State private var query: CustomReportQuery
    private let store: CustomReportStore
    private let onSave: (CustomReportQuery) -> Void
    private let onRun: (CustomReportQuery) -> Void

    public init(
        query: CustomReportQuery = CustomReportQuery(),
        store: CustomReportStore = .shared,
        onSave: @escaping (CustomReportQuery) -> Void = { _ in },
        onRun: @escaping (CustomReportQuery) -> Void = { _ in }
    ) {
        _query = State(wrappedValue: query)
        self.store = store
        self.onSave = onSave
        self.onRun = onRun
    }

    public var body: some View {
        NavigationStack {
            Form {
                nameSection
                entitySection
                measureSection
                groupBySection
                dateRangeSection
                filtersSection
                actionsSection
            }
            .navigationTitle("Build Report")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveQuery() }
                        .accessibilityLabel("Save custom report")
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Report Name") {
            TextField("Name", text: $query.name)
                .accessibilityLabel("Report name")
        }
    }

    private var entitySection: some View {
        Section("Entity") {
            Picker("Entity", selection: $query.entity) {
                ForEach(ReportEntity.allCases) { entity in
                    Label(entity.displayName, systemImage: entity.systemImage)
                        .tag(entity)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select entity to report on")
            .onChange(of: query.entity) { _, newEntity in
                // Reset measure if not available for new entity
                if !newEntity.availableMeasures.contains(query.measure) {
                    query.measure = newEntity.availableMeasures.first ?? .revenue
                }
            }
        }
    }

    private var measureSection: some View {
        Section("Measure") {
            Picker("Measure", selection: $query.measure) {
                ForEach(query.entity.availableMeasures) { measure in
                    Text(measure.displayName).tag(measure)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select measure to aggregate")
        }
    }

    private var groupBySection: some View {
        Section("Group By") {
            Picker("Group By", selection: $query.groupBy) {
                ForEach(ReportGroupBy.allCases) { bucket in
                    Text(bucket.displayName).tag(bucket)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Select grouping bucket")
        }
    }

    private var dateRangeSection: some View {
        Section("Time Frame") {
            Picker("Preset", selection: $query.dateRange) {
                ForEach(DateRangePreset.allCases) { preset in
                    Text(preset.displayLabel).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Select date range preset")
        }
    }

    private var filtersSection: some View {
        Section("Filters") {
            if query.filters.isEmpty {
                Text("No filters applied")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No filters")
            } else {
                ForEach(query.filters) { filter in
                    HStack {
                        Text(filter.displayLabel)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Button {
                            query.filters.removeAll { $0.id == filter.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityLabel("Remove filter: \(filter.displayLabel)")
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            // Favorite toggle
            Toggle(isOn: $query.isFavorite) {
                Label("Save as Favorite", systemImage: "star.fill")
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Save as favorite report")

            // Run button
            Button {
                onRun(query)
            } label: {
                Label("Run Report", systemImage: "play.fill")
                    .foregroundStyle(Color.bizarreOrange)
            }
            .accessibilityLabel("Run this report")
        }
    }

    // MARK: - Actions

    private func saveQuery() {
        store.save(query)
        onSave(query)
    }
}

// MARK: - CustomReportListView (favorites + all)

public struct CustomReportListView: View {
    @State private var queries: [CustomReportQuery] = []
    @State private var showBuilder = false
    @State private var editingQuery: CustomReportQuery?

    private let store: CustomReportStore
    private let onRun: (CustomReportQuery) -> Void

    public init(
        store: CustomReportStore = .shared,
        onRun: @escaping (CustomReportQuery) -> Void = { _ in }
    ) {
        self.store = store
        self.onRun = onRun
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .onAppear { refresh() }
        .sheet(isPresented: $showBuilder) {
            CustomReportQueryBuilderView(store: store, onSave: { _ in refresh(); showBuilder = false })
        }
        .sheet(item: $editingQuery) { q in
            CustomReportQueryBuilderView(query: q, store: store, onSave: { _ in refresh(); editingQuery = nil })
        }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        NavigationStack {
            listContent
                .navigationTitle("Custom Reports")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showBuilder = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create new custom report")
                    }
                }
        }
    }

    private var ipadLayout: some View {
        NavigationSplitView {
            listContent
                .navigationTitle("Custom Reports")
        } detail: {
            Text("Select a report")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBuilder = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create new custom report")
            }
        }
    }

    private var listContent: some View {
        List {
            if !queries.filter(\.isFavorite).isEmpty {
                Section("Favorites") {
                    ForEach(queries.filter(\.isFavorite)) { q in
                        queryRow(q)
                    }
                }
            }

            let all = queries.filter { !$0.isFavorite }
            if !all.isEmpty {
                Section("All Reports") {
                    ForEach(all) { q in
                        queryRow(q)
                    }
                    .onDelete { indexSet in
                        indexSet.map { all[$0].id }.forEach { store.delete(id: $0) }
                        refresh()
                    }
                }
            }

            if queries.isEmpty {
                ContentUnavailableView(
                    "No custom reports yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Tap + to build your first custom report")
                )
                .accessibilityLabel("No custom reports. Tap plus to create one.")
            }
        }
    }

    private func queryRow(_ q: CustomReportQuery) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BrandSpacing.xs) {
                    if q.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.bizarreOrange)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    Text(q.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                Text("\(q.entity.displayName) · \(q.measure.displayName) · \(q.groupBy.displayName)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button {
                onRun(q)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Run report: \(q.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture { editingQuery = q }
        .contextMenu {
            Button {
                store.toggleFavorite(id: q.id)
                refresh()
            } label: {
                Label(q.isFavorite ? "Remove Favorite" : "Add Favorite",
                      systemImage: q.isFavorite ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                store.delete(id: q.id)
                refresh()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(q.name), \(q.entity.displayName), \(q.measure.displayName)")
        .accessibilityHint("Tap to edit, swipe or use context menu to delete")
    }

    private func refresh() {
        queries = store.allQueries().sorted { $0.createdAt > $1.createdAt }
    }
}
