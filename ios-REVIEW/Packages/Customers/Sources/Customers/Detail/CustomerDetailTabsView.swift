#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.2 Customer detail Tabs (Info / Tickets / Invoices / Communications / Assets)

/// Five-tab customer detail view.
/// iPhone: `TabView` with `.tabViewStyle(.page)` to allow swipe-between.
/// iPad: `TabView` with `.tabViewStyle(.tabBar)` — full sidebar is the outer navigator.
public struct CustomerDetailTabsView: View {
    @State private var selectedTab: CustomerDetailTab = .info
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?
    let api: APIClient

    public init(detail: CustomerDetail, analytics: CustomerAnalytics?, api: APIClient) {
        self.detail = detail
        self.analytics = analytics
        self.api = api
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            CustomerInfoTabView(detail: detail, analytics: analytics, api: api)
                .tag(CustomerDetailTab.info)
                .tabItem { Label("Info", systemImage: "person.crop.circle") }

            CustomerTicketsTabView(customerId: detail.id, api: api)
                .tag(CustomerDetailTab.tickets)
                .tabItem { Label("Tickets", systemImage: "ticket") }

            CustomerInvoicesTabView(customerId: detail.id, api: api)
                .tag(CustomerDetailTab.invoices)
                .tabItem { Label("Invoices", systemImage: "doc.text") }

            CustomerCommsTabView(customerId: detail.id, api: api)
                .tag(CustomerDetailTab.communications)
                .tabItem { Label("Comms", systemImage: "message") }

            CustomerAssetsTabView(customerId: detail.id, api: api)
                .tag(CustomerDetailTab.assets)
                .tabItem { Label("Assets", systemImage: "iphone") }
        }
        .tint(.bizarreOrange)
        .accessibilityLabel("Customer detail sections")
    }
}

// MARK: - Tab enum

public enum CustomerDetailTab: String, CaseIterable, Sendable {
    case info
    case tickets
    case invoices
    case communications
    case assets
}

// MARK: - Info Tab

public struct CustomerInfoTabView: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?
    let api: APIClient
    @State private var showingHealthSheet = false
    @State private var showingLTVSheet = false
    @State private var showingDelete = false
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                // §5.2 Header — avatar + name + LTV tier chip + health-score ring + VIP star
                CustomerDetailHeader(
                    detail: detail,
                    analytics: analytics,
                    api: api,
                    onHealthTap: { showingHealthSheet = true },
                    onLTVTap: { showingLTVSheet = true }
                )

                // Quick-action glass row
                CustomerQuickActionRow(detail: detail, api: api)

                // §5 Birthday gift reminder chip (visible ≤14 days before birthday)
                BirthdayGiftReminderChip(detail: detail, api: api)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // §5 Anniversary chip (visible ≤7 days before customer anniversary)
                CustomerAnniversaryChip(createdAt: detail.createdAt)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // §5 Lifetime-spend card (LTV formatted with percentile tier badge)
                CustomerLifetimeSpendCard(detail: detail, analytics: analytics)

                // §5.2 Contact card — multi-phone, multi-email, address→Maps
                CustomerFullContactCard(detail: detail, onMapsTap: nil)

                // §5 Marketing-channel preference row (reads comm prefs; taps → edit sheet)
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    Text("Preferences")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    MarketingChannelPreferenceRow(customerId: detail.id, api: api)

                    // §5 Customer-portal magic-link copy chip
                    HStack {
                        Text("Self-service portal")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer(minLength: 0)
                        CustomerPortalMagicLinkCopy(customerId: detail.id, api: api)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BrandSpacing.base)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))

                // §5.2 Membership card (shown only if tenant has memberships)
                CustomerMembershipCard(customerId: detail.id, api: api)

                // Balance / credit §5.2
                CustomerBalanceCard(customerId: detail.id, api: api)

                // §5.2 vCard actions — Share + Add to Contacts
                CustomerVCardActions(detail: detail)

                // §5.2 Delete customer
                CustomerDeleteButton(
                    customerId: detail.id,
                    displayName: detail.displayName,
                    openTicketCount: detail.openTicketCount ?? 0,
                    api: api,
                    onDeleted: { dismiss() }
                )
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showingHealthSheet) {
            CustomerHealthExplainerSheet(detail: detail, analytics: analytics, api: api)
        }
        .sheet(isPresented: $showingLTVSheet) {
            CustomerLTVExplainerSheet(detail: detail, analytics: analytics)
        }
    }

}

// HealthRing and InfoContactCard replaced by CustomerDetailHeader + CustomerFullContactCard
// (see Detail/CustomerDetailHeader.swift)

// MARK: - Tickets Tab

public struct CustomerTicketsTabView: View {
    let customerId: Int64
    let api: APIClient
    @State private var tickets: [TicketSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    public var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let e = error {
                errorState(e)
            } else if tickets.isEmpty {
                emptyState("No tickets yet.")
            } else {
                List(tickets) { t in
                    TicketRow(ticket: t)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await loadTickets() }
        .refreshable { await loadTickets() }
    }

    private func loadTickets() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { tickets = try await api.customerRecentTickets(id: customerId, pageSize: 100) }
        catch { self.error = error.localizedDescription }
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(.bizarreError).accessibilityHidden(true)
            Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
            Button("Retry") { Task { await loadTickets() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "ticket").font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
            Text(text).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TicketRow: View {
    let ticket: TicketSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.orderId).font(.brandMono(size: 14)).foregroundStyle(.bizarreOnSurface)
                if let dev = ticket.firstDevice?.deviceName, !dev.isEmpty {
                    Text(dev).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                }
            }
            Spacer()
            if let s = ticket.status?.name {
                Text(s).font(.brandLabelSmall())
                    .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreSurface2, in: Capsule())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Invoices Tab

public struct CustomerInvoicesTabView: View {
    let customerId: Int64
    let api: APIClient
    @State private var invoices: [CustomerInvoiceSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    public var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let e = error {
                VStack(spacing: BrandSpacing.md) {
                    Text(e).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadInvoices() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if invoices.isEmpty {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "doc.text").font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                    Text("No invoices yet.").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(invoices) { inv in
                    InvoiceRow(invoice: inv)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await loadInvoices() }
        .refreshable { await loadInvoices() }
    }

    private func loadInvoices() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { invoices = try await api.customerInvoices(id: customerId) }
        catch { self.error = error.localizedDescription }
    }
}

private struct InvoiceRow: View {
    let invoice: CustomerInvoiceSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.invoiceNumber ?? "#\(invoice.id)").font(.brandMono(size: 14)).foregroundStyle(.bizarreOnSurface)
                if let date = invoice.issuedAt { Text(String(date.prefix(10))).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let total = invoice.totalCents {
                    Text(centsToString(total)).font(.brandTitleSmall()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                }
                if let status = invoice.status {
                    Text(status.capitalized).font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func centsToString(_ cents: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(Double(cents)/100.0)"
    }
}

// MARK: - Communications Tab

public struct CustomerCommsTabView: View {
    let customerId: Int64
    let api: APIClient
    @State private var comms: [CustomerCommEntry] = []
    @State private var isLoading = true
    @State private var error: String?

    public var body: some View {
        Group {
            if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let e = error {
                VStack(spacing: BrandSpacing.md) {
                    Text(e).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadComms() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comms.isEmpty {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "message").font(.system(size: 36)).foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                    Text("No communications yet.").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(comms) { entry in
                    CommRow(entry: entry)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await loadComms() }
        .refreshable { await loadComms() }
    }

    private func loadComms() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { comms = try await api.customerCommunications(id: customerId) }
        catch { self.error = error.localizedDescription }
    }
}

private struct CommRow: View {
    let entry: CustomerCommEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: entry.kind == "sms" ? "message.fill" : entry.kind == "email" ? "envelope.fill" : "phone.fill")
                .foregroundStyle(.bizarreOrange)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.body ?? "(no body)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if let date = entry.createdAt {
                    Text(String(date.prefix(16)))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Assets Tab (wraps CustomerAssetsListView via repository)

public struct CustomerAssetsTabView: View {
    let customerId: Int64
    let api: APIClient

    public var body: some View {
        // §5.2 Assets tab — GET /customers/:id/assets; add asset; tap → device-history.
        CustomerAssetsListView(
            repository: CustomerAssetsRepositoryImpl(api: api),
            customerId: customerId
        )
    }
}
#endif
