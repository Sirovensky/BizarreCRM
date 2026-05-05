#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct CustomerDetailView: View {
    @State private var vm: CustomerDetailViewModel
    @State private var showingEdit: Bool = false
    @State private var showingMerge: Bool = false
    @State private var showingTagEditor: Bool = false
    private let api: APIClient?

    public init(repo: CustomerDetailRepository, customerId: Int64, api: APIClient? = nil) {
        _vm = State(wrappedValue: CustomerDetailViewModel(repo: repo, customerId: customerId))
        self.api = api
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(vm.snapshot.detail?.displayName ?? "Customer")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            if let api, vm.snapshot.detail != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingEdit = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .accessibilityLabel("Edit customer")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingMerge = true } label: {
                        Label("Merge…", systemImage: "arrow.triangle.merge")
                    }
                    .accessibilityLabel("Merge customer with another")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let detail = vm.snapshot.detail, let api {
                CustomerEditView(api: api, customer: detail) {
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $showingMerge) {
            if let detail = vm.snapshot.detail, let api {
                CustomerMergeView(api: api, primary: detail) {
                    Task { await vm.load() }
                }
            }
        }
        .sheet(isPresented: $showingTagEditor) {
            if let detail = vm.snapshot.detail, let api {
                CustomerTagEditorSheet(
                    api: api,
                    customerId: detail.id,
                    initialTags: detail.tagList
                ) { _ in
                    Task { await vm.load() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading, vm.snapshot.detail == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.snapshot.detail == nil {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                Text("Couldn't load customer")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail = vm.snapshot.detail {
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    Header(detail: detail, analytics: vm.snapshot.analytics)

                    let health = CustomerHealthScore.compute(detail: detail)
                    if let rec = health.recommendation {
                        RecommendationBanner(text: rec, detail: detail)
                    }

                    if let stats = vm.snapshot.analytics {
                        QuickStatsRow(analytics: stats)
                    }

                    QuickActions(detail: detail)

                    ContactInfo(detail: detail)

                    if let tickets = vm.snapshot.recentTickets, !tickets.isEmpty {
                        RecentTicketsSection(tickets: tickets)
                    }

                    if let invoices = vm.snapshot.recentInvoices, !invoices.isEmpty {
                        RecentInvoicesSection(invoices: invoices)
                    }

                    // §5.9 Tags section
                    TagsCard(
                        tagItems: detail.tagItems ?? detail.tagList.map { CustomerDetail.CustomerTagItem(name: $0, color: nil) },
                        onEditTags: api != nil ? { showingTagEditor = true } : nil
                    )

                    if let comments = detail.comments, !comments.isEmpty {
                        CommentsCard(text: comments)
                    }

                    if let notes = vm.snapshot.notes, !notes.isEmpty {
                        NotesTimeline(notes: notes)
                    }

                    // §5.6 Contacts section
                    if let api {
                        CustomerContactListView(api: api, customerId: detail.id)
                    }

                    // §5.7 Devices section
                    if let api {
                        CustomerDeviceListView(api: api, customerId: detail.id)
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

// MARK: - Header

private struct Header: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?

    var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                Text(detail.initials)
                    .font(.brandDisplayMedium())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 88, height: 88)

            Text(detail.displayName)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)

            if let group = detail.customerGroupName, !group.isEmpty {
                Text(group)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // §44 — health badge + LTV chip + LTV tier badge + churn risk badge
            let health = CustomerHealthScore.compute(detail: detail)
            let ltvDollars: Double? = {
                if let ltv = analytics?.lifetimeValue, ltv > 0 { return ltv }
                if let c = detail.ltvCents, c > 0 { return Double(c) / 100.0 }
                return nil
            }()
            let ltvCentsInt = ltvDollars.map { Int($0 * 100) } ?? 0
            let tier = LTVCalculator.tier(for: ltvCentsInt)

            BrandGlassContainer(spacing: BrandSpacing.sm) {
                HStack(spacing: BrandSpacing.sm) {
                    CustomerHealthBadge(score: health)
                    // LTV chip (dollar amount)
                    if let ltv = ltvDollars {
                        CustomerLTVChip(ltvDollars: ltv)
                    }
                    // §44.2 Tier badge
                    LTVTierBadge(tier: tier, ltvDollars: ltvDollars)
                }
            }

            // §5 Customer-since badge — localised "Member since {date}" label.
            CustomerSinceBadge(createdAt: detail.createdAt)

            // §44.3 Churn risk badge — shown below the tier row
            let churnInput = ChurnInput(
                daysSinceLastVisit: analytics?.daysSinceLastVisit ?? {
                    detail.lastVisitAt.flatMap { CustomerHealthScore.parseISO8601($0) }
                        .map { CustomerHealthScore.daysSince($0) }
                }(),
                visitFrequencyDecline: false,
                supportComplaints: detail.complaintCount ?? 0,
                npsScore: nil,
                ltvTrend: .stable
            )
            let churnScore = ChurnScoreCalculator.compute(input: churnInput)
            if churnScore.riskLevel != .low {
                ChurnRiskBadge(score: churnScore)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.md)
    }
}

// MARK: - Quick stats

private struct QuickStatsRow: View {
    let analytics: CustomerAnalytics

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            tile("Tickets", value: "\(analytics.totalTickets)")
            tile("Lifetime", value: formatMoney(analytics.lifetimeValue))
            tile("Last visit", value: analytics.lastVisit.map { String($0.prefix(10)) } ?? "—")
        }
    }

    private func tile(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Quick actions (Call / SMS)

private struct QuickActions: View {
    let detail: CustomerDetail

    var phone: String? {
        if let m = detail.mobile, !m.isEmpty { return m }
        if let p = detail.phone, !p.isEmpty { return p }
        return nil
    }

    var body: some View {
        if let phone {
            let digits = phone.filter(\.isNumber)
            HStack(spacing: BrandSpacing.sm) {
                if let telURL = URL(string: "tel:\(digits)") {
                    Link(destination: telURL) {
                        actionLabel("Call", icon: "phone.fill", tint: .bizarreOrange)
                    }
                }
                if let smsURL = URL(string: "sms:\(digits)") {
                    Link(destination: smsURL) {
                        actionLabel("SMS", icon: "message.fill", tint: .bizarreTeal)
                    }
                }
            }
        }
    }

    private func actionLabel(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
            Text(title).font(.brandTitleMedium())
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .foregroundStyle(Color.black)
        .background(tint, in: Capsule())
    }
}

// MARK: - Contact info

private struct ContactInfo: View {
    let detail: CustomerDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Contact").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)

            if let mobile = detail.mobile, !mobile.isEmpty {
                row(icon: "phone", label: "Mobile", value: PhoneFormatter.format(mobile), mono: true)
            }
            if let phone = detail.phone, !phone.isEmpty, phone != detail.mobile {
                row(icon: "phone", label: "Phone", value: PhoneFormatter.format(phone), mono: true)
            }
            if let email = detail.email, !email.isEmpty {
                row(icon: "envelope", label: "Email", value: email)
            }
            if let addr = detail.addressLine {
                addressRow(addr: addr)
            }
            if let org = detail.organization, !org.isEmpty {
                row(icon: "building.2", label: "Organization", value: org)
            }

            // §5 blocklist toggle copy — SMS opt-out badge (read-only in detail; edit via Edit form).
            if detail.smsOptOut == true {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("SMS marketing opt-out")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreSurface2, in: Capsule())
                .accessibilityLabel("SMS marketing opt-out: customer has opted out of promotional messages")
            }
        }
        .cardBackground()
    }

    /// Standard text row with textSelection enabled.
    private func row(icon: String, label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon).foregroundStyle(.bizarreOnSurfaceMuted).frame(width: 22)
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

    /// Address row with a copy-to-clipboard chip alongside the text.
    @MainActor
    private func addressRow(addr: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "mappin.and.ellipse").foregroundStyle(.bizarreOnSurfaceMuted).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Address").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                Text(addr)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            // §5 address copy chip
            Button {
                UIPasteboard.general.string = addr
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOrange)
                    .padding(BrandSpacing.xs)
                    .background(Color.bizarreOrange.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("Copy address")
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}

// MARK: - Recent tickets

private struct RecentTicketsSection: View {
    let tickets: [TicketSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent tickets").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            VStack(spacing: BrandSpacing.xs) {
                ForEach(tickets.prefix(10)) { t in
                    let deviceName = t.firstDevice?.deviceName ?? ""
                    let statusName = t.status?.name ?? ""
                    let a11yLabel: String = {
                        var parts = ["Ticket \(t.orderId)"]
                        if !deviceName.isEmpty { parts.append(deviceName) }
                        if !statusName.isEmpty { parts.append("Status: \(statusName)") }
                        return parts.joined(separator: ", ")
                    }()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.orderId).font(.brandMono(size: 14)).foregroundStyle(.bizarreOnSurface)
                            if !deviceName.isEmpty {
                                Text(deviceName).font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(1)
                            }
                        }
                        Spacer()
                        if !statusName.isEmpty {
                            Text(statusName).font(.brandLabelSmall())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.bizarreSurface2, in: Capsule())
                                .foregroundStyle(.bizarreOnSurface)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a11yLabel)
                }
            }
        }
        .cardBackground()
    }
}

// MARK: - Tags / Comments / Notes

private struct TagsCard: View {
    let tagItems: [CustomerDetail.CustomerTagItem]
    let onEditTags: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Tags").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                if let onEditTags {
                    Button {
                        onEditTags()
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.bizarreOrange)
                    }
                    .accessibilityLabel("Edit tags")
                }
            }
            if tagItems.isEmpty {
                Text("No tags.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                // §5 Accessibility-labelled tag chips
                AccessibleTagChips(tagItems: tagItems)
            }
        }
        .cardBackground()
    }
}

private struct FlowTags: View {
    let tagItems: [CustomerDetail.CustomerTagItem]

    var body: some View {
        // Simple wrapping via LazyVGrid; flow layout would be prettier but not critical.
        let columns = [GridItem(.adaptive(minimum: 80), spacing: BrandSpacing.xs)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(tagItems, id: \.name) { item in
                let accent = item.color.flatMap { Color(hexString: $0) } ?? Color.bizarreSurface2
                Text(item.name)
                    .font(.brandLabelLarge())
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .foregroundStyle(item.color != nil ? .white : .bizarreOnSurface)
                    .background(accent.opacity(item.color != nil ? 0.85 : 1), in: Capsule())
                    .accessibilityLabel("Tag: \(item.name)")
            }
        }
    }
}

private struct CommentsCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .cardBackground()
    }
}

private struct NotesTimeline: View {
    let notes: [CustomerNote]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Timeline").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                ForEach(notes.prefix(25)) { note in
                    VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                        HStack {
                            Text(note.authorUsername ?? "Staff")
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(String(note.createdAt.prefix(16)))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Text(note.body)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .padding(.vertical, BrandSpacing.xs)
                }
            }
        }
        .cardBackground()
    }
}

// MARK: - §44 Recommendation banner

/// Horizontal glass card shown when `CustomerHealthScore` produces a recommendation.
/// The "Send follow-up" CTA deep-links to the native SMS compose sheet
/// using the existing `sms:` URL scheme with the customer's phone pre-filled.
private struct RecommendationBanner: View {
    let text: String
    let detail: CustomerDetail

    private var smsURL: URL? {
        let digits = [detail.mobile, detail.phone]
            .compactMap { $0?.filter(\.isNumber) }
            .first { !$0.isEmpty }
        guard let digits else { return nil }
        return URL(string: "sms:\(digits)")
    }

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.bizarreWarning)
                .font(.system(size: 18))
                .accessibilityHidden(true)

            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let url = smsURL {
                Link(destination: url) {
                    Text("Send follow-up")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreTeal)
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xs)
                        .background(Color.bizarreTeal.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel("Send follow-up SMS to \(detail.displayName)")
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recent invoices

private struct RecentInvoicesSection: View {
    let invoices: [Networking.InvoiceSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent invoices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            VStack(spacing: BrandSpacing.xs) {
                ForEach(Array(invoices.prefix(5))) { inv in
                    let totalFormatted = formattedTotal(inv.total)
                    let statusName = inv.status?.capitalized ?? "Unknown"
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inv.displayId)
                                .font(.brandMono(size: 14))
                                .foregroundStyle(.bizarreOnSurface)
                            if let date = inv.createdAt.map({ String($0.prefix(10)) }) {
                                Text(date)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(totalFormatted)
                                .font(.brandTitleMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text(statusName)
                                .font(.brandLabelSmall())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(statusColor(inv.statusKind).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(inv.statusKind))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Invoice \(inv.displayId), \(totalFormatted), \(statusName)")
                }
            }
        }
        .cardBackground()
    }

    private func formattedTotal(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    private func statusColor(_ kind: Networking.InvoiceSummary.Status) -> Color {
        switch kind {
        case .paid:    return .bizarreTeal
        case .unpaid:  return .bizarreError
        case .partial: return .bizarreWarning
        case .void_:   return .bizarreOnSurfaceMuted
        case .other:   return .bizarreOnSurfaceMuted
        }
    }
}

// MARK: - Card helper

private struct CardBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

private extension View {
    func cardBackground() -> some View { modifier(CardBackgroundModifier()) }
}

// MARK: - Hex color helper

private extension Color {
    /// Parse a 6-digit RGB hex string (with or without leading `#`) into a SwiftUI Color.
    /// Returns nil when the string is not a valid 6-digit hex.
    init?(hexString: String) {
        let stripped = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard stripped.count == 6, let value = UInt32(stripped, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
#endif
