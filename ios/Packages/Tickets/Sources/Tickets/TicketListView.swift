#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Customers

public struct TicketListView: View {
    @State private var vm: TicketListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
    @State private var showingSortMenu: Bool = false
    @State private var showingExport: Bool = false
    // §4.5 — Bulk action state
    @State private var bulkSelection: BulkEditSelection = .init()
    @State private var showingBulkAction: Bool = false
    @State private var bulkOutcomes: [BulkTicketOutcome] = []
    @State private var showingBulkResult: Bool = false
    // §4.1 — Column/density picker state (iPad/Mac)
    @State private var columnPrefs: TicketColumnPrefs = .load()
    @State private var showingColumnPicker: Bool = false
    private let repo: TicketRepository
    private let api: APIClient?
    private let customerRepo: CustomerRepository?

    // §22 quick-action handlers — no-op unless api is wired.
    private var quickActionHandlers: TicketQuickActionHandlers {
        TicketQuickActionHandlers(
            onAdvanceStatus: { [weak vm] ticket, transition in
                guard let vm else { return }
                Task { await vm.advanceStatus(ticket: ticket, transition: transition) }
            },
            onAssign: { _, _ in
                // TODO: POST /tickets/:id/assign — endpoint pending §4 write flow
            },
            onAddNote: { _ in
                // TODO: present AddNoteSheet — §4 write flow
            },
            onDuplicate: { _ in
                // TODO: POST /tickets/:id/duplicate — endpoint pending §4
            },
            onArchive: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.archive(ticket: ticket) }
            },
            onDelete: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.delete(ticket: ticket) }
            },
            onConvertToInvoice: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.convertToInvoice(ticket: ticket) }
            },
            onTogglePin: { [weak vm] ticket in
                guard let vm else { return }
                Task { await vm.togglePin(ticket: ticket) }
            }
        )
    }

    /// List + detail only. Create/Edit unavailable.
    public init(repo: TicketRepository) {
        self.repo = repo
        self.api = nil
        self.customerRepo = nil
        _vm = State(wrappedValue: TicketListViewModel(repo: repo))
    }

    /// Enables the "+" toolbar + Edit in the row context menu + pin/convert actions.
    public init(repo: TicketRepository, api: APIClient, customerRepo: CustomerRepository) {
        self.repo = repo
        self.api = api
        self.customerRepo = customerRepo
        _vm = State(wrappedValue: TicketListViewModel(repo: repo, api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        // §4.5 — Bulk action sheet
        .sheet(isPresented: $showingBulkAction) {
            if let api {
                BulkActionMenu(
                    selection: bulkSelection,
                    api: api
                ) { action in
                    let ids = Array(bulkSelection.selectedIDs)
                    let coordinator = BulkEditCoordinator(api: api)
                    showingBulkAction = false
                    Task {
                        let outcomes = await coordinator.execute(action: action, ticketIDs: ids)
                        bulkOutcomes = outcomes
                        bulkSelection.deactivate()
                        showingBulkResult = true
                        await vm.refresh()
                    }
                }
            }
        }
        .sheet(isPresented: $showingBulkResult) {
            BulkEditResultView(outcomes: bulkOutcomes) { failedIds in
                // retry: re-open bulk menu for failed IDs
                bulkSelection.activateMode()
                failedIds.forEach { bulkSelection.toggle($0) }
                showingBulkAction = true
            }
        }
    }

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterAndSortBar
                    listContent { id in
                        path.append(id)
                    }
                }
            }
            .navigationTitle("Tickets")
            .searchable(text: $searchText, prompt: "Search tickets")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                detailView(for: id)
            }
            .toolbar {
                newTicketToolbar
                sortToolbarItem
                stalenessToolbarItem
                exportToolbarItem
                selectToolbarItem
            }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api, let customerRepo {
                    TicketCreateView(api: api, customerRepo: customerRepo)
                }
            }
            .sheet(isPresented: $showingExport) {
                if let api {
                    TicketExportView(api: api, filter: vm.filter, keyword: vm.searchQuery.isEmpty ? nil : vm.searchQuery, sort: vm.sort)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if bulkSelection.isActive && bulkSelection.hasSelection {
                    TicketBulkActionBar(
                        count: bulkSelection.count,
                        onAction: { showingBulkAction = true },
                        onDeselect: { bulkSelection.deactivate() }
                    )
                }
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterAndSortBar
                    listContent { id in
                        selected = id
                    }
                }
            }
            .navigationTitle("Tickets")
            .searchable(text: $searchText, prompt: "Search tickets")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar {
                newTicketToolbar
                sortToolbarItem
                stalenessToolbarItem
                columnPickerToolbarItem
                exportToolbarItem
                selectToolbarItem
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if bulkSelection.isActive && bulkSelection.hasSelection {
                    TicketBulkActionBar(
                        count: bulkSelection.count,
                        onAction: { showingBulkAction = true },
                        onDeselect: { bulkSelection.deactivate() }
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                if let api, let customerRepo {
                    TicketCreateView(api: api, customerRepo: customerRepo)
                }
            }
            .sheet(isPresented: $showingExport) {
                if let api {
                    TicketExportView(api: api, filter: vm.filter, keyword: vm.searchQuery.isEmpty ? nil : vm.searchQuery, sort: vm.sort)
                }
            }
        } detail: {
            if let id = selected {
                NavigationStack {
                    detailView(for: id)
                }
            } else {
                EmptyTicketDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared

    @ViewBuilder
    private func detailView(for id: Int64) -> some View {
        if let api {
            TicketDetailView(repo: repo, ticketId: id, api: api)
        } else {
            TicketDetailView(repo: repo, ticketId: id)
        }
    }

    private var newTicketToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCreate = true
            } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New ticket")
            .disabled(api == nil || customerRepo == nil)
        }
    }

    /// §4.5 — Multi-select toggle button.
    private var selectToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                bulkSelection.toggleMode()
            } label: {
                Label(
                    bulkSelection.isActive ? "Done" : "Select",
                    systemImage: bulkSelection.isActive ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .accessibilityLabel(bulkSelection.isActive ? "Exit selection mode" : "Enter selection mode")
        }
    }

    /// §4.1 — Sort dropdown in toolbar.
    private var sortToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                ForEach(TicketSortOrder.allCases) { option in
                    Button {
                        Task { await vm.applySort(option) }
                    } label: {
                        HStack {
                            Text(option.displayName)
                            if vm.sort == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort tickets. Current: \(vm.sort.displayName)")
        }
    }

    private var stalenessToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    /// §4.1 Column/density picker — iPad/Mac only.
    private var columnPickerToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingColumnPicker = true
            } label: {
                Label("Columns", systemImage: "slider.horizontal.3")
            }
            .accessibilityLabel("Column and density settings")
            .sheet(isPresented: $showingColumnPicker) {
                TicketColumnDensityPicker(prefs: $columnPrefs)
            }
        }
    }

    /// §4.1 — Export CSV toolbar item.
    private var exportToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingExport = true
            } label: {
                Label("Export CSV", systemImage: "arrow.down.doc")
            }
            .disabled(api == nil)
            .accessibilityLabel("Export tickets as CSV")
        }
    }

    // MARK: - Filter + Sort bar

    private var filterAndSortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(TicketListFilter.allCases) { option in
                    FilterChip(
                        label: option.displayName,
                        selected: vm.filter == option
                    ) {
                        Task { await vm.applyFilter(option) }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading tickets")
        } else if let err = vm.errorMessage {
            TicketErrorState(message: err) { Task { await vm.load() } }
        } else if vm.tickets.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "tickets")
        } else if vm.tickets.isEmpty {
            TicketEmptyState(
                hint: emptyHint,
                showCreateCTA: api != nil && customerRepo != nil,
                onCreate: { showingCreate = true }
            )
        } else {
            VStack(spacing: 0) {
                List(selection: Binding<Int64?>(
                    get: { Platform.isCompact ? nil : selected },
                    set: { if let id = $0 { selected = id } }
                )) {
                    ForEach(vm.tickets) { ticket in
                        ticketRow(ticket: ticket, onSelect: onSelect)
                            .listRowBackground(Color.bizarreSurface1)
                            .listRowInsets(EdgeInsets(top: BrandSpacing.sm, leading: BrandSpacing.base, bottom: BrandSpacing.sm, trailing: BrandSpacing.base))
                            .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                // §4.1 Footer state
                TicketListFooter(state: vm.footerState)
            }
        }
    }

    @ViewBuilder
    private func ticketRow(ticket: TicketSummary, onSelect: @escaping (Int64) -> Void) -> some View {
        let currentStatus = TicketStatus(rawValue: ticket.status?.name.lowercased().replacingOccurrences(of: " ", with: "") ?? "")
        let isSelected = bulkSelection.selectedIDs.contains(ticket.id)
        if bulkSelection.isActive {
            // §4.5 — Bulk-select mode: tap toggles selection
            Button {
                bulkSelection.toggle(ticket.id)
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                        .font(.system(size: 22))
                        .accessibilityHidden(true)
                    TicketRow(ticket: ticket)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isSelected ? "Selected" : "Not selected"): \(ticket.orderId)")
        } else if Platform.isCompact {
            NavigationLink(value: ticket.id) {
                TicketRow(ticket: ticket)
            }
            .hoverEffect(.highlight)
            .contextMenu {
                TicketQuickActionsContent(
                    ticket: ticket,
                    currentStatus: currentStatus,
                    assignees: [],
                    handlers: quickActionHandlers
                )
            }
            .modifier(TicketRowSwipeActions(
                ticket: ticket,
                currentStatus: currentStatus,
                handlers: quickActionHandlers
            ))
            // Long-press to enter bulk selection
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                bulkSelection.activateMode()
                bulkSelection.toggle(ticket.id)
            })
        } else {
            Button { onSelect(ticket.id) } label: {
                TicketRow(ticket: ticket)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .tag(ticket.id)
            .contextMenu {
                TicketQuickActionsContent(
                    ticket: ticket,
                    currentStatus: currentStatus,
                    assignees: [],
                    handlers: quickActionHandlers
                )
            }
            .modifier(TicketRowSwipeActions(
                ticket: ticket,
                currentStatus: currentStatus,
                handlers: quickActionHandlers
            ))
            // Long-press to enter bulk selection
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                bulkSelection.activateMode()
                bulkSelection.toggle(ticket.id)
            })
        }
    }

    private var emptyHint: String {
        if !searchText.isEmpty { return "No results for \"\(searchText)\"." }
        switch vm.filter {
        case .all:       return "No tickets yet."
        case .open:      return "Nothing open right now."
        case .onHold:    return "Nothing on hold."
        case .closed:    return "Nothing closed yet."
        case .cancelled: return "No cancelled tickets."
        case .active:    return "No active tickets in progress."
        case .myTickets: return "No tickets are assigned to you."
        }
    }
}

// MARK: - Row

private struct TicketRow: View {
    let ticket: TicketSummary

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(primaryLine)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    // §4.1 — Pinned/bookmarked indicator
                    if ticket.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Pinned")
                    }
                }
                Text(secondaryLine)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)

                // §4.1 — Urgency chip with color dot
                if let urgency = ticket.urgency, !urgency.isEmpty {
                    UrgencyChip(urgency: urgency)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                if let status = ticket.status {
                    StatusPill(status.name, hue: groupHue(status.group))
                }
                Text(formatMoney(ticket.total))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()

                // §4.1 — Row age / due-date badge (red/amber/yellow/gray)
                if let dueOn = ticket.dueOn {
                    DueDateBadge(isoDateString: dueOn)
                }

                // §4.1 — SLA badge color indicator
                if let sla = ticket.slaStatus, !sla.isEmpty {
                    SLABadge(status: sla)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            RowAccessibilityFormatter.ticketRow(
                id: ticket.orderId,
                customer: ticket.customer?.displayName ?? "",
                device: ticket.firstDevice?.deviceName ?? "",
                status: ticket.status?.name ?? "",
                dueAt: ticket.dueOn
            )
        )
        .accessibilityHint(RowAccessibilityFormatter.ticketRowHint)
        .accessibilityAddTraits(.isButton)
    }

    // Customer-first, falling back to device or order ID.
    private var primaryLine: String {
        if let name = ticket.customer?.displayName, !name.isEmpty { return name }
        if let device = ticket.firstDevice?.deviceName, !device.isEmpty { return device }
        return ticket.orderId
    }

    private var secondaryLine: String {
        let device = ticket.firstDevice?.deviceName ?? ""
        if !device.isEmpty && device != primaryLine {
            return "\(ticket.orderId)  \u{2022}  \(device)"
        }
        return ticket.orderId
    }

    private func groupHue(_ group: TicketSummary.Status.Group) -> StatusPill.Hue {
        switch group {
        case .inProgress: return .inProgress
        case .waiting:    return .awaiting
        case .complete:   return .completed
        case .cancelled:  return .archived
        }
    }

    private func formatMoney(_ cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents / 100)"
    }
}

// MARK: - §4.1 Urgency chip

private struct UrgencyChip: View {
    let urgency: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(urgency.capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(dotColor)
        }
        .accessibilityLabel("Urgency: \(urgency)")
    }

    private var dotColor: Color {
        switch urgency.lowercased() {
        case "critical": return Color.bizarreError
        case "high":     return Color.bizarreOrange
        case "medium":   return Color(red: 0.93, green: 0.76, blue: 0.18) // amber
        case "normal":   return Color.bizarreOnSurfaceMuted
        case "low":      return Color.bizarreTeal
        default:         return Color.bizarreOnSurfaceMuted
        }
    }
}

// MARK: - §4.1 SLA badge

private struct SLABadge: View {
    let status: String  // e.g. "ok", "warning", "breached"

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(badgeColor)
            .accessibilityLabel("SLA \(status)")
    }

    private var icon: String {
        switch status.lowercased() {
        case "breached": return "clock.badge.xmark"
        case "warning":  return "clock.badge.exclamationmark"
        default:         return "clock"
        }
    }

    private var badgeColor: Color {
        switch status.lowercased() {
        case "breached": return .bizarreError
        case "warning":  return .bizarreOrange
        default:         return .bizarreOnSurfaceMuted
        }
    }
}

// MARK: - §4.1 Row age / due-date badge

/// Compact badge showing days until (or since) the ticket due date.
/// Color scheme mirrors Android My Queue:
///   red     — overdue (past due date)
///   amber   — due within 24 hours
///   yellow  — due within 3 days
///   gray    — due in 3+ days or undetermined
private struct DueDateBadge: View {
    let isoDateString: String

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Short: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private var dueDate: Date? {
        Self.iso8601.date(from: isoDateString) ?? Self.iso8601Short.date(from: isoDateString)
    }

    private var daysUntilDue: Int? {
        guard let due = dueDate else { return nil }
        let seconds = due.timeIntervalSinceNow
        return Int(seconds / 86400)
    }

    var body: some View {
        if let days = daysUntilDue {
            HStack(spacing: 3) {
                Circle()
                    .fill(dotColor(days: days))
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text(label(days: days))
                    .font(.brandLabelSmall())
                    .foregroundStyle(dotColor(days: days))
            }
            .accessibilityLabel(a11yLabel(days: days))
        }
    }

    private func label(days: Int) -> String {
        if days < 0  { return "\(-days)d overdue" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }

    private func a11yLabel(days: Int) -> String {
        if days < 0  { return "Overdue by \(-days) day\(-days == 1 ? "" : "s")" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }

    private func dotColor(days: Int) -> Color {
        if days < 0  { return .bizarreError }
        if days == 0 { return .bizarreOrange }
        if days <= 3 { return Color(red: 0.93, green: 0.76, blue: 0.18) } // amber
        return .bizarreOnSurfaceMuted
    }
}

// MARK: - §4.1 Footer states

private struct TicketListFooter: View {
    let state: TicketListFooterState

    var body: some View {
        Group {
            switch state {
            case .loading:
                HStack(spacing: BrandSpacing.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

            case .showing(let count):
                Text("Showing \(count) ticket\(count == 1 ? "" : "s")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

            case .end:
                Text("End of list")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

            case .offline(let count, let syncedAt):
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    if let syncedAt {
                        let ago = relativeTime(from: syncedAt)
                        Text("Offline — \(count) cached, last synced \(ago)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        Text("Offline — \(count) cached")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.bizarreSurfaceBase)
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 { return "\(hours)h ago" }
        if minutes > 0 { return "\(minutes)m ago" }
        return "just now"
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(selected ? Color.black : Color.bizarreOnSurface)
                .background(
                    selected ? Color.bizarreOrange : Color.bizarreSurface1,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.bizarreOutline.opacity(selected ? 0 : 0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Empty / Error / Placeholder

private struct TicketErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load tickets")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// §4.13 — "No tickets yet. Create one." with optional CTA.
private struct TicketEmptyState: View {
    let hint: String
    var showCreateCTA: Bool = false
    var onCreate: () -> Void = {}

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                .accessibilityHidden(true)
            Text(hint)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            if showCreateCTA {
                Button {
                    onCreate()
                } label: {
                    Label("Create your first ticket", systemImage: "plus")
                        .font(.brandBodyLarge())
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Create your first ticket")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyTicketDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a ticket from the list.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }
}

// MARK: - §4.5 Bulk action floating bar

/// Floating glass bar shown at the bottom of the list when bulk-selection mode is active
/// and at least one ticket is selected.
private struct TicketBulkActionBar: View {
    let count: Int
    let onAction: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.base) {
            Button(action: onDeselect) {
                Label("Cancel", systemImage: "xmark.circle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel selection")

            Spacer()

            Text("\(count) selected")
                .font(.brandBodyMedium().bold())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("\(count) tickets selected")

            Spacer()

            Button(action: onAction) {
                Label("Actions…", systemImage: "ellipsis.circle.fill")
                    .font(.brandBodyMedium().bold())
                    .foregroundStyle(.bizarreOrange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show bulk actions for \(count) selected tickets")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(duration: 0.25), value: count)
    }
}
#endif
