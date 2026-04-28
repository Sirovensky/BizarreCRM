import Foundation

// MARK: - CustomerSortOrder

/// Sort options for the customer list, including §44.2/§44.3 additions.
public enum CustomerSortOrder: String, CaseIterable, Sendable {
    case name         = "A–Z"
    case nameDesc     = "Z–A"
    case mostTickets  = "Most tickets"
    case mostRevenue  = "Most revenue"
    case lastVisit    = "Last visit"
    case ltvTier      = "LTV tier ↑"
    case churnRisk    = "Churn risk ↑"
}

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync
import Contacts
import ContactsUI

public struct CustomerListView: View {
    @State private var vm: CustomerListViewModel
    @State private var searchText: String = ""
    @State private var path: [Int64] = []
    @State private var selected: Int64?
    @State private var showingCreate: Bool = false
    @State private var showingFilter: Bool = false
    @State private var showingTagInput: Bool = false
    @State private var showingContactPicker: Bool = false
    @State private var showingDeleteUndo: Bool = false
    @State private var undoCustomers: [CustomerSummary] = []
    @State private var undoTask: Task<Void, Never>?
    private let listRepo: CustomerRepository
    private let detailRepo: CustomerDetailRepository
    private let api: APIClient

    public init(repo: CustomerRepository, detailRepo: CustomerDetailRepository, api: APIClient) {
        self.listRepo = repo
        self.detailRepo = detailRepo
        self.api = api
        _vm = State(wrappedValue: CustomerListViewModel(repo: repo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .sheet(isPresented: $showingFilter) {
            CustomerFilterSheet(filter: $vm.filter) {
                Task { await vm.load() }
            }
        }
        .sheet(isPresented: $showingTagInput) {
            BulkTagInputSheet { tag in
                Task { await vm.bulkTag(tag: tag) }
            }
        }
        .sheet(isPresented: $showingContactPicker) {
            ContactPickerView { contacts in
                // Each contact → open CustomerCreateView prefilled.
                // Phase 4 wiring: deep-link is handled outside this package.
                // For now, log the contact count and show create sheet.
                if contacts.count == 1 {
                    showingCreate = true
                }
            }
        }
        // §5.4 Concurrent-edit 409 banner
        .overlay(alignment: .top) {
            if vm.concurrentEditConflict {
                ConflictBanner {
                    vm.dismissConflictBanner()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: vm.concurrentEditConflict)
                .padding(.top, BrandSpacing.sm)
            }
        }
        // §5.1 Bulk delete undo toast (5-second window)
        .overlay(alignment: .bottom) {
            if showingDeleteUndo {
                UndoToast(
                    message: "Deleted \(undoCustomers.count) customer\(undoCustomers.count == 1 ? "" : "s")"
                ) {
                    undoTask?.cancel()
                    showingDeleteUndo = false
                    Task { await vm.undoBulkDelete(restored: undoCustomers) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: showingDeleteUndo)
                .padding(.bottom, BrandSpacing.lg)
            }
        }
    }

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainStack
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .navigationDestination(for: Int64.self) { id in
                CustomerDetailView(repo: detailRepo, customerId: id, api: api)
            }
            .toolbar {
                newCustomerToolbar
                stalenessToolbarItem
                sortToolbarItem
                filterToolbarItem
                statsToolbarItem
                bulkSelectToolbarItem
                exportToolbarItem
                importToolbarItem
            }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                CustomerCreateView(api: api)
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainStack
            }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .refreshable { await vm.refresh() }
            .toolbar {
                newCustomerToolbar
                stalenessToolbarItem
                sortToolbarItem
                filterToolbarItem
                statsToolbarItem
                bulkSelectToolbarItem
                exportToolbarItem
                importToolbarItem
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.refresh() } }) {
                CustomerCreateView(api: api)
            }
        } detail: {
            if let id = selected {
                NavigationStack {
                    CustomerDetailView(repo: detailRepo, customerId: id, api: api)
                }
            } else {
                EmptyDetailPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Main stack (stats + list + bulk bar)

    @ViewBuilder
    private var mainStack: some View {
        VStack(spacing: 0) {
            // §5.1 Stats header (toggleable)
            if vm.showStats, let stats = vm.stats {
                CustomerStatsHeader(stats: stats)
                Divider().overlay(Color.bizarreOutline.opacity(0.2))
            }

            // §5.7 Tag filter active bar
            if let activeTag = vm.filter.tag, !activeTag.isEmpty {
                CustomerTagFilterBar(tag: activeTag) {
                    vm.filter.tag = nil
                    Task { await vm.load() }
                }
            }

            // Main list content
            listContent { id in
                if vm.isBulkSelecting {
                    vm.toggleSelection(id: id)
                } else if Platform.isCompact {
                    path.append(id)
                } else {
                    selected = id
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // §5.1 / §5.6 Bulk action bar
            if vm.isBulkSelecting {
                CustomerBulkActionBar(
                    selectedCount: vm.selectedIds.count,
                    onTag: { showingTagInput = true },
                    onExport: {
                        // §5.6 bulk export selected customers as CSV
                        let selected = vm.customers.filter { vm.selectedIds.contains($0.id) }
                        if let url = CustomerCSVExporter.export(selected) {
                            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let vc = scene.windows.first?.rootViewController {
                                vc.present(activity, animated: true)
                            }
                        }
                    },
                    onDelete: {
                        Task {
                            let deleted = await vm.bulkDelete()
                            if !deleted.isEmpty {
                                undoCustomers = deleted
                                showingDeleteUndo = true
                                undoTask?.cancel()
                                undoTask = Task {
                                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                                    if !Task.isCancelled {
                                        showingDeleteUndo = false
                                    }
                                }
                            }
                        }
                    },
                    onCancel: { vm.toggleBulkSelect() }
                )
                // §5.6 bulk export — shares via UIActivityViewController (same as exportCSV())

            }
        }
    }

    // MARK: - Toolbar items

    private var newCustomerToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: {
                Image(systemName: "plus")
            }
            .keyboardShortcut("N", modifiers: .command)
            .accessibilityLabel("New customer")
        }
    }

    private var stalenessToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    /// §5.1 Sort menu.
    private var sortToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                ForEach(CustomerSortOrder.allCases, id: \.self) { order in
                    Button {
                        vm.sortOrder = order
                        Task { await vm.load() }
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if vm.sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort customers by \(vm.sortOrder.rawValue)")
        }
    }

    /// §5.1 Filter button.
    private var filterToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingFilter = true
            } label: {
                Label(
                    vm.filter.isActive ? "Filter (active)" : "Filter",
                    systemImage: vm.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                )
            }
            .accessibilityLabel(vm.filter.isActive ? "Filter active, tap to edit" : "Filter customers")
        }
    }

    /// §5.1 Stats toggle.
    private var statsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                vm.showStats.toggle()
            } label: {
                Label(
                    vm.showStats ? "Hide stats" : "Show stats",
                    systemImage: vm.showStats ? "chart.bar.fill" : "chart.bar"
                )
            }
            .accessibilityLabel(vm.showStats ? "Hide customer stats" : "Show customer stats")
        }
    }

    /// §5.1 Bulk select toggle.
    private var bulkSelectToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                vm.toggleBulkSelect()
            } label: {
                Label(
                    vm.isBulkSelecting ? "Done" : "Select",
                    systemImage: vm.isBulkSelecting ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .accessibilityLabel(vm.isBulkSelecting ? "Done selecting" : "Select multiple customers")
        }
    }

    /// §5.1 Export CSV (iPad/Mac).
    private var exportToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            if !Platform.isCompact {
                Button {
                    exportCSV()
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export customer list as CSV")
            }
        }
    }

    /// §5.1 Import from Contacts.
    private var importToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingContactPicker = true
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
            }
            .accessibilityLabel("Import customers from Contacts")
        }
    }

    // MARK: - List content

    @ViewBuilder
    private func listContent(onSelect: @escaping (Int64) -> Void) -> some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            CustomerErrorState(message: err) { Task { await vm.load() } }
        } else if vm.customers.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "customers")
        } else if vm.customers.isEmpty {
            // §5.1 Empty state
            CustomerEmptyState(
                isSearching: !searchText.isEmpty,
                query: searchText,
                onCreate: { showingCreate = true },
                onImport: { showingContactPicker = true }
            )
        } else {
            // §5.1 A-Z section index on iPhone via SectionedList
            if Platform.isCompact {
                sectionedList(onSelect: onSelect)
            } else {
                plainList(onSelect: onSelect)
            }
        }
    }

    // MARK: - §5.1 A-Z section index (iPhone)

    private var sectionedCustomers: [(letter: String, customers: [CustomerSummary])] {
        let sorted = vm.customers
        var result: [(letter: String, customers: [CustomerSummary])] = []
        var current: (letter: String, customers: [CustomerSummary])?
        for c in sorted {
            let letter = String(c.displayName.prefix(1).uppercased()).filter(\.isLetter)
            let key = letter.isEmpty ? "#" : letter
            if current?.letter == key {
                current?.customers.append(c)
            } else {
                if let prev = current { result.append(prev) }
                current = (key, [c])
            }
        }
        if let last = current { result.append(last) }
        return result
    }

    private func sectionedList(onSelect: @escaping (Int64) -> Void) -> some View {
        List {
            ForEach(sectionedCustomers, id: \.letter) { section in
                Section(header: Text(section.letter)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                ) {
                    ForEach(section.customers) { customer in
                        customerRow(customer: customer, onSelect: onSelect)
                            .listRowBackground(listRowBackground(for: customer))
                            .listRowInsets(EdgeInsets(
                                top: BrandSpacing.sm,
                                leading: BrandSpacing.base,
                                bottom: BrandSpacing.sm,
                                trailing: BrandSpacing.base
                            ))
                            .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                leadingSwipeActions(for: customer)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                trailingSwipeActions(for: customer)
                            }
                            .onAppear {
                                Task { await vm.loadMoreIfNeeded(currentItem: customer) }
                            }
                    }
                }
            }
            if vm.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .accessibilityLabel("Loading more customers")
            } else if !vm.hasMore && !vm.customers.isEmpty {
                Text("End of list")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("End of customer list")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func plainList(onSelect: @escaping (Int64) -> Void) -> some View {
        List(selection: Binding<Int64?>(
            get: { Platform.isCompact ? nil : selected },
            set: { if let id = $0 { selected = id } }
        )) {
            ForEach(vm.customers) { customer in
                customerRow(customer: customer, onSelect: onSelect)
                    .listRowBackground(listRowBackground(for: customer))
                    .listRowInsets(EdgeInsets(
                        top: BrandSpacing.sm,
                        leading: BrandSpacing.base,
                        bottom: BrandSpacing.sm,
                        trailing: BrandSpacing.base
                    ))
                    .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        leadingSwipeActions(for: customer)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        trailingSwipeActions(for: customer)
                    }
                    .onAppear {
                        Task { await vm.loadMoreIfNeeded(currentItem: customer) }
                    }
                    // §5.1 iPad hover preview popover
                    .popover(isPresented: .constant(false)) {
                        CustomerPreviewPopover(customer: customer)
                    }
            }
            if vm.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Loading more customers")
            } else if !vm.hasMore && !vm.customers.isEmpty {
                Text("End of list")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func listRowBackground(for customer: CustomerSummary) -> some View {
        Group {
            if vm.isBulkSelecting && vm.selectedIds.contains(customer.id) {
                Color.bizarreOrange.opacity(0.12)
            } else {
                Color.bizarreSurface1
            }
        }
    }

    // MARK: - §5.1 Row

    @ViewBuilder
    private func customerRow(customer: CustomerSummary, onSelect: @escaping (Int64) -> Void) -> some View {
        Button { onSelect(customer.id) } label: {
            HStack(spacing: BrandSpacing.sm) {
                // §5.1 Bulk select checkmark
                if vm.isBulkSelecting {
                    Image(systemName: vm.selectedIds.contains(customer.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(vm.selectedIds.contains(customer.id) ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                }
                CustomerRow(customer: customer)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .tag(customer.id)
        .contextMenu { customerContextMenu(for: customer, onSelect: onSelect) }
        // §5.1 Preview popover on hover (iPad/Mac)
        .overlay(alignment: .trailing) {
            if !Platform.isCompact {
                PreviewPopoverButton(customer: customer)
            }
        }
    }

    // MARK: - §5.1 Swipe actions

    @ViewBuilder
    private func leadingSwipeActions(for customer: CustomerSummary) -> some View {
        if let digits = phoneDigits(for: customer) {
            Button {
                if let url = URL(string: "tel:\(digits)") { UIApplication.shared.open(url) }
            } label: {
                Label("Call", systemImage: "phone.fill")
            }
            .tint(.bizarreOrange)

            Button {
                if let url = URL(string: "sms:\(digits)") { UIApplication.shared.open(url) }
            } label: {
                Label("SMS", systemImage: "message.fill")
            }
            .tint(.bizarreTeal)
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for customer: CustomerSummary) -> some View {
        Button(role: .destructive) {
            Task {
                let req = BulkDeleteRequest(customerIds: [customer.id])
                _ = try? await listRepo.bulkDelete(req)
                await vm.load()
            }
        } label: {
            Label("Archive", systemImage: "archivebox.fill")
        }

        Button {
            // Mark VIP: apply the "vip" tag.
            Task {
                let req = BulkTagRequest(customerIds: [customer.id], tag: "vip")
                _ = try? await listRepo.bulkTag(req)
            }
        } label: {
            Label("Mark VIP", systemImage: "star.fill")
        }
        .tint(.bizarreOrange)
    }

    // MARK: - §5.1 Context menu (full)

    @ViewBuilder
    private func customerContextMenu(
        for customer: CustomerSummary,
        onSelect: @escaping (Int64) -> Void
    ) -> some View {
        Button {
            onSelect(customer.id)
        } label: {
            Label("Open", systemImage: "person.circle")
        }
        .accessibilityLabel("Open \(customer.displayName)")

        if let digits = phoneDigits(for: customer) {
            Button {
                if let url = URL(string: "tel:\(digits)") { UIApplication.shared.open(url) }
            } label: {
                Label("Call", systemImage: "phone")
            }
            .accessibilityLabel("Call \(customer.displayName)")

            Button {
                if let url = URL(string: "sms:\(digits)") { UIApplication.shared.open(url) }
            } label: {
                Label("SMS", systemImage: "message")
            }
            .accessibilityLabel("Send SMS to \(customer.displayName)")
        }

        if let phone = customer.mobile ?? customer.phone, !phone.isEmpty {
            if let url = URL(string: "facetime:\(phone.filter(\.isNumber))") {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Label("FaceTime", systemImage: "video")
                }
                .accessibilityLabel("FaceTime \(customer.displayName)")
            }
        }

        if let email = customer.email, !email.isEmpty {
            Button {
                UIPasteboard.general.string = email
            } label: {
                Label("Copy email", systemImage: "envelope")
            }
            .accessibilityLabel("Copy \(customer.displayName)'s email")
        }

        if let phone = customer.mobile ?? customer.phone, !phone.isEmpty {
            Button {
                UIPasteboard.general.string = phone
            } label: {
                Label("Copy phone", systemImage: "phone.badge.plus")
            }
            .accessibilityLabel("Copy \(customer.displayName)'s phone")
        }

        Divider()

        Button {
            // TODO: deep-link to TicketCreateView pre-filled — Phase 4
        } label: {
            Label("New Ticket", systemImage: "ticket")
        }
        .accessibilityLabel("Create new ticket for \(customer.displayName)")

        Button {
            // TODO: deep-link to InvoiceCreateView pre-filled — Phase 4
        } label: {
            Label("New Invoice", systemImage: "doc.text")
        }
        .accessibilityLabel("Create new invoice for \(customer.displayName)")

        Divider()

        Button {
            // TODO: present CustomerMergeView — Phase 4
        } label: {
            Label("Merge\u{2026}", systemImage: "person.2.badge.gearshape")
        }
        .accessibilityLabel("Merge \(customer.displayName) with another customer")

        Button(role: .destructive) {
            Task {
                let req = BulkDeleteRequest(customerIds: [customer.id])
                _ = try? await listRepo.bulkDelete(req)
                await vm.load()
            }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        .accessibilityLabel("Archive \(customer.displayName)")
    }

    // MARK: - §5.1 Export CSV

    private func exportCSV() {
        let header = "ID,Name,Email,Phone,Organization,City,State,Tickets\n"
        let rows = vm.customers.map { c in
            [
                String(c.id),
                c.displayName,
                c.email ?? "",
                c.mobile ?? c.phone ?? "",
                c.organization ?? "",
                c.city ?? "",
                c.state ?? "",
                c.ticketCount.map(String.init) ?? ""
            ]
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .map { $0.contains(",") ? "\"\($0)\"" : $0 }
            .joined(separator: ",")
        }.joined(separator: "\n")
        let csv = header + rows
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("customers.csv")
        try? csv.write(to: tmpURL, atomically: true, encoding: .utf8)
        let activity = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let vc = window.rootViewController else { return }
        // iPad presents UIActivityViewController as a popover and crashes if
        // sourceView / sourceRect are not set. Anchor at the top-trailing
        // toolbar area so the share sheet appears near the export button.
        if let popover = activity.popoverPresentationController {
            popover.sourceView = window
            let bounds = window.bounds
            popover.sourceRect = CGRect(x: bounds.maxX - 60, y: bounds.minY + 60,
                                        width: 1, height: 1)
            popover.permittedArrowDirections = [.up]
        }
        vc.present(activity, animated: true)
    }

    // MARK: - Helpers

    private func phoneDigits(for customer: CustomerSummary) -> String? {
        let raw = customer.mobile ?? customer.phone
        guard let raw, !raw.isEmpty else { return nil }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : digits
    }
}

// MARK: - Preview Popover Button (iPad/Mac hover)

/// §5.1 Hover preview popover — quick stats on hover (iPad/Mac).
private struct PreviewPopoverButton: View {
    let customer: CustomerSummary
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.6))
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            CustomerPreviewPopover(customer: customer)
        }
        .accessibilityLabel("Quick preview of \(customer.displayName)")
    }
}

private struct CustomerPreviewPopover: View {
    let customer: CustomerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(customer.displayName)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if let email = customer.email, !email.isEmpty {
                Label(email, systemImage: "envelope")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
            if let phone = customer.mobile ?? customer.phone, !phone.isEmpty {
                Label(PhoneFormatter.format(phone), systemImage: "phone")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
            if let org = customer.organization, !org.isEmpty {
                Label(org, systemImage: "building.2")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let tickets = customer.ticketCount {
                Label("\(tickets) ticket\(tickets == 1 ? "" : "s")", systemImage: "ticket")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.base)
        .frame(minWidth: 220)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

private struct CustomerRow: View {
    let customer: CustomerSummary

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreOrangeContainer)
                Text(customer.initials)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(customer.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let line = customer.contactLine {
                    Text(line)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: BrandSpacing.sm)

            if let count = customer.ticketCount, count > 0 {
                TicketCountBadge(count: count)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            RowAccessibilityFormatter.customerRow(
                name: customer.displayName,
                phone: customer.phone ?? customer.mobile,
                openTicketCount: customer.ticketCount ?? 0,
                ltvCents: nil,
                lastVisitAt: nil
            )
        )
        .accessibilityHint(RowAccessibilityFormatter.customerRowHint)
        .accessibilityAddTraits(.isButton)
    }
}

/// Compact pill — single-value chip instead of stacked 20pt + 13pt pair
/// so count + label sit tight and the row stays horizontal.
private struct TicketCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Text("\(count)")
                .monospacedDigit()
            Text(count == 1 ? "ticket" : "tickets")
        }
        .font(.brandLabelSmall())
        .foregroundStyle(.bizarreOnSurfaceMuted)
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
        .accessibilityLabel("\(count) \(count == 1 ? "ticket" : "tickets")")
    }
}

// MARK: - §5.4 Concurrent-edit conflict banner

private struct ConflictBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Someone else edited this record. Refresh to see latest changes.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Concurrent edit conflict. Someone else edited this record.")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - §5.1 Undo Toast

private struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: 0)
            Button("Undo", action: onUndo)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). Double tap to undo.")
    }
}

// MARK: - §5.1 Empty state

private struct CustomerEmptyState: View {
    let isSearching: Bool
    let query: String
    let onCreate: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: isSearching ? "magnifyingglass" : "person.2")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text(title)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)

            if !isSearching {
                Text("Add your first customer or import from your device contacts.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)

                HStack(spacing: BrandSpacing.md) {
                    Button(action: onCreate) {
                        Label("Create", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Create new customer")

                    Button(action: onImport) {
                        Label("Import", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Import customers from Contacts")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if isSearching {
            return query.isEmpty ? "No results" : "No results for \u{201C}\(query)\u{201D}"
        }
        return "No customers yet"
    }
}

// MARK: - §5.1 Contact Picker (Import from Contacts)

/// Wraps `CNContactPickerViewController` for SwiftUI.
private struct ContactPickerView: UIViewControllerRepresentable {
    let onSelect: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForSelectionOfProperty = nil
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([CNContact]) -> Void
        init(onSelect: @escaping ([CNContact]) -> Void) { self.onSelect = onSelect }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(contacts)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect([contact])
        }
    }
}

// MARK: - Empty / Error / Placeholder

private struct CustomerErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load customers")
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

private struct EmptyDetailPlaceholder: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select a customer")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Pick someone from the list to see their profile.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
        }
    }
}
#endif
