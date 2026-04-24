import SwiftUI
import Core
import DesignSystem
import Networking

/// §22 iPad three-column audit log layout:
///   Column 1 (sidebar)  — AuditEntityFilterSidebar (entity-kind filter)
///   Column 2 (content)  — activity list with search + toolbar
///   Column 3 (detail)   — AuditMetadataDiffInspector for the selected entry
///
/// Entry point for the iPad layout. The caller (AuditLogListView) gates on
/// `!Platform.isCompact` before presenting this view.
///
/// Keyboard shortcuts (⌘F / ⌘R / ⌘E) are registered via AuditKeyboardShortcuts.
public struct AuditLogsThreeColumnView: View {

    @State private var vm: AuditLogViewModel
    @Binding var selectedEntry: AuditLogEntry?
    @State private var searchText = ""

    private let api: APIClient
    private let navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)?

    // MARK: Init

    public init(
        api: APIClient,
        selectedEntry: Binding<AuditLogEntry?>,
        navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)? = nil
    ) {
        self.api = api
        self._selectedEntry = selectedEntry
        self.navigateToEntity = navigateToEntity
        let repo = AuditLogRepository(api: api)
        _vm = State(wrappedValue: AuditLogViewModel(repository: repo))
    }

    // MARK: Body

    public var body: some View {
        NavigationSplitView {
            sidebarColumn
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 560)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .task { await vm.load() }
        .background(AuditKeyboardShortcuts(
            onFilter:  { vm.showFilterSheet = true },
            onRefresh: { Task { await vm.load() } },
            onExport:  { exportCSV() }
        ))
    }

    // MARK: - Column 1: Entity filter sidebar

    private var sidebarColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            AuditEntityFilterSidebar(
                selectedEntityKind: Binding(
                    get: { vm.filters.entityType },
                    set: { kind in
                        let updated = AuditLogFilters(
                            actorId:    vm.filters.actorId,
                            actions:    vm.filters.actions,
                            entityType: kind,
                            since:      vm.filters.since,
                            until:      vm.filters.until,
                            query:      vm.filters.query
                        )
                        vm.applyFilters(updated)
                    }
                )
            )
        }
        .navigationTitle("Entity")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Column 2: Activity list

    private var contentColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            listContent
        }
        .navigationTitle("Audit Logs")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search logs")
        .onChange(of: searchText) { _, q in vm.onQueryChange(q) }
        .toolbar { contentToolbar }
        .sheet(isPresented: $vm.showFilterSheet) { filterSheet }
    }

    // MARK: - Column 3: Metadata / diff detail

    private var detailColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if let entry = selectedEntry {
                AuditMetadataDiffInspector(
                    entry: entry,
                    navigateToEntity: navigateToEntity
                )
            } else {
                placeholderDetail
            }
        }
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        if vm.isLoading && vm.entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.entries.isEmpty {
            errorView(err)
        } else if vm.entries.isEmpty {
            emptyView
        } else {
            List(selection: Binding(
                get: { selectedEntry },
                set: { selectedEntry = $0 }
            )) {
                ForEach(vm.entries) { entry in
                    auditRow(entry)
                        .listRowBackground(Color.bizarreSurface1)
                        .onAppear { vm.loadMoreIfNeeded(entryId: entry.id) }
                }

                if vm.isLoadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if !vm.hasMore && !vm.entries.isEmpty {
                    Text("End of log")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder
    private func auditRow(_ entry: AuditLogEntry) -> some View {
        iPadAuditLogRow(entry: entry)
            .contentShape(Rectangle())
            .onTapGesture { selectedEntry = entry }
            .background(
                selectedEntry?.id == entry.id
                    ? Color.bizarreOrangeContainer.opacity(0.2)
                    : Color.clear
            )
            #if canImport(UIKit)
            .hoverEffect(.highlight)
            #endif
            .contextMenu {
                AuditContextMenu(
                    entry: entry,
                    onFilterByActor: { actorId in
                        let updated = AuditLogFilters(
                            actorId:    actorId,
                            actions:    vm.filters.actions,
                            entityType: vm.filters.entityType,
                            since:      vm.filters.since,
                            until:      vm.filters.until,
                            query:      vm.filters.query
                        )
                        vm.applyFilters(updated)
                    },
                    onOpenEntity: navigateToEntity
                )
            }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showFilterSheet = true
            } label: {
                Image(systemName: vm.filters.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .tint(vm.filters.isActive ? .bizarreOrange : .primary)
            .accessibilityLabel(vm.filters.isActive ? "Filters active" : "Filter logs")
            .accessibilityIdentifier("ipad.auditlog.filter.button")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { Task { await vm.load() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh audit logs")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { exportCSV() } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Export audit logs as CSV")
        }
    }

    // MARK: - Filter sheet

    private var filterSheet: some View {
        AuditLogFilterSheet(
            filters: Binding(
                get: { vm.filters },
                set: { _ in }
            ),
            selectedRange: Binding(
                get: { vm.selectedRange },
                set: { _ in }
            ),
            onApply: { vm.applyFilters($0) },
            onClear: { vm.clearFilters() }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - State views

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Could not load audit logs")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(vm.filters.isActive ? "No matching logs" : "No audit logs yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if vm.filters.isActive {
                Button("Clear Filters") { vm.clearFilters() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholderDetail: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select an entry")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap any audit log entry to inspect its metadata and diff.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Export

    private func exportCSV() {
        let header = "id,created_at,actor,action,entity_kind,entity_id\n"
        let isoFormatter = ISO8601DateFormatter()
        let rows = vm.entries.map { e in
            let eid = e.entityId.map(String.init) ?? ""
            return "\(e.id),\(isoFormatter.string(from: e.createdAt)),\"\(e.actorName)\",\(e.action),\(e.entityKind),\(eid)"
        }.joined(separator: "\n")
        let csv = header + rows

        #if canImport(UIKit)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit_log_\(Int(Date().timeIntervalSince1970)).csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        // Surface the share sheet — caller receives via UIActivityViewController
        NotificationCenter.default.post(
            name: .auditLogExportReady,
            object: tempURL
        )
        #endif
    }
}

// MARK: - Notification name for export

public extension Notification.Name {
    /// Posted with a `URL` object pointing to the temporary CSV file.
    static let auditLogExportReady = Notification.Name("com.bizarrecrm.auditlog.exportReady")
}

// MARK: - iPadAuditLogRow

/// Thin row view used inside the three-column list. Distinct name from the private
/// `AuditLogRow` in `AuditLogListView.swift` to avoid a same-module redeclaration.
private struct iPadAuditLogRow: View {
    let entry: AuditLogEntry

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            ActorAvatar(name: entry.actorName, diameter: 36)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(entry.actorName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(relativeTime)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(entry.action)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOrange)
                    Text("·")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(entry.entityKind)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            if entry.metadata != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityIdentifier("ipad.auditlog.row.\(entry.id)")
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.createdAt, relativeTo: Date())
    }

    private var a11yLabel: String {
        let entitySuffix = entry.entityId.map { " #\($0)" } ?? ""
        return "\(entry.actorName) performed \(entry.action) on \(entry.entityKind)\(entitySuffix) \(relativeTime)"
    }
}
