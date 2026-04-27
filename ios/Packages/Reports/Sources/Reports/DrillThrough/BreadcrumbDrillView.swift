import SwiftUI
import DesignSystem

// MARK: - §15.9 Breadcrumb Drill Trail + Chart Export + Save as Dashboard Tile
//
// Breadcrumb drill: tap chart segment → filtered records list;
// trail "Total revenue → October → Services → iPhone repair"; each crumb tappable.
// Context panel: filters narrowed-by-drill (left), records list (right).
// Export at any level: share current filtered view as PDF / CSV.
// "Save this drill as dashboard tile" saves with query.

// MARK: - DrillBreadcrumb

public struct DrillBreadcrumb: Identifiable, Sendable {
    public let id: String
    /// Human-readable label for this crumb (e.g. "October", "Services").
    public let label: String
    /// Metric context (matches DrillThroughContext.metric).
    public let metric: String
    /// Date or value filter at this level.
    public let filter: String

    public init(id: String = UUID().uuidString, label: String, metric: String, filter: String) {
        self.id = id
        self.label = label
        self.metric = metric
        self.filter = filter
    }
}

// MARK: - DrillThroughState

@Observable
@MainActor
public final class DrillThroughState {
    public var breadcrumbs: [DrillBreadcrumb] = []
    public var records: [DrillThroughRecord] = []
    public var isLoading = false
    public var errorMessage: String?

    private let repository: ReportsRepository

    public init(repository: ReportsRepository) {
        self.repository = repository
    }

    /// Push a new level into the trail and load records.
    public func drillInto(crumb: DrillBreadcrumb) async {
        breadcrumbs.append(crumb)
        await loadRecords(metric: crumb.metric, date: crumb.filter)
    }

    /// Pop back to a specific crumb index and reload from that level.
    public func popTo(index: Int) async {
        guard index >= 0 && index < breadcrumbs.count else { return }
        breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        let crumb = breadcrumbs[index]
        await loadRecords(metric: crumb.metric, date: crumb.filter)
    }

    /// Pop one level up.
    public func popBack() async {
        guard breadcrumbs.count > 1 else { return }
        breadcrumbs.removeLast()
        let crumb = breadcrumbs[breadcrumbs.count - 1]
        await loadRecords(metric: crumb.metric, date: crumb.filter)
    }

    /// Reset to empty (root) state.
    public func reset() {
        breadcrumbs = []
        records = []
    }

    private func loadRecords(metric: String, date: String) async {
        isLoading = true
        errorMessage = nil
        do {
            records = try await repository.getDrillThrough(metric: metric, date: date)
        } catch {
            errorMessage = error.localizedDescription
            records = []
        }
        isLoading = false
    }
}

// MARK: - BreadcrumbTrailView

public struct BreadcrumbTrailView: View {
    public let breadcrumbs: [DrillBreadcrumb]
    public let onTapCrumb: (Int) -> Void

    public init(breadcrumbs: [DrillBreadcrumb], onTapCrumb: @escaping (Int) -> Void) {
        self.breadcrumbs = breadcrumbs
        self.onTapCrumb = onTapCrumb
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                // Root crumb
                Button {
                    onTapCrumb(-1)
                } label: {
                    Text("All")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xs)
                }
                .accessibilityLabel("Back to all data")

                ForEach(Array(breadcrumbs.enumerated()), id: \.1.id) { idx, crumb in
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .imageScale(.small)
                        .accessibilityHidden(true)

                    let isLast = idx == breadcrumbs.count - 1
                    Button {
                        onTapCrumb(idx)
                    } label: {
                        Text(crumb.label)
                            .font(isLast ? .brandLabelLarge() : .brandBodyMedium())
                            .foregroundStyle(isLast ? .bizarreOnSurface : .bizarreOrange)
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xs)
                    }
                    .disabled(isLast)
                    .accessibilityLabel(isLast ? "Current level: \(crumb.label)" : "Drill back to \(crumb.label)")
                }
            }
        }
        .brandGlass(.clear, in: Capsule())
        .accessibilityLabel("Drill path: \(["All"] + breadcrumbs.map(\.label).joined(separator: " → "))")
    }
}

// MARK: - BreadcrumbDrillView (§15.9)
//
// iPhone: full-screen list with breadcrumb trail header.
// iPad: NavigationSplitView — filters narrowed-by-drill (left), records list (right).

public struct BreadcrumbDrillView: View {
    @State private var drillState: DrillThroughState
    private let onTapRecord: (Int64) -> Void
    private let onSaveAsDashboardTile: (DrillBreadcrumb) -> Void

    @State private var showExportSheet = false
    @State private var exportURL: URL?

    public init(
        repository: ReportsRepository,
        initialCrumb: DrillBreadcrumb,
        onTapRecord: @escaping (Int64) -> Void = { _ in },
        onSaveAsDashboardTile: @escaping (DrillBreadcrumb) -> Void = { _ in }
    ) {
        _drillState = State(wrappedValue: DrillThroughState(repository: repository))
        self.onTapRecord = onTapRecord
        self.onSaveAsDashboardTile = onSaveAsDashboardTile
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareLink(item: url)
            }
        }
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb trail
                if !drillState.breadcrumbs.isEmpty {
                    BreadcrumbTrailView(
                        breadcrumbs: drillState.breadcrumbs
                    ) { idx in
                        Task {
                            if idx < 0 { drillState.reset() }
                            else { await drillState.popTo(index: idx) }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    Divider()
                }
                recordsList
            }
            .navigationTitle(drillState.breadcrumbs.last?.label ?? "Drill Through")
            .toolbar { toolbarContent }
        }
    }

    private var ipadLayout: some View {
        NavigationSplitView {
            // Left: filter/context panel
            filterPanel
                .navigationTitle("Filters")
        } detail: {
            // Right: records list
            VStack(spacing: 0) {
                if !drillState.breadcrumbs.isEmpty {
                    BreadcrumbTrailView(
                        breadcrumbs: drillState.breadcrumbs
                    ) { idx in
                        Task {
                            if idx < 0 { drillState.reset() }
                            else { await drillState.popTo(index: idx) }
                        }
                    }
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    Divider()
                }
                recordsList
            }
            .navigationTitle(drillState.breadcrumbs.last?.label ?? "Drill Through")
            .toolbar { toolbarContent }
        }
    }

    // MARK: - Filter Panel (iPad left column)

    private var filterPanel: some View {
        List {
            Section("Active Filters") {
                if drillState.breadcrumbs.isEmpty {
                    Text("No filters applied")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("No active filters")
                } else {
                    ForEach(drillState.breadcrumbs) { crumb in
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(crumb.metric.capitalized)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                Text(crumb.label)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Filter: \(crumb.metric) = \(crumb.label)")
                    }
                }
            }

            Section {
                Button {
                    drillState.reset()
                } label: {
                    Label("Clear All Filters", systemImage: "xmark.circle")
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Clear all drill-through filters")
                .disabled(drillState.breadcrumbs.isEmpty)
            }
        }
    }

    // MARK: - Records List

    private var recordsList: some View {
        Group {
            if drillState.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading drill-through records")
            } else if let err = drillState.errorMessage {
                ContentUnavailableView(
                    "Couldn't load records",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
                .accessibilityLabel("Error: \(err)")
            } else if drillState.records.isEmpty {
                ContentUnavailableView(
                    "No records",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No data matches the current drill filters")
                )
                .accessibilityLabel("No records match current filters")
            } else {
                List(drillState.records) { record in
                    Button {
                        onTapRecord(record.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.label)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let detail = record.detail {
                                    Text(detail)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }
                            Spacer()
                            if let amount = record.amountDollars {
                                Text(amount, format: .currency(code: "USD"))
                                    .font(.brandLabelLarge()).monospacedDigit()
                                    .foregroundStyle(.bizarreOnSurface)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(record.label)\(record.detail != nil ? ", \(record.detail!)" : "")\(record.amountDollars != nil ? String(format: ", $%.2f", record.amountDollars!) : "")"
                    )
                    .accessibilityHint("Tap to open record")
                    .hoverEffect(.highlight)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Text("\(drillState.records.count) records")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("\(drillState.records.count) records")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    Task { await exportDrillCSV() }
                } label: {
                    Label("Export CSV", systemImage: "doc.plaintext")
                }
                .accessibilityLabel("Export filtered records as CSV")

                if let crumb = drillState.breadcrumbs.last {
                    Button {
                        onSaveAsDashboardTile(crumb)
                    } label: {
                        Label("Save as Dashboard Tile", systemImage: "square.grid.2x2.fill")
                    }
                    .accessibilityLabel("Save this drill as a dashboard tile")
                }

                if drillState.breadcrumbs.count > 0 {
                    Divider()
                    Button(role: .destructive) {
                        drillState.reset()
                    } label: {
                        Label("Clear Filters", systemImage: "xmark.circle")
                    }
                    .accessibilityLabel("Clear all drill filters")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Drill actions")
        }
    }

    // MARK: - Export CSV

    private func exportDrillCSV() async {
        guard !drillState.records.isEmpty else { return }
        let header = "ID,Label,Detail,Amount\n"
        let rows = drillState.records.map { r in
            let amount = r.amountDollars.map { String(format: "%.2f", $0) } ?? ""
            return "\(r.id),\"\(r.label)\",\"\(r.detail ?? "")\",\(amount)"
        }.joined(separator: "\n")
        let csv = header + rows
        let fileName = "drill_export_\(Date().timeIntervalSince1970).csv"
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? csv.write(to: tmpURL, atomically: true, encoding: .utf8)
        exportURL = tmpURL
        showExportSheet = true
    }
}

// MARK: - ChartImageExporter (§15.9 Export chart as PNG/CSV)
//
// Converts a SwiftUI View's chart into a PNG image for sharing.

@MainActor
public struct ChartImageExporter {
    /// Render the given view as a PNG at the specified size.
    public static func exportAsPNG<V: View>(view: V, size: CGSize) async -> URL? {
        let renderer = ImageRenderer(content:
            view.frame(width: size.width, height: size.height)
        )
        renderer.scale = 3.0
        guard let image = renderer.uiImage,
              let data = image.pngData() else { return nil }
        let fileName = "chart_export_\(Date().timeIntervalSince1970).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)
        return url
    }

    /// Compose a CSV from an array of (label, value) pairs.
    public static func exportAsCSV(entries: [(label: String, value: Double)],
                                    title: String = "Chart Data") -> URL? {
        let header = "Label,Value\n"
        let rows = entries.map { "\"\($0.label)\",\($0.value)" }.joined(separator: "\n")
        let csv = header + rows
        let fileName = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - SaveDrillAsDashboardTile (§15.9)

public struct SavedDrillTile: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let metric: String
    public let filter: String
    public let savedAt: Date

    public init(title: String, metric: String, filter: String) {
        self.id = UUID().uuidString
        self.title = title
        self.metric = metric
        self.filter = filter
        self.savedAt = Date()
    }
}

public final class SavedDrillTileStore: @unchecked Sendable {
    public static let shared = SavedDrillTileStore()
    private let key = "com.bizarrecrm.savedDrillTiles"
    private var tiles: [SavedDrillTile] = []

    public init() { load() }

    public func allTiles() -> [SavedDrillTile] { tiles }

    public func save(crumb: DrillBreadcrumb) {
        let tile = SavedDrillTile(title: crumb.label, metric: crumb.metric, filter: crumb.filter)
        tiles.append(tile)
        persist()
    }

    public func delete(id: String) {
        tiles.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedDrillTile].self, from: data)
        else { return }
        tiles = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tiles) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
