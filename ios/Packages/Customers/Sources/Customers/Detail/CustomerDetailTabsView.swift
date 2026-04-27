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

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                // §5.2 Health score ring — tap → explanation sheet
                healthScoreRing

                // §5.2 LTV tier chip — tap → explanation
                ltvTierChip

                // Quick-action glass row
                CustomerQuickActionRow(detail: detail, api: api)

                // Contact info
                InfoContactCard(detail: detail)

                // Balance / credit §5.2
                CustomerBalanceCard(customerId: detail.id, api: api)
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

    // MARK: Health score ring

    private var healthScoreRing: some View {
        let health = CustomerHealthScoreResult.compute(detail: detail)
        return Button {
            showingHealthSheet = true
        } label: {
            HStack(spacing: BrandSpacing.md) {
                HealthRing(score: health.value, tier: health.tier)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(tierLabel(health.tier))
                        .font(.brandTitleSmall())
                        .foregroundStyle(tierColor(health.tier))
                    Text("Health Score")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    if let rec = health.recommendation {
                        Text(rec)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Health score \(health.value) of 100. \(tierLabel(health.tier)). Tap for breakdown.")
    }

    // MARK: LTV tier chip

    private var ltvTierChip: some View {
        let ltvCentsInt: Int = {
            if let a = analytics, a.lifetimeValue > 0 { return Int(a.lifetimeValue * 100) }
            if let c = detail.ltvCents, c > 0 { return Int(c) }
            return 0
        }()
        let tier = LTVCalculator.tier(for: ltvCentsInt)
        let formatted = currencyString(Double(ltvCentsInt) / 100.0)

        return Button {
            showingLTVSheet = true
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tier.icon)
                    .foregroundStyle(tier.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LTV: \(formatted)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("\(tier.label) tier")
                        .font(.brandLabelSmall())
                        .foregroundStyle(tier.color)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tier.color.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lifetime value \(formatted). \(tier.label) tier. Tap for details.")
    }

    private func tierLabel(_ t: CustomerHealthTier) -> String {
        switch t { case .green: return "Healthy"; case .yellow: return "At Risk"; case .red: return "Critical" }
    }
    private func tierColor(_ t: CustomerHealthTier) -> Color {
        switch t { case .green: return .bizarreSuccess; case .yellow: return .bizarreWarning; case .red: return .bizarreError }
    }
    private func currencyString(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - HealthRing subview

private struct HealthRing: View {
    let score: Int
    let tier: CustomerHealthTier

    private var color: Color {
        switch tier { case .green: return .bizarreSuccess; case .yellow: return .bizarreWarning; case .red: return .bizarreError }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: score)
            Text("\(score)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
    }
}

// MARK: - Info Contact Card

private struct InfoContactCard: View {
    let detail: CustomerDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Contact").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            if let m = detail.mobile, !m.isEmpty { row("phone", "Mobile", PhoneFormatter.format(m), mono: true) }
            if let p = detail.phone, !p.isEmpty, p != detail.mobile { row("phone", "Phone", PhoneFormatter.format(p), mono: true) }
            if let e = detail.email, !e.isEmpty { row("envelope", "Email", e) }
            if let addr = detail.addressLine { row("mappin.and.ellipse", "Address", addr) }
            if let org = detail.organization, !org.isEmpty { row("building.2", "Organization", org) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func row(_ icon: String, _ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon).foregroundStyle(.bizarreOnSurfaceMuted).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(mono ? .brandMono(size: 14) : .brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

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

// MARK: - Assets Tab (wraps existing CustomerAssetsListView)

public struct CustomerAssetsTabView: View {
    let customerId: Int64
    let api: APIClient

    public var body: some View {
        CustomerAssetsListView(api: api, customerId: customerId)
    }
}
#endif
