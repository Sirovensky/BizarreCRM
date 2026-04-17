import SwiftUI
import Core
import DesignSystem
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
        switch appState.phase {
        case .launching:
            LaunchView()
                .task { await bootstrap() }
        case .unauthenticated:
            LoginFlowView()
        case .locked:
            PINUnlockView()
        case .authenticated:
            MainShellView()
        }
    }

    private func bootstrap() async {
        await SessionBootstrapper.resolveInitialPhase(into: appState)
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

    var body: some View {
        if Platform.isCompact {
            iPhoneTabs(selection: $selectedTab)
        } else {
            iPadSplit(selection: $selectedTab)
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

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage) }
                .tag(MainTab.dashboard)

            TicketListView()
                .tabItem { Label(MainTab.tickets.title, systemImage: MainTab.tickets.systemImage) }
                .tag(MainTab.tickets)

            CustomerListView()
                .tabItem { Label(MainTab.customers.title, systemImage: MainTab.customers.systemImage) }
                .tag(MainTab.customers)

            PosView()
                .tabItem { Label(MainTab.pos.title, systemImage: MainTab.pos.systemImage) }
                .tag(MainTab.pos)

            MoreMenuView()
                .tabItem { Label(MainTab.more.title, systemImage: MainTab.more.systemImage) }
                .tag(MainTab.more)

            GlobalSearchView()
                .tabItem { Label(MainTab.search.title, systemImage: MainTab.search.systemImage) }
                .tag(MainTab.search)
        }
    }
}

private struct iPadSplit: View {
    @Binding var selection: MainTab

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
        } detail: {
            switch selection {
            case .dashboard: DashboardView()
            case .tickets:   TicketListView()
            case .customers: CustomerListView()
            case .pos:       PosView()
            case .more:      MoreMenuView()
            case .search:    GlobalSearchView()
            }
        }
    }
}

struct MoreMenuView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Operations") {
                    NavigationLink("Inventory") { InventoryListView() }
                    NavigationLink("Invoices") { InvoiceListView() }
                    NavigationLink("Estimates") { EstimateListView() }
                    NavigationLink("Leads") { LeadListView() }
                    NavigationLink("Appointments") { AppointmentListView() }
                    NavigationLink("Expenses") { ExpenseListView() }
                    NavigationLink("Reports") { ReportsView() }
                }
                Section("People") {
                    NavigationLink("Employees") { EmployeeListView() }
                    NavigationLink("SMS") { SmsListView() }
                    NavigationLink("Notifications") { NotificationListView() }
                }
                Section {
                    NavigationLink("Settings") { SettingsView() }
                }
            }
            .navigationTitle("More")
        }
    }
}
