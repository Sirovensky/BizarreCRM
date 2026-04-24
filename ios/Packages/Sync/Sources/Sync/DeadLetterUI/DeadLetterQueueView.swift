import SwiftUI
import DesignSystem
import Core

// MARK: - DeadLetterQueueView

/// Root "Sync Dead-Letter Queue" screen.
///
/// iPhone: single-column list under navigation; iPad: NavigationSplitView
/// with sidebar (filtered list) + detail pane side-by-side.
///
/// Uses `DeadLetterActionCoordinator` via protocol seam so the UI is
/// independent of the real GRDB store. `DeadLetterStoreProtocol` is the
/// injection point; callers may pass a mock for previews / tests.
public struct DeadLetterQueueView: View {
    // MARK: - State

    @State private var coordinator: DeadLetterActionCoordinator
    @State private var items: [DeadLetterItem] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var filter: DeadLetterFilter = .all
    @State private var selectedItem: DeadLetterItem?
    @State private var showDiscardAll: Bool = false

    private let store: any DeadLetterStoreProtocol

    // MARK: - Init

    public init(store: any DeadLetterStoreProtocol = DeadLetterRepository.shared) {
        self.store = store
        self._coordinator = State(
            initialValue: DeadLetterActionCoordinator(store: store)
        )
    }

    // MARK: - Derived

    private var filteredItems: [DeadLetterItem] {
        items.applying(filter)
    }

    private var availableEntities: [String] {
        Array(Set(items.map(\.entity))).sorted()
    }

    // MARK: - Body

    public var body: some View {
        mainContent
            .navigationTitle("Sync Dead Letter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .task { await loadItems() }
            .refreshable { await loadItems() }
            .alert("Error", isPresented: Binding(
                get: { coordinator.lastError != nil || loadError != nil },
                set: { if !$0 { coordinator.clearError(); loadError = nil } }
            )) {
                Button("OK") { coordinator.clearError(); loadError = nil }
            } message: {
                Text(coordinator.lastError ?? loadError ?? "")
            }
            .confirmationDialog(
                "Discard All",
                isPresented: $showDiscardAll,
                titleVisibility: .visible
            ) {
                Button("Discard \(filteredItems.count) operation\(filteredItems.count == 1 ? "" : "s")", role: .destructive) {
                    Task { await coordinator.discardAll(ids: filteredItems.map(\.id)) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Permanently removes all visible failed operations. This cannot be undone.")
            }
            .onChange(of: coordinator.isBulkInFlight) { _, inFlight in
                if !inFlight { Task { await loadItems() } }
            }
    }

    // MARK: - Layout switch

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
        #else
        iPadLayout
        #endif
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        Group {
            if isLoading && items.isEmpty {
                loadingView
            } else if filteredItems.isEmpty && !filter.isActive && items.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    if !availableEntities.isEmpty || filter.isActive {
                        DeadLetterFilterBar(
                            filter: $filter,
                            availableEntities: availableEntities
                        )
                        .background(.bar)
                        Divider()
                    }
                    listView(items: filteredItems, selection: nil)
                }
            }
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                DeadLetterItemDetailView(
                    item: item,
                    coordinator: coordinator,
                    store: store,
                    onDismiss: { selectedItem = nil; Task { await loadItems() } }
                )
            }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            if let selected = selectedItem {
                DeadLetterItemDetailView(
                    item: selected,
                    coordinator: coordinator,
                    store: store,
                    onDismiss: { selectedItem = nil; Task { await loadItems() } }
                )
            } else {
                ContentUnavailableView(
                    "Select an operation",
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    description: Text("Choose a failed sync operation from the list.")
                )
            }
        }
    }

    private var sidebarContent: some View {
        Group {
            if isLoading && items.isEmpty {
                loadingView
            } else if items.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: 0) {
                    if !availableEntities.isEmpty || filter.isActive {
                        DeadLetterFilterBar(
                            filter: $filter,
                            availableEntities: availableEntities
                        )
                        Divider()
                    }
                    listView(items: filteredItems, selection: $selectedItem)
                }
            }
        }
        .navigationTitle("Sync Dead Letter")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Shared list

    private func listView(items: [DeadLetterItem], selection: Binding<DeadLetterItem?>?) -> some View {
        List(selection: selection) {
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        DeadLetterQueueRow(
                            item: item,
                            isInFlight: coordinator.isInFlight(item.id),
                            onTap: {
                                selectedItem = item
                                #if os(iOS)
                                if Platform.isCompact { selectedItem = item }
                                #endif
                            },
                            onRetry: {
                                Task { await coordinator.retryOne(id: item.id); await loadItems() }
                            },
                            onDiscard: {
                                Task { await coordinator.discardOne(id: item.id); await loadItems() }
                            }
                        )
                        .tag(item)
                        #if os(iOS)
                        .hoverEffect(.highlight)
                        #endif
                        .contextMenu {
                            Button {
                                Task { await coordinator.retryOne(id: item.id); await loadItems() }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                Task { await coordinator.discardOne(id: item.id); await loadItems() }
                            } label: {
                                Label("Discard", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("\(items.count) failed operation\(items.count == 1 ? "" : "s")")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                noResultsRow
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading dead-letter queue")
    }

    private var emptyStateView: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No failed operations")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Sync dead-letter queue is empty.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync dead-letter queue is empty. No failed operations.")
    }

    private var noResultsRow: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No items match the current filters.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(BrandSpacing.xl)
            Spacer()
        }
        .listRowBackground(Color.clear)
        .accessibilityLabel("No items match the current filters")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Retry All — primary action
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await coordinator.retryAll(ids: filteredItems.map(\.id)) }
            } label: {
                Label("Retry All", systemImage: "arrow.clockwise.circle")
            }
            .disabled(filteredItems.isEmpty || coordinator.isBulkInFlight)
            .accessibilityLabel("Retry all visible operations")
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        // Discard All — destructive, trailing
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                showDiscardAll = true
            } label: {
                Label("Discard All", systemImage: "trash.circle")
            }
            .disabled(filteredItems.isEmpty || coordinator.isBulkInFlight)
            .accessibilityLabel("Discard all visible operations")
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    // MARK: - Data

    private func loadItems() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            items = try await store.fetchAll(limit: 200)
        } catch {
            loadError = error.localizedDescription
            AppLog.sync.error("DeadLetterQueueView.loadItems failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - DeadLetterQueueRow

private struct DeadLetterQueueRow: View {
    let item: DeadLetterItem
    let isInFlight: Bool
    let onTap: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            // Status icon
            ZStack {
                Circle()
                    .fill(Color.bizarreError.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.bizarreError)
            }
            .accessibilityHidden(true)

            // Content
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(item.entity)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text(Self.relFormatter.localizedString(for: item.movedAt, relativeTo: Date()))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                HStack(spacing: BrandSpacing.sm) {
                    Text(item.op.uppercased())
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreTeal)
                    if let error = item.lastError {
                        Text(error)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                            .lineLimit(1)
                    }
                }
                Text("\(item.attemptCount) attempt\(item.attemptCount == 1 ? "" : "s")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Inline action buttons (only on wide rows)
            if !Platform.isCompact {
                Divider().frame(height: 32)
                inlineActions
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .padding(.vertical, BrandSpacing.xxs)
        .overlay {
            if isInFlight {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bizarreOnSurface.opacity(0.06))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint("Double-tap to view details")
    }

    private var inlineActions: some View {
        HStack(spacing: BrandSpacing.xs) {
            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.brandGlassClear)
            .disabled(isInFlight)
            .accessibilityLabel("Retry \(item.entity) \(item.op)")

            Button(role: .destructive) {
                onDiscard()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.bizarreError)
            }
            .buttonStyle(.brandGlassClear)
            .disabled(isInFlight)
            .accessibilityLabel("Discard \(item.entity) \(item.op)")
        }
    }

    private var a11yLabel: String {
        let entity = "\(item.entity) \(item.op)"
        let attempts = "\(item.attemptCount) attempt\(item.attemptCount == 1 ? "" : "s")"
        let err = item.lastError.map { "Error: \($0)." } ?? ""
        return "\(entity). \(attempts). \(err)"
    }
}

// MARK: - DeadLetterItemDetailView

/// Full detail screen: header, error reason, JSON payload, single-item actions.
/// Used both in iPhone sheet and iPad detail column.
public struct DeadLetterItemDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let item: DeadLetterItem
    let coordinator: DeadLetterActionCoordinator
    let store: any DeadLetterStoreProtocol
    let onDismiss: () -> Void

    @State private var detailItem: DeadLetterItem?
    @State private var isLoadingDetail: Bool = true
    @State private var showDiscardConfirm: Bool = false

    public init(
        item: DeadLetterItem,
        coordinator: DeadLetterActionCoordinator,
        store: any DeadLetterStoreProtocol,
        onDismiss: @escaping () -> Void
    ) {
        self.item = item
        self.coordinator = coordinator
        self.store = store
        self.onDismiss = onDismiss
    }

    private var displayItem: DeadLetterItem { detailItem ?? item }
    private var isInFlight: Bool { coordinator.isInFlight(item.id) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                headerSection
                errorSection
                payloadSection
                Spacer(minLength: BrandSpacing.base)
                actionSection
            }
            .padding(BrandSpacing.base)
        }
        .navigationTitle("Dead Letter Detail")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { onDismiss(); dismiss() }
                    .accessibilityLabel("Close detail view")
            }
        }
        .task { await loadDetail() }
        .alert("Discard Operation?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                Task {
                    await coordinator.discardOne(id: item.id)
                    onDismiss()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the failed operation. It cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("\(displayItem.entity) — \(displayItem.op.uppercased())")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text("Failed after \(displayItem.attemptCount) attempt\(displayItem.attemptCount == 1 ? "" : "s")")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("Moved to dead letter: \(displayItem.movedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = displayItem.lastError {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Error Reason")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text(error)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .textSelection(.enabled)
                    .accessibilityLabel("Error: \(error)")
            }
            .padding(BrandSpacing.sm)
            .background(
                Color.bizarreError.opacity(0.08),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
            )
        }
    }

    // MARK: - Payload

    private var payloadSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Payload (JSON)")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            if isLoadingDetail {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel("Loading payload")
            } else {
                let payload = displayItem.payload
                if payload.isEmpty {
                    Text("No payload available")
                        .font(.brandMono())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("No payload available")
                } else {
                    Text(prettyPrint(payload))
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                        .accessibilityLabel("JSON payload")
                }
            }
        }
        .padding(BrandSpacing.sm)
        .background(
            Color.bizarreSurface2.opacity(0.5),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
        )
    }

    // MARK: - Actions

    private var actionSection: some View {
        BrandGlassContainer {
            VStack(spacing: BrandSpacing.sm) {
                Button {
                    Task {
                        await coordinator.retryOne(id: item.id)
                        onDismiss()
                        dismiss()
                    }
                } label: {
                    HStack {
                        if isInFlight {
                            ProgressView()
                                .tint(.bizarreOnOrange)
                                .scaleEffect(0.8)
                        }
                        Text(isInFlight ? "Retrying…" : "Retry")
                            .font(.brandTitleSmall())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .disabled(isInFlight)
                .accessibilityLabel("Retry this sync operation")
                .accessibilityHint("Re-enqueues the operation for another attempt")
                .keyboardShortcut("r", modifiers: .command)

                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Text("Discard")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandGlass)
                .tint(.bizarreError)
                .disabled(isInFlight)
                .accessibilityLabel("Discard this operation")
                .accessibilityHint("Permanently removes the failed operation")
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }
    }

    // MARK: - Helpers

    private func loadDetail() async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            detailItem = try await store.fetchDetail(item.id)
        } catch {
            AppLog.sync.error("DeadLetterItemDetailView.loadDetail failed: \(error, privacy: .public)")
        }
    }

    private func prettyPrint(_ json: String) -> String {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let result = String(data: pretty, encoding: .utf8)
        else { return json }
        return result
    }
}
