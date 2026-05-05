import SwiftUI
import DesignSystem
import Core

// MARK: - ConflictListView

/// Lists pending sync conflicts grouped by entity kind.
/// Supports iPad (NavigationSplitView) and iPhone (NavigationStack).
///
/// Entry point: Settings → Sync → Conflict Resolution
public struct ConflictListView: View {
    @State private var viewModel: ConflictResolutionViewModel
    @State private var selectedConflict: ConflictItem?

    public init(repository: ConflictResolutionRepositoryProtocol) {
        _viewModel = State(initialValue: ConflictResolutionViewModel(repository: repository))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task { await viewModel.loadConflicts() }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") { Task { await viewModel.acknowledgeOutcome() } }
        } message: {
            if case .error(let msg) = viewModel.phase { Text(msg) }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            conflictListContent
                .navigationTitle("Sync Conflicts")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { filterToolbarItems }
                .navigationDestination(item: $selectedConflict) { conflict in
                    ConflictDiffView(initialConflict: conflict, viewModel: viewModel)
                }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            conflictListContent
                .navigationTitle("Sync Conflicts")
                .toolbar { filterToolbarItems }
        } detail: {
            if let conflict = selectedConflict {
                ConflictDiffView(initialConflict: conflict, viewModel: viewModel)
            } else {
                emptyDetailPlaceholder
            }
        }
    }

    private var emptyDetailPlaceholder: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "arrow.left.and.right.square")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Select a conflict to review")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No conflict selected. Select a conflict from the list to review.")
    }

    // MARK: - List content

    @ViewBuilder
    private var conflictListContent: some View {
        if viewModel.phase == .loading && viewModel.conflicts.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading sync conflicts")
        } else if viewModel.conflicts.isEmpty {
            emptyState
        } else {
            conflictList
        }
    }

    private var conflictList: some View {
        List(selection: Binding(
            get: { selectedConflict?.id },
            set: { newId in
                if let item = viewModel.conflicts.first(where: { $0.id == newId }) {
                    selectedConflict = item
                    Task { await viewModel.selectConflict(item) }
                }
            }
        )) {
            ForEach(viewModel.conflictsByEntityKind, id: \.key) { group in
                Section {
                    ForEach(group.items) { conflict in
                        conflictRow(conflict)
                    }
                } header: {
                    HStack {
                        Text(group.key.capitalized)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text("\(group.items.count)")
                            .font(.brandMono(size: 11))
                            .foregroundStyle(.bizarreTeal)
                    }
                }
            }

            // Pagination trigger — visible when more pages exist.
            if viewModel.currentPage < viewModel.totalPages {
                HStack {
                    Spacer()
                    if viewModel.isLoadingNextPage {
                        ProgressView()
                    } else {
                        Button("Load More") {
                            Task { await viewModel.loadNextPage() }
                        }
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreTeal)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .padding(.vertical, BrandSpacing.sm)
                .accessibilityLabel("Load more conflicts")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .refreshable { await viewModel.refresh() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Empty state

    private func conflictRow(_ conflict: ConflictItem) -> some View {
        ConflictRowView(conflict: conflict)
            .tag(conflict.id)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedConflict = conflict
                Task { await viewModel.selectConflict(conflict) }
            }
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
            .contextMenu {
                Button("View Details") {
                    selectedConflict = conflict
                    Task { await viewModel.selectConflict(conflict) }
                }
            }
            .accessibilityLabel(conflictA11yLabel(conflict))
            .accessibilityHint("Double-tap to review and resolve this conflict")
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No pending conflicts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("All sync conflicts have been resolved.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pending sync conflicts. All sync conflicts have been resolved.")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var filterToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Status", selection: $viewModel.statusFilter) {
                    Text("All").tag(Optional<ConflictStatus>.none)
                    ForEach(ConflictStatus.allCases, id: \.self) { s in
                        Text(s.displayName).tag(Optional(s))
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.bizarreTeal)
            }
            .accessibilityLabel("Filter conflicts by status")
            .onChange(of: viewModel.statusFilter) { _, _ in
                Task { await viewModel.loadConflicts() }
            }
        }
    }

    // MARK: - Helpers

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { if case .error = viewModel.phase { return true } else { return false } },
            set: { _ in }
        )
    }

    private func conflictA11yLabel(_ c: ConflictItem) -> String {
        "\(c.entityKind) entity \(c.entityId). \(c.conflictType.displayName). Reported by \(c.reporterDisplayName)."
    }
}

// MARK: - ConflictRowView

private struct ConflictRowView: View {
    let conflict: ConflictItem

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Label {
                    Text("\(conflict.entityKind) #\(conflict.entityId)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                } icon: {
                    Image(systemName: conflictTypeIcon(conflict.conflictType))
                        .foregroundStyle(conflictTypeColor(conflict.conflictType))
                        .accessibilityHidden(true)
                }

                Spacer()

                statusBadge(conflict.status)
            }

            HStack(spacing: BrandSpacing.sm) {
                Text(conflict.conflictType.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Spacer()

                Text(relativeDate(conflict.reportedAt))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Text("Reported by \(conflict.reporterDisplayName)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }

    // MARK: Helpers

    private func conflictTypeIcon(_ type: ConflictType) -> String {
        switch type {
        case .concurrentUpdate: return "arrow.triangle.2.circlepath"
        case .staleWrite:       return "clock.badge.exclamationmark"
        case .duplicateCreate:  return "doc.on.doc"
        case .deletedRemote:    return "trash.slash"
        }
    }

    private func conflictTypeColor(_ type: ConflictType) -> Color {
        switch type {
        case .concurrentUpdate: return .bizarreWarning
        case .staleWrite:       return .bizarreWarning
        case .duplicateCreate:  return .bizarreTeal
        case .deletedRemote:    return .bizarreError
        }
    }

    private func statusBadge(_ status: ConflictStatus) -> some View {
        Text(status.displayName)
            .font(.brandMono(size: 10))
            .foregroundStyle(statusForeground(status))
            .padding(.horizontal, BrandSpacing.xs)
            .padding(.vertical, 2)
            .background(statusBackground(status), in: Capsule())
    }

    private func statusForeground(_ status: ConflictStatus) -> Color {
        switch status {
        case .pending:  return .bizarreWarning
        case .resolved: return .bizarreSuccess
        case .rejected: return .bizarreError
        case .deferred: return .bizarreOnSurfaceMuted
        }
    }

    private func statusBackground(_ status: ConflictStatus) -> some ShapeStyle {
        switch status {
        case .pending:  return Color.bizarreWarning.opacity(0.15)
        case .resolved: return Color.bizarreSuccess.opacity(0.15)
        case .rejected: return Color.bizarreError.opacity(0.15)
        case .deferred: return Color.bizarreOnSurfaceMuted.opacity(0.15)
        }
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let date = formatter.date(from: iso) ?? fallback.date(from: iso) ?? Date()
        return Self.dateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
