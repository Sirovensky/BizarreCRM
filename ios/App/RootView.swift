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

struct RootView: View {
    @Environment(AppState.self) private var appState

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
                PINUnlockView(onUnlock: {
                    appState.phase = .authenticated
                })
            case .authenticated:
                MainShellView(onSignOut: {
                    appState.phase = .unauthenticated
                })
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
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        if Platform.isCompact {
            iPhoneTabs(selection: $selectedTab, onSignOut: onSignOut)
        } else {
            iPadSplit(selection: $selectedTab, onSignOut: onSignOut)
        }
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
            DashboardView(repo: DashboardRepositoryImpl(api: AppServices.shared.apiClient))
                .tabItem { Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage) }
                .tag(MainTab.dashboard)

            TicketListView(repo: TicketRepositoryImpl(api: AppServices.shared.apiClient))
                .tabItem { Label(MainTab.tickets.title, systemImage: MainTab.tickets.systemImage) }
                .tag(MainTab.tickets)

            CustomerListView(
                repo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                detailRepo: CustomerDetailRepositoryImpl(api: AppServices.shared.apiClient)
            )
                .tabItem { Label(MainTab.customers.title, systemImage: MainTab.customers.systemImage) }
                .tag(MainTab.customers)

            PosView()
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

private struct iPadSplit: View {
    @Binding var selection: MainTab
    var onSignOut: (() -> Void)? = nil

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<MainTab?>(
                get: { selection },
                set: { if let new = $0 { selection = new } }
            )) {
                ForEach(MainTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                }
            }
            .navigationTitle("Bizarre CRM")
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            switch selection {
            case .dashboard: DashboardView(repo: DashboardRepositoryImpl(api: AppServices.shared.apiClient))
            case .tickets:   TicketListView(repo: TicketRepositoryImpl(api: AppServices.shared.apiClient))
            case .customers: CustomerListView(
                repo: CustomerRepositoryImpl(api: AppServices.shared.apiClient),
                detailRepo: CustomerDetailRepositoryImpl(api: AppServices.shared.apiClient)
            )
            case .pos:       PosView()
            case .more:      MoreMenuView(onSignOut: onSignOut)
            case .search:    GlobalSearchView(api: AppServices.shared.apiClient)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
                            detailRepo: InventoryDetailRepositoryImpl(api: AppServices.shared.apiClient)
                        )
                    }
                    NavigationLink("Invoices") {
                        InvoiceListView(
                            repo: InvoiceRepositoryImpl(api: AppServices.shared.apiClient),
                            detailRepo: InvoiceDetailRepositoryImpl(api: AppServices.shared.apiClient)
                        )
                    }
                    NavigationLink("Estimates") { EstimateListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Leads") { LeadListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Appointments") { AppointmentListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Expenses") { ExpenseListView(api: AppServices.shared.apiClient) }
                    NavigationLink("Reports") { ReportsView() }
                }
                Section("People") {
                    NavigationLink("Employees") { EmployeeListView(api: AppServices.shared.apiClient) }
                    NavigationLink("SMS") {
                        SmsListView(
                            repo: SmsRepositoryImpl(api: AppServices.shared.apiClient),
                            threadRepo: SmsThreadRepositoryImpl(api: AppServices.shared.apiClient)
                        )
                    }
                    NavigationLink("Notifications") { NotificationListView(api: AppServices.shared.apiClient) }
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
