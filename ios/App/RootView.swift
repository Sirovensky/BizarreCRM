import SwiftUI
import Core
import DesignSystem
import Networking
import Persistence
import Auth
import Dashboard
import Tickets
import Customers
import Inventory
import Invoices
import Estimates
import Leads
import Appointments
import Expenses
import Pos
import Communications
import Reports
import Settings
import Notifications
import Employees
import Search
import Voice
import CommandPalette
import AuditLogs
import Marketing
import Setup
import DataImport
import DataExport
import KioskMode
import RolesEditor
import RepairPricing
import Hardware

struct RootView: View {
    @Environment(AppState.self) private var appState
    /// §28.8 — tracks whether the app is inactive / backgrounded so we can
    /// overlay a branded blur before the system takes an App Switcher snapshot.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                LaunchView()
                    .task { await bootstrap() }
            case .unauthenticated:
                LoginFlowView(api: AppServices.shared.apiClient, onFinished: {
                    appState.phase = .authenticated
                })
            case .locked:
                PINUnlockView(
                    onUnlock: {
                        appState.phase = .authenticated
                    },
                    onRevoked: {
                        // PIN blown past max failures OR the user tapped
                        // "Sign in with password instead". Either way we
                        // wipe the session and drop to full login so they
                        // can re-enroll a new PIN after re-authenticating.
                        TokenStore.shared.clear()
                        PINStore.shared.reset()
                        Task { await AppServices.shared.apiClient.setAuthToken(nil) }
                        appState.phase = .unauthenticated
                    }
                )
            case .authenticated:
                MainShellView(onSignOut: {
                    appState.phase = .unauthenticated
                })
                .overlay(alignment: .topTrailing) { ConnectivityChip() }
                .posTheme(override: nil)
            }
        }
        // §28.8 Privacy snapshot — overlay a branded blur while the app is
        // inactive so the App Switcher thumbnail never reveals sensitive data.
        // Removed immediately when the app becomes active again.
        .overlay {
            if scenePhase != .active {
                PrivacySnapshotOverlay()
            }
        }
        .task { await listenForSessionEvents() }
    }

    private func bootstrap() async {
        await SessionBootstrapper.resolveInitialPhase(into: appState)
    }

    /// Watches for server-signalled session revocations (401 on authenticated
    /// calls) and kicks the user back to login. Runs for the RootView
    /// lifetime (always mounted).
    private func listenForSessionEvents() async {
        for await event in SessionEvents.stream {
            switch event {
            case .sessionRevoked:
                TokenStore.shared.clear()
                await AppServices.shared.apiClient.setAuthToken(nil)
                if appState.phase != .unauthenticated {
                    appState.phase = .unauthenticated
                }
            }
        }
    }
}

// MARK: - §28.8 Privacy snapshot overlay

/// Branded blur shown while the app is inactive (App Switcher, system overlays).
///
/// The system captures the app snapshot when `scenePhase` transitions from
/// `.active` to `.inactive`. By overlaying this view before that snapshot is
/// taken, no sensitive data appears in the App Switcher.
///
/// Customer-facing display (kiosk) intentionally opts out — kiosk content is
/// already meant to be public-facing and the overlay would confuse customers.
private struct PrivacySnapshotOverlay: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image("BrandMark")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 56, height: 56)
                Text("BizarreCRM")
                    .font(.system(.title2, design: .default).bold())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .transition(.opacity)
        .accessibilityHidden(true) // decorative only; app is inactive
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: .bsMd) {
                Image("BrandMark")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 72, height: 72)
                ProgressView()
                    .tint(.bizarreOrange)
            }
        }
    }
}

struct MainShellView: View {
    @State private var selectedTab: MainTab = .dashboard
    /// §22.G — iPad rail destination. Kept separate from `selectedTab` so the
    /// iPhone `TabView` and iPad rail each own their own selection state without
    /// needing a lossy conversion on every switch.
    @State private var railDestination: RailDestination = .dashboard
    @State private var showCmdPalette: Bool = false
    /// §23 — ⌘/ toggles the keyboard shortcut cheat-sheet overlay.
    @State private var showShortcutOverlay: Bool = false
    /// §23 — hardware keyboard detector; drives ShortcutHintPill visibility.
    @State private var keyboardDetector = HardwareKeyboardDetector()
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if Platform.isCompact {
                iPhoneTabs(selection: $selectedTab, onSignOut: onSignOut)
            } else {
                iPadShell(destination: $railDestination, onSignOut: onSignOut)
            }

            // §52.1 — ⌘K opens Command Palette on iPad/Mac. Hidden button
            // so the shortcut works anywhere in the app shell regardless
            // of which tab is active.
            Button { showCmdPalette.toggle() } label: { EmptyView() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // §23 — ⌘/ opens the keyboard shortcut overlay.
            Button { showShortcutOverlay.toggle() } label: { EmptyView() }
                .keyboardShortcut("/", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // §23 — Navigation shortcuts ⌘1–⌘6. Hidden buttons placed
            // in the ZStack so they're active on every tab.
            navShortcutButtons

            // §23 — ShortcutHintPill when hardware keyboard is attached.
            if keyboardDetector.isAttached && !showShortcutOverlay {
                VStack {
                    Spacer()
                    ShortcutHintPill { showShortcutOverlay = true }
                        .padding(.bottom, BrandSpacing.lg)
                }
                .allowsHitTesting(true)
                .transition(.opacity)
                .animation(BrandMotion.offlineBanner, value: keyboardDetector.isAttached)
            }
        }
        .sheet(isPresented: $showCmdPalette) {
            CommandPaletteView(viewModel: makeCmdPaletteVM())
        }
        // §23 — Shortcut overlay as a full-screen cover so it layers above
        // tab bars and navigation chrome.
        .fullScreenCover(isPresented: $showShortcutOverlay) {
            KeyboardShortcutOverlayView { showShortcutOverlay = false }
                .background(.clear)
        }
    }

    /// Hidden buttons that wire ⌘1–⌘8 to navigation.
    /// On iPhone they drive `selectedTab`; on iPad they drive `railDestination`.
    @ViewBuilder
    private var navShortcutButtons: some View {
        Group {
            Button {
                selectedTab = .dashboard
                railDestination = .dashboard
            } label: { EmptyView() }
                .keyboardShortcut("1", modifiers: .command)
            Button {
                selectedTab = .tickets
                railDestination = .tickets
            } label: { EmptyView() }
                .keyboardShortcut("2", modifiers: .command)
            Button {
                selectedTab = .customers
                railDestination = .customers
            } label: { EmptyView() }
                .keyboardShortcut("3", modifiers: .command)
            Button {
                selectedTab = .pos
                railDestination = .pos
            } label: { EmptyView() }
                .keyboardShortcut("4", modifiers: .command)
            Button {
                selectedTab = .more
                railDestination = .inventory
            } label: { EmptyView() }
                .keyboardShortcut("5", modifiers: .command)
            Button {
                selectedTab = .search
                railDestination = .sms
            } label: { EmptyView() }
                .keyboardShortcut("6", modifiers: .command)
            Button { railDestination = .reports  } label: { EmptyView() }
                .keyboardShortcut("7", modifiers: .command)
            Button { railDestination = .settings } label: { EmptyView() }
                .keyboardShortcut("8", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Build a fresh VM each time sheet opens so recent-usage state stays fresh.
    private func makeCmdPaletteVM() -> CommandPaletteViewModel {
        let actions = CommandCatalog.defaultActions(
            newTicket:         { Task { @MainActor in selectedTab = .tickets;  self.railDestination = .tickets;  self.showCmdPalette = false } },
            newCustomer:       { Task { @MainActor in selectedTab = .customers; self.railDestination = .customers; self.showCmdPalette = false } },
            findCustomerPhone: { Task { @MainActor in selectedTab = .customers; self.railDestination = .customers; self.showCmdPalette = false } },
            findCustomerName:  { Task { @MainActor in selectedTab = .customers; self.railDestination = .customers; self.showCmdPalette = false } },
            openDashboard:     { Task { @MainActor in selectedTab = .dashboard; self.railDestination = .dashboard; self.showCmdPalette = false } },
            openPOS:           { Task { @MainActor in selectedTab = .pos;       self.railDestination = .pos;       self.showCmdPalette = false } },
            clockIn:           { Task { @MainActor in selectedTab = .dashboard; self.railDestination = .dashboard; self.showCmdPalette = false } },
            clockOut:          { Task { @MainActor in selectedTab = .dashboard; self.railDestination = .dashboard; self.showCmdPalette = false } },
            openTickets:       { Task { @MainActor in selectedTab = .tickets;   self.railDestination = .tickets;   self.showCmdPalette = false } },
            openInventory:     { Task { @MainActor in selectedTab = .more;      self.railDestination = .inventory;  self.showCmdPalette = false } },
            settingsTax:       { Task { @MainActor in selectedTab = .more;      self.railDestination = .settings;  self.showCmdPalette = false } },
            settingsHours:     { Task { @MainActor in selectedTab = .more;      self.railDestination = .settings;  self.showCmdPalette = false } },
            reportsRevenue:    { Task { @MainActor in selectedTab = .more;      self.railDestination = .reports;   self.showCmdPalette = false } },
            sendSMS:           { Task { @MainActor in selectedTab = .more;      self.railDestination = .sms;       self.showCmdPalette = false } },
            signOut:           { Task { @MainActor [onSignOut] in self.showCmdPalette = false; onSignOut?() } }
        )
        return CommandPaletteViewModel(actions: actions, context: .none)
    }
}

enum MainTab: Hashable, CaseIterable, Identifiable {
    case dashboard, tickets, customers, pos, more, search
    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .tickets:   return "Tickets"
        case .customers: return "Customers"
        case .pos:       return "POS"
        case .more:      return "More"
        case .search:    return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house"
        case .tickets:   return "wrench.and.screwdriver"
        case .customers: return "person.2"
        case .pos:       return "cart"
        case .more:      return "square.grid.2x2"
        case .search:    return "magnifyingglass"
        }
    }
}

private struct iPhoneTabs: View {
    @Binding var selection: MainTab
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(repo: DashboardRepositoryImpl(api: AppServices.shared.apiClient), api: AppServices.shared.apiClient)
                .tabItem { Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage) }
                .tag(MainTab.dashboard)

            TicketListView(
                repo: TicketRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient,
                customerRepo: CustomerRepositoryImpl(api: AppServices.shared.apiClient)
            )
                .tabItem { Label(MainTab.tickets.title, systemImage: MainTab.tickets.systemImage) }
                .tag(MainTab.tickets)

            CustomerListView(
                repo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                detailRepo: CustomerDetailRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient
            )
                .tabItem { Label(MainTab.customers.title, systemImage: MainTab.customers.systemImage) }
                .tag(MainTab.customers)

            PosView(repo: InventoryRepositoryImpl(api: AppServices.shared.apiClient),
                    api: AppServices.shared.apiClient,
                    customerRepo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                    cashDrawerOpen: { try await AppServices.shared.cashDrawer.open() })
                .tabItem { Label(MainTab.pos.title, systemImage: MainTab.pos.systemImage) }
                .tag(MainTab.pos)

            MoreMenuView(onSignOut: onSignOut)
                .tabItem { Label(MainTab.more.title, systemImage: MainTab.more.systemImage) }
                .tag(MainTab.more)

            GlobalSearchView(api: AppServices.shared.apiClient)
                .tabItem { Label(MainTab.search.title, systemImage: MainTab.search.systemImage) }
                .tag(MainTab.search)
        }
    }
}

/// §22.G — iPad shell using the custom 64pt rail (`ShellLayout`) instead of the
/// system `NavigationSplitView` sidebar. The rail owns primary navigation; the
/// detail column hosts the selected destination's view.
///
/// The iPhone `iPhoneTabs` struct is unchanged — `ShellLayout` falls through
/// to the compact-content closure on narrow size classes, so even if this view
/// were ever placed on iPhone the behaviour would degrade gracefully.
private struct iPadShell: View {
    @Binding var destination: RailDestination
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        ShellLayout(selection: $destination) { dest in
            detailView(for: dest)
        } compactContent: {
            // Compact fallback — `MainShellView` already gates on
            // `Platform.isCompact` so this branch is never reached in
            // production. Providing it keeps the ShellLayout contract.
            iPhoneTabs(
                selection: .constant(.dashboard),
                onSignOut: onSignOut
            )
        }
    }

    @ViewBuilder
    private func detailView(for dest: RailDestination) -> some View {
        switch dest {
        case .dashboard:
            DashboardView(
                repo: DashboardRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient
            )

        case .tickets:
            TicketListView(
                repo: TicketRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient,
                customerRepo: CustomerRepositoryImpl(api: AppServices.shared.apiClient)
            )

        case .customers:
            CustomerListView(
                repo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                detailRepo: CustomerDetailRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient
            )

        case .pos:
            PosView(
                repo: InventoryRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient,
                customerRepo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                cashDrawerOpen: { try await AppServices.shared.cashDrawer.open() }
            )

        case .inventory:
            InventoryListView(
                repo: InventoryRepositoryImpl(api: AppServices.shared.apiClient),
                detailRepo: InventoryDetailRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient
            )

        case .sms:
            SmsListView(
                repo: SmsRepositoryImpl(api: AppServices.shared.apiClient),
                threadRepo: SmsThreadRepositoryImpl(api: AppServices.shared.apiClient),
                api: AppServices.shared.apiClient
            )

        case .reports:
            ReportsView(repository: LiveReportsRepository(api: AppServices.shared.apiClient))

        case .settings:
            SettingsView(onSignOut: onSignOut)
        }
    }
}

struct MoreMenuView: View {
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Operations") {
                    NavigationLink("Inventory") {
                        InventoryListView(
                            repo: InventoryRepositoryImpl(api: AppServices.shared.apiClient),
                            detailRepo: InventoryDetailRepositoryImpl(api: AppServices.shared.apiClient),
                            api: AppServices.shared.apiClient
                        )
                    }
                    NavigationLink("Invoices") {
                        InvoiceListView(
                            repo: InvoiceRepositoryImpl(api: AppServices.shared.apiClient),
                            detailRepo: InvoiceDetailRepositoryImpl(api: AppServices.shared.apiClient),
                            api: AppServices.shared.apiClient
                        )
                    }
                    NavigationLink("Estimates") { EstimateListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Leads") { LeadListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Appointments") { AppointmentListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Expenses") { ExpenseListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Payment links") { PaymentLinksListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Marketing") { CampaignListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Reports") {
                        ReportsView(repository: LiveReportsRepository(api: AppServices.shared.apiClient))
                    }
                }
                Section("Admin") {
                    NavigationLink("Audit Logs") {
                        AuditLogListView(api: AppServices.shared.apiClient)
                    }
                    NavigationLink("Roles Matrix") {
                        Group {
                            if Platform.isCompact {
                                RoleListView(viewModel: RolesMatrixViewModel(
                                    repository: RolesRepositoryLive(api: AppServices.shared.apiClient)))
                            } else {
                                RolesMatrixView(viewModel: RolesMatrixViewModel(
                                    repository: RolesRepositoryLive(api: AppServices.shared.apiClient)))
                            }
                        }
                    }
                    NavigationLink("Data Import") {
                        DataImportView(repository: LiveImportRepository(api: AppServices.shared.apiClient))
                    }
                    NavigationLink("Data Export") {
                        DataExportSettingsView(viewModel: DataExportViewModel(
                            repository: LiveExportRepository(api: AppServices.shared.apiClient)))
                    }
                    NavigationLink("Price Overrides") {
                        PriceOverrideListView(api: AppServices.shared.apiClient)
                    }
                    NavigationLink("Device Templates") {
                        DeviceTemplateListView(api: AppServices.shared.apiClient)
                    }
                    NavigationLink("Kiosk Mode") {
                        KioskModeSettingsView(manager: KioskModeManager())
                    }
                    NavigationLink("Setup Wizard") {
                        SetupWizardView(repository: SetupRepositoryLive(api: AppServices.shared.apiClient))
                    }
                }
                Section("People") {
                    NavigationLink("Employees") { EmployeeListView(api: AppServices.shared.apiClient) }
                    NavigationLink("SMS") {
                        SmsListView(
                            repo: SmsRepositoryImpl(api: AppServices.shared.apiClient),
                            threadRepo: SmsThreadRepositoryImpl(api: AppServices.shared.apiClient),
                            api: AppServices.shared.apiClient
                        )
                    }
                    NavigationLink("Notifications") { NotificationListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Calls") { CallLogView(api: AppServices.shared.apiClient) }
                    NavigationLink("Voicemail") { VoicemailListView(api: AppServices.shared.apiClient) }
                }
                Section {
                    NavigationLink("Settings") {
                        SettingsView(onSignOut: onSignOut)
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

/// Reactive chip rendered over the authenticated shell. Two-phase UI:
///
/// 1. **Expanded** (first ~3.5 s after state enters a visible mode) — full
///    glass chip with icon + text. Grabs attention.
/// 2. **Compact** (after the grace window) — icon-only circle tucked in the
///    top-trailing corner. Tap to re-expand for 4 more seconds.
///
/// Uses `.overlay(alignment: .topTrailing)` at the call site so the chip is
/// floating chrome and never pushes surrounding layout — important because
/// the `MainShellView` is a `NavigationSplitView` on iPad and a top-center
/// overlay would collide with per-column nav bars.
///
/// Polls `Reachability.shared` + `SyncQueueStore.shared` every 2 s. Both are
/// actor/observable; polling is cheap and avoids a Combine pipeline for a
/// tiny chip.
private struct ConnectivityChip: View {
    @State private var isOffline: Bool = false
    @State private var pendingCount: Int = 0
    @State private var expanded: Bool = true
    /// Monotonic task generation so we can cancel an in-flight collapse when
    /// the user taps to re-expand without racing with an old timer.
    @State private var collapseTaskId: Int = 0

    private var isVisible: Bool { isOffline || pendingCount > 0 }

    var body: some View {
        Group {
            if isVisible {
                OfflineBanner(
                    isOffline: isOffline,
                    pendingCount: pendingCount,
                    expanded: expanded
                )
                .contentShape(Rectangle())
                .onTapGesture { reExpand() }
            }
        }
        .padding(.top, BrandSpacing.sm)
        .padding(.trailing, BrandSpacing.base)
        .task { await monitor() }
    }

    private func reExpand() {
        expanded = true
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTaskId &+= 1
        let id = collapseTaskId
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard id == collapseTaskId else { return }
            expanded = false
        }
    }

    /// Watch Reachability + SyncQueueStore. Kick off the monitor defensively —
    /// `start()` is idempotent, so the extra call only matters if the bootstrap
    /// path somehow failed to warm it up before the authenticated shell
    /// mounted.
    private func monitor() async {
        Reachability.shared.startIfNeeded()
        var wasVisible = false
        while !Task.isCancelled {
            isOffline = !Reachability.shared.isOnline
            pendingCount = (try? await SyncQueueStore.shared.pendingCount()) ?? 0
            let nowVisible = isOffline || pendingCount > 0
            if nowVisible && !wasVisible {
                // Transitioned from hidden → visible: show expanded, start
                // collapse timer. Matches the "grab attention, then tuck"
                // pattern the user asked for.
                expanded = true
                scheduleCollapse()
            }
            wasVisible = nowVisible
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}
