import SwiftUI
import Core
import DesignSystem
import Networking

/// §50.1 Audit Logs list — admin-only, iPhone NavigationStack / iPad three-column split.
///
/// Wiring snippet for `project.yml` / `RootView.swift`:
/// ```swift
/// import AuditLogs
/// // In MoreMenuView or admin-settings navigation:
/// AuditLogListView(api: api)
/// ```
public struct AuditLogListView: View {

    @State private var vm: AuditLogViewModel
    @State private var selectedEntry: AuditLogEntry?
    @State private var searchText = ""
    // §50.3 Export sheet
    @State private var showExportSheet = false

    /// Called with (entityType, entityId) when the user navigates to an affected entity.
    private let navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)?

    private let api: APIClient

    public init(
        api: APIClient,
        navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)? = nil
    ) {
        self.api = api
        self.navigateToEntity = navigateToEntity
        let repo = AuditLogRepository(api: api)
        _vm = State(wrappedValue: AuditLogViewModel(repository: repo))
    }

    public var body: some View {
        Group {
            if !vm.hasAccess {
                accessDeniedView
            } else if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task { await vm.load() }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                listContent
            }
            .navigationTitle("Audit Logs")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .searchable(text: $searchText, prompt: "Search logs")
            .onChange(of: searchText) { _, q in vm.onQueryChange(q) }
            .toolbar { toolbarItems }
            .sheet(isPresented: $vm.showFilterSheet) { filterSheet }
            .navigationDestination(for: AuditLogEntry.self) { entry in
                AuditLogDetailView(entry: entry, navigateToEntity: navigateToEntity)
            }
            .safeAreaInset(edge: .top) { filterChipBar }
            // §50.3 Export sheet
            .sheet(isPresented: $showExportSheet) {
                AuditLogExportSheet(entries: vm.entries)
            }
        }
    }

    // MARK: - iPad layout — filter sidebar + list + diff triple column

    private var iPadLayout: some View {
        NavigationSplitView {
            // Column 1: Filters
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                inlineFilterPanel
            }
            .navigationTitle("Filters")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
        } content: {
            // Column 2: List
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
            .toolbar { toolbarItems }
            .navigationSplitViewColumnWidth(min: 340, ideal: 420, max: 560)
            // §50.3 Export sheet
            .sheet(isPresented: $showExportSheet) {
                AuditLogExportSheet(entries: vm.entries)
            }
        } detail: {
            // Column 3: Diff detail
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if let entry = selectedEntry {
                    AuditLogDetailView(entry: entry, navigateToEntity: navigateToEntity)
                } else {
                    placeholderDetail
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
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
                    Group {
                        if Platform.isCompact {
                            NavigationLink(value: entry) {
                                AuditLogRow(entry: entry)
                            }
                        } else {
                            AuditLogRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedEntry = entry }
                                .background(selectedEntry?.id == entry.id ? Color.bizarreOrangeContainer.opacity(0.2) : Color.clear)
                                #if canImport(UIKit)
                                .hoverEffect(.highlight)
                                #endif
                                .contextMenu {
                                    Button {
                                        selectedEntry = entry
                                    } label: {
                                        Label("View Details", systemImage: "doc.text.magnifyingglass")
                                    }
                                    Button {
                                        if let eid = entry.entityId {
                                            navigateToEntity?(entry.entityKind, String(eid))
                                        }
                                    } label: {
                                        Label("Go to \(entry.entityKind.capitalized)", systemImage: "arrow.right.circle")
                                    }
                                }
                        }
                    }
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

    // MARK: - Filter chip bar (iPhone only, §50.2)

    @ViewBuilder
    private var filterChipBar: some View {
        if vm.filters.isActive || vm.selectedRange != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    if let range = vm.selectedRange {
                        FilterChip(label: range.rawValue) { vm.applyDateRange(nil) }
                    }
                    if let et = vm.filters.entityType {
                        FilterChip(label: et.capitalized) {
                            vm.applyFilters(AuditLogFilters(
                                actorId: vm.filters.actorId,
                                actions: vm.filters.actions,
                                entityType: nil,
                                since: vm.filters.since,
                                until: vm.filters.until,
                                query: vm.filters.query
                            ))
                        }
                    }
                    ForEach(vm.filters.actions, id: \.self) { action in
                        FilterChip(label: action) {
                            var updated = vm.filters
                            updated.actions.removeAll { $0 == action }
                            vm.applyFilters(updated)
                        }
                    }
                    if vm.filters.isActive {
                        Button("Clear") { vm.clearFilters() }
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Inline filter panel (iPad column 1)

    private var inlineFilterPanel: some View {
        AuditLogFilterSheet(
            filters: Binding(
                get: { vm.filters },
                set: { _ in }  // managed by vm.applyFilters
            ),
            selectedRange: Binding(
                get: { vm.selectedRange },
                set: { _ in }
            ),
            onApply: { vm.applyFilters($0) },
            onClear: { vm.clearFilters() }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showFilterSheet = true
            } label: {
                Image(systemName: vm.filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .tint(vm.filters.isActive ? .bizarreOrange : .primary)
            .accessibilityLabel(vm.filters.isActive ? "Filters active, tap to edit" : "Filter logs")
            .accessibilityIdentifier("auditlog.filter.button")
        }
        // §50.3 Export CSV — wires to AuditLogExportSheet
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showExportSheet = true
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .disabled(vm.entries.isEmpty)
            .accessibilityLabel("Export audit log as CSV")
            .accessibilityIdentifier("auditlog.export.button")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { Task { await vm.load() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("R", modifiers: .command)
            .accessibilityLabel("Refresh audit logs")
        }
    }

    // MARK: - Filter sheet (iPhone)

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

    // MARK: - States

    private var accessDeniedView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Access Denied")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Audit Logs require the admin or owner role.\nContact your account owner for access.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Access denied. Audit Logs require admin or owner role.")
    }

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AuditLogRow

/// Single list row for an audit log entry. §50.1 + §50.6 accessibility.
private struct AuditLogRow: View {
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
        .accessibilityIdentifier("auditlog.row.\(entry.id)")
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

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(.brandLabelSmall())
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .accessibilityLabel("Remove \(label) filter")
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .brandGlass(.regular, in: Capsule(), tint: .bizarreOrange)
        .foregroundStyle(.bizarreOnSurface)
    }
}

// AuditLogEntry already conforms to Hashable (declared in AuditLogEntry.swift).
