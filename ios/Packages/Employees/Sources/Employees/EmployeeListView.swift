import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class EmployeeListViewModel {
    public private(set) var items: [Employee] = []
    public private(set) var filteredItems: [Employee] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var lastSyncedAt: Date?

    public var filter: EmployeeListFilter = .init() {
        didSet { applyFilter() }
    }

    /// All distinct roles seen in the loaded data — used to populate the filter picker.
    public private(set) var availableRoles: [String] = []

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: EmployeeCachedRepository?

    public init(api: APIClient, cachedRepo: EmployeeCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            let activeItems: [Employee]
            if let repo = cachedRepo {
                activeItems = try await repo.listEmployees()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                activeItems = try await api.listEmployees()
            }
            let allItems: [Employee]
            if filter.showInactive {
                // /api/v1/settings/users returns ALL users including inactive (admin)
                let allUsers = try await api.listAllUsers()
                allItems = allUsers
            } else {
                allItems = activeItems
            }
            items = allItems
            availableRoles = Array(Set(allItems.compactMap { $0.role?.isEmpty == false ? $0.role : nil })).sorted()
            applyFilter()
        } catch {
            AppLog.ui.error("Employees load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            if let repo = cachedRepo {
                items = try await repo.forceRefresh()
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                items = try await api.listEmployees()
            }
            availableRoles = Array(Set(items.compactMap { $0.role?.isEmpty == false ? $0.role : nil })).sorted()
            applyFilter()
        } catch {
            AppLog.ui.error("Employees force-refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func applyFilter() {
        var result = items
        if let role = filter.role {
            result = result.filter { $0.role == role }
        }
        if let locationId = filter.locationId {
            // Employee.homeLocationId is not yet on the base Employee model;
            // we do a best-effort pass-through (no-op until the model adds it).
            _ = locationId
        }
        if !filter.showInactive {
            result = result.filter { $0.active }
        }
        if !filter.searchQuery.isEmpty {
            let q = filter.searchQuery.lowercased()
            result = result.filter {
                $0.displayName.lowercased().contains(q) ||
                ($0.email?.lowercased().contains(q) ?? false)
            }
        }
        filteredItems = result
    }
}

// MARK: - EmployeeListView

public struct EmployeeListView: View {
    @State private var vm: EmployeeListViewModel
    @State private var showCommissionRules: Bool = false
    @State private var showFilters: Bool = false
    @State private var selectedEmployee: Employee?
    private let api: APIClient

    public init(api: APIClient, cachedRepo: EmployeeCachedRepository? = nil) {
        self.api = api
        _vm = State(wrappedValue: EmployeeListViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        if Platform.isCompact {
            iPhoneLayout
        } else {
            iPadLayout
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Employees")
            .toolbar { toolbarItems }
            .sheet(isPresented: $showCommissionRules) {
                CommissionRulesListView(api: api)
            }
            .sheet(isPresented: $showFilters) {
                EmployeeFilterSheet(vm: vm)
            }
            .task { await vm.load() }
            .refreshable { await vm.forceRefresh() }
        }
    }

    // MARK: - iPad Layout (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                sidebarContent
            }
            .navigationTitle("Employees")
            .toolbar { toolbarItems }
            .sheet(isPresented: $showCommissionRules) {
                CommissionRulesListView(api: api)
            }
            .sheet(isPresented: $showFilters) {
                EmployeeFilterSheet(vm: vm)
            }
            .task { await vm.load() }
            .refreshable { await vm.forceRefresh() }
        } detail: {
            if let emp = selectedEmployee {
                EmployeeDetailView(
                    employeeId: emp.id,
                    displayName: emp.displayName,
                    api: api
                )
            } else {
                ContentUnavailableView(
                    "Select an employee",
                    systemImage: "person.crop.circle",
                    description: Text("Choose an employee from the list to view their details.")
                )
            }
        }
    }

    // MARK: - Content (iPhone)

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if vm.filteredItems.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "employees")
        } else if vm.filteredItems.isEmpty {
            emptyState
        } else {
            employeeList(selection: nil)
        }
    }

    // MARK: - Sidebar content (iPad)

    @ViewBuilder
    private var sidebarContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorState(err)
        } else if vm.filteredItems.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "employees")
        } else if vm.filteredItems.isEmpty {
            emptyState
        } else {
            employeeList(selection: $selectedEmployee)
        }
    }

    // MARK: - Employee list

    @ViewBuilder
    private func employeeList(selection: Binding<Employee?>?) -> some View {
        VStack(spacing: 0) {
            if !vm.filter.isDefault {
                activeFiltersBanner
            }
            if let sel = selection {
                List(vm.filteredItems, selection: sel) { emp in
                    Row(employee: emp)
                        .listRowBackground(Color.bizarreSurface1)
                        .hoverEffect(.highlight)
                        .contextMenu {
                            Button {
                                selectedEmployee = emp
                            } label: {
                                Label("View Details", systemImage: "person.crop.circle")
                            }
                        }
                        .tag(emp)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            } else {
                List(vm.filteredItems) { emp in
                    NavigationLink {
                        EmployeeDetailView(
                            employeeId: emp.id,
                            displayName: emp.displayName,
                            api: api
                        )
                    } label: {
                        Row(employee: emp)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Active filters banner

    private var activeFiltersBanner: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(filterSummary)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Button("Clear") {
                vm.filter = .init()
            }
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel("Clear all filters")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface1)
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let r = vm.filter.role { parts.append(r.capitalized) }
        if vm.filter.showInactive { parts.append("Including inactive") }
        if !vm.filter.searchQuery.isEmpty { parts.append("\"\(vm.filter.searchQuery)\"") }
        return parts.isEmpty ? "Filtered" : parts.joined(separator: " · ")
    }

    // MARK: - Empty / error states

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(vm.filter.isDefault ? "No employees" : "No matching employees")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if !vm.filter.isDefault {
                Button("Clear Filters") { vm.filter = .init() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load employees").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showCommissionRules = true
            } label: {
                Image(systemName: "percent")
            }
            .accessibilityLabel("Commission Rules (admin)")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showFilters = true
            } label: {
                Image(systemName: vm.filter.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(vm.filter.isDefault ? Color.primary : Color.bizarreOrange)
            }
            .accessibilityLabel(vm.filter.isDefault ? "Filter employees" : "Filters active")
            .keyboardShortcut("f", modifiers: [.command])
        }
        ToolbarItem(placement: .automatic) {
            StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
        }
    }

    // MARK: - Row

    private struct Row: View {
        let employee: Employee

        var body: some View {
            HStack(spacing: BrandSpacing.md) {
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(employee.initials)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(employee.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let role = employee.role, !role.isEmpty {
                        Text(role.capitalized)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let email = employee.email, !email.isEmpty {
                        Text(email)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if !employee.active {
                    Text("Inactive")
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .background(Color.bizarreSurface2, in: Capsule())
                }
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: employee))
        }

        static func a11y(for emp: Employee) -> String {
            var parts: [String] = [emp.displayName]
            if let role = emp.role, !role.isEmpty { parts.append(role.capitalized) }
            if !emp.active { parts.append("Inactive") }
            return parts.joined(separator: ". ")
        }
    }
}

// MARK: - EmployeeFilterSheet

struct EmployeeFilterSheet: View {
    @Bindable var vm: EmployeeListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Picker("Role", selection: $vm.filter.role) {
                        Text("All roles").tag(String?.none)
                        ForEach(vm.availableRoles, id: \.self) { role in
                            Text(role.capitalized).tag(Optional(role))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Filter by role")
                }

                Section("Status") {
                    Toggle("Show inactive employees", isOn: $vm.filter.showInactive)
                        .accessibilityLabel("Include inactive employees in list")
                }

                Section("Search") {
                    TextField("Name or email", text: $vm.filter.searchQuery)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Search employees by name or email")
                }
            }
            .navigationTitle("Filter Employees")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.return, modifiers: [])
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        vm.filter = .init()
                    }
                    .disabled(vm.filter.isDefault)
                    .accessibilityLabel("Clear all filters")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
