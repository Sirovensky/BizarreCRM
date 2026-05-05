#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// §22 — iPad 3-column Employees layout: role sidebar | list | detail + inspector
//
// Column 1 (sidebar)  — role filter list with Liquid Glass chrome
// Column 2 (content)  — searchable employee list with context menus
// Column 3 (detail)   — EmployeeDetailView + EmployeePerformanceInspector
//
// Gate: only instantiate when `!Platform.isCompact`.
// The existing EmployeeListView continues to own the compact (iPhone) path.

/// Full-width iPad layout for Employees.
///
/// Three-column `NavigationSplitView`:
/// 1. **Sidebar** — role filter list.
/// 2. **Content** — filtered, searchable employee list with context menus.
/// 3. **Detail** — `EmployeeDetailView` + trailing `EmployeePerformanceInspector`.
public struct EmployeesThreeColumnView: View {

    // MARK: - State

    @State private var vm: EmployeeListViewModel
    @State private var searchText: String = ""
    @State private var selectedRoleFilter: String? = nil
    @State private var selectedEmployee: Employee? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showFilters: Bool = false
    @State private var showCommissionRules: Bool = false
    @State private var pendingClockEmployee: Employee? = nil
    @State private var pendingDeactivateEmployee: Employee? = nil
    @State private var actionError: String? = nil
    @State private var showClockSheet: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: EmployeeCachedRepository?

    // MARK: - Init

    public init(api: APIClient, cachedRepo: EmployeeCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
        _vm = State(wrappedValue: EmployeeListViewModel(api: api, cachedRepo: cachedRepo))
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            roleSidebar
        } content: {
            employeeListColumn
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .modifier(EmployeeKeyboardShortcuts(
            onSearch:     { columnVisibility = .all; showFilters = true },
            onRefresh:    { Task { await vm.forceRefresh() } },
            onClockInOut: {
                if let emp = selectedEmployee {
                    pendingClockEmployee = emp
                    showClockSheet = true
                }
            },
            onDeactivate: {
                if let emp = selectedEmployee { pendingDeactivateEmployee = emp }
            }
        ))
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .sheet(isPresented: $showFilters) {
            EmployeeFilterSheet(vm: vm)
        }
        .sheet(isPresented: $showCommissionRules) {
            CommissionRulesListView(api: api)
        }
        // Clock In/Out sheet (PIN-gated via EmployeeClockInOutView)
        .sheet(isPresented: $showClockSheet) {
            if let emp = pendingClockEmployee {
                NavigationStack {
                    EmployeeClockInOutView(
                        vm: EmployeeClockViewModel(api: api, employeeId: emp.id)
                    )
                    .navigationTitle("Clock: \(emp.displayName)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showClockSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .onChange(of: showClockSheet) { _, visible in
            if !visible { pendingClockEmployee = nil }
        }
        // Deactivate / Reactivate confirmation
        .confirmationDialog(
            pendingDeactivateEmployee?.active == true ? "Deactivate Employee" : "Reactivate Employee",
            isPresented: Binding(
                get: { pendingDeactivateEmployee != nil },
                set: { if !$0 { pendingDeactivateEmployee = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let emp = pendingDeactivateEmployee {
                Button(
                    emp.active ? "Deactivate" : "Reactivate",
                    role: emp.active ? .destructive : .none
                ) {
                    Task { await performToggleActive(emp) }
                }
                Button("Cancel", role: .cancel) { pendingDeactivateEmployee = nil }
            }
        } message: {
            if let emp = pendingDeactivateEmployee {
                Text(
                    emp.active
                        ? "Deactivating \(emp.displayName) will prevent them from logging in."
                        : "Reactivate \(emp.displayName) so they can log in again?"
                )
            }
        }
        // Action error alert
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Column 1: Role Sidebar

    private var roleSidebar: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: 0) {
                offlineBannerIfNeeded
                List {
                    // "All Roles" row
                    RoleSidebarRow(
                        title: "All Employees",
                        icon: "person.3",
                        isSelected: selectedRoleFilter == nil
                    ) {
                        selectedRoleFilter = nil
                        applyRoleFilter(nil)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .hoverEffect(.highlight)

                    if !vm.availableRoles.isEmpty {
                        Section("Roles") {
                            ForEach(vm.availableRoles, id: \.self) { role in
                                RoleSidebarRow(
                                    title: role.capitalized,
                                    icon: "person.badge.key",
                                    isSelected: selectedRoleFilter == role
                                ) {
                                    selectedRoleFilter = role
                                    applyRoleFilter(role)
                                }
                                .listRowBackground(Color.bizarreSurface1)
                                .hoverEffect(.highlight)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Employees")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BrandGlassContainer {
                    Button {
                        showCommissionRules = true
                    } label: {
                        Image(systemName: "percent")
                    }
                    .accessibilityLabel("Commission rules (admin)")
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        }
    }

    // MARK: - Column 2: Employee List

    private var employeeListColumn: some View {
        ZStack(alignment: .top) {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            employeeListContent
        }
        .navigationTitle(selectedRoleFilter?.capitalized ?? "All Employees")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search employees")
        .onChange(of: searchText) { _, new in
            vm.filter = EmployeeListFilter(
                role: vm.filter.role,
                locationId: vm.filter.locationId,
                showInactive: vm.filter.showInactive,
                searchQuery: new
            )
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showFilters = true
                } label: {
                    Image(
                        systemName: vm.filter.isDefault
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                    .foregroundStyle(vm.filter.isDefault ? Color.primary : Color.bizarreOrange)
                }
                .accessibilityLabel(vm.filter.isDefault ? "Filter employees" : "Filters active")
                .keyboardShortcut("f", modifiers: .command)
            }
            ToolbarItem(placement: .status) {
                StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
            }
        }
    }

    @ViewBuilder
    private var employeeListContent: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading employees")
        } else if let err = vm.errorMessage {
            errorState(message: err)
        } else if vm.filteredItems.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "employees")
        } else if vm.filteredItems.isEmpty {
            emptyState
        } else {
            List(vm.filteredItems, selection: $selectedEmployee) { emp in
                EmployeeThreeColRow(employee: emp, isSelected: selectedEmployee?.id == emp.id)
                    .tag(emp)
                    .listRowBackground(
                        selectedEmployee?.id == emp.id
                            ? Color.bizarreOrange.opacity(0.12)
                            : Color.bizarreSurface1
                    )
                    .hoverEffect(.highlight)
                    .modifier(EmployeeContextMenu(
                        employee: emp,
                        availableRoles: [],
                        onOpen: { selectedEmployee = emp },
                        onAssignRole: { roleId in
                            await assignRole(emp, roleId: roleId)
                        },
                        onToggleActive: {
                            pendingDeactivateEmployee = emp
                        },
                        onToggleClock: {
                            pendingClockEmployee = emp
                            showClockSheet = true
                        }
                    ))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Column 3: Detail + Inspector

    @ViewBuilder
    private var detailPane: some View {
        if let emp = selectedEmployee {
            iPadDetailWithInspector(employee: emp)
        } else {
            emptyDetailPlaceholder
        }
    }

    private func iPadDetailWithInspector(employee: Employee) -> some View {
        HStack(spacing: 0) {
            EmployeeDetailView(
                employeeId: employee.id,
                displayName: employee.displayName,
                api: api
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            EmployeePerformanceInspector(employeeId: employee.id, api: api)
                .frame(width: 260)
        }
    }

    // MARK: - Helper views

    @ViewBuilder
    private var offlineBannerIfNeeded: some View {
        if !Reachability.shared.isOnline {
            OfflineBanner(isOffline: true)
        }
    }

    private var emptyDetailPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ContentUnavailableView(
                "Select an employee",
                systemImage: "person.crop.circle",
                description: Text("Choose an employee from the list to view their profile and metrics.")
            )
        }
    }

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
                    .accessibilityLabel("Clear all employee filters")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load employees")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Retry loading employees")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func applyRoleFilter(_ role: String?) {
        vm.filter = EmployeeListFilter(
            role: role,
            locationId: vm.filter.locationId,
            showInactive: vm.filter.showInactive,
            searchQuery: vm.filter.searchQuery
        )
    }

    /// Assigns a role to the given employee via the API. Shows an error alert on failure.
    private func assignRole(_ employee: Employee, roleId: Int) async {
        do {
            try await api.assignEmployeeRole(userId: employee.id, roleId: roleId)
            await vm.forceRefresh()
        } catch {
            AppLog.ui.error("Assign role failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    /// Toggles active flag for the given employee.
    private func performToggleActive(_ employee: Employee) async {
        pendingDeactivateEmployee = nil
        do {
            _ = try await api.setEmployeeActive(id: employee.id, isActive: !employee.active)
            await vm.forceRefresh()
        } catch {
            AppLog.ui.error("Toggle active failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

}

// MARK: - RoleSidebarRow

private struct RoleSidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)

                Spacer()
            }
            .padding(.vertical, BrandSpacing.xs)
            .frame(minHeight: DesignTokens.Touch.minTargetSide)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) filter")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - EmployeeThreeColRow

private struct EmployeeThreeColRow: View {
    let employee: Employee
    let isSelected: Bool

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                Text(employee.initials)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(employee.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                if let role = employee.role, !role.isEmpty {
                    Text(role.capitalized)
                        .font(.brandLabelSmall())
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
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .background(Color.bizarreSurface2, in: Capsule())
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var parts: [String] = [employee.displayName]
        if let role = employee.role, !role.isEmpty { parts.append(role.capitalized) }
        if let email = employee.email, !email.isEmpty { parts.append(email) }
        if !employee.active { parts.append("Inactive") }
        return parts.joined(separator: ". ")
    }
}

#endif
