#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

public struct TicketDetailView: View {
    @State private var vm: TicketDetailViewModel
    @State private var showingEdit: Bool = false
    @State private var showingStatus: Bool = false
    @State private var showingTransition: Bool = false
    @State private var showingTimeline: Bool = false
    // §4 — new features
    @State private var showingMerge: Bool = false
    @State private var showingSplit: Bool = false
    @State private var showingSignOff: Bool = false
    private let api: APIClient?

    /// Basic init — read-only detail.
    public init(repo: TicketRepository, ticketId: Int64) {
        _vm = State(wrappedValue: TicketDetailViewModel(repo: repo, ticketId: ticketId))
        self.api = nil
    }

    /// Edit-capable init — enables the "Edit" toolbar button that presents
    /// `TicketEditDeepView`. Pass the real `APIClient` when you want writes.
    public init(repo: TicketRepository, ticketId: Int64, api: APIClient) {
        _vm = State(wrappedValue: TicketDetailViewModel(repo: repo, ticketId: ticketId))
        self.api = api
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .toolbar {
            toolbarItems
        }
        // §4.4 — Deep edit sheet
        .sheet(isPresented: $showingEdit) {
            if let api, case let .loaded(detail) = vm.state {
                TicketEditDeepView(api: api, ticket: detail) {
                    Task { await vm.load() }
                }
            }
        }
        // Legacy status change (server-driven list)
        .sheet(isPresented: $showingStatus) {
            if let api, case let .loaded(detail) = vm.state {
                TicketStatusChangeSheet(
                    ticketId: detail.id,
                    currentStatusId: detail.status?.id,
                    api: api
                ) { Task { await vm.load() } }
            }
        }
        // §4.6 — State-machine-gated transition sheet
        .sheet(isPresented: $showingTransition) {
            if let api, case let .loaded(detail) = vm.state {
                TicketStatusTransitionSheet(
                    ticketId: detail.id,
                    currentStatus: detail.status,
                    api: api
                ) { Task { await vm.load() } }
            }
        }
        // §4.7 — Timeline sheet
        .sheet(isPresented: $showingTimeline) {
            if let api, case let .loaded(detail) = vm.state {
                NavigationStack {
                    ScrollView {
                        TicketTimelineView(
                            ticketId: detail.id,
                            api: api,
                            fallbackHistory: detail.history
                        )
                        .padding(BrandSpacing.base)
                    }
                    .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                    .navigationTitle("Timeline")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingTimeline = false }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
        // §4 — Merge
        .sheet(isPresented: $showingMerge) {
            if let api, case let .loaded(detail) = vm.state {
                TicketMergeView(vm: TicketMergeViewModel(
                    primaryId: detail.id,
                    repo: vm.repo,
                    api: api
                ))
            }
        }
        // §4 — Split
        .sheet(isPresented: $showingSplit) {
            if let api, case let .loaded(detail) = vm.state {
                TicketSplitView(vm: TicketSplitViewModel(
                    ticketId: detail.id,
                    repo: vm.repo,
                    api: api
                ))
            }
        }
        // §4 — Sign-off (only when readyForPickup)
        .sheet(isPresented: $showingSignOff) {
            if let api, case let .loaded(detail) = vm.state {
                TicketSignOffView(vm: TicketSignOffViewModel(
                    ticketId: detail.id,
                    api: api
                ))
            }
        }
    }

    private var navTitle: String {
        if case let .loaded(detail) = vm.state { return detail.orderId }
        return "Ticket"
    }

    // MARK: — Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if api != nil, case .loaded = vm.state {
            // §4.6 — "Advance status" button
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingTransition = true
                } label: {
                    Label("Advance Status", systemImage: "arrow.right.circle")
                }
                .accessibilityLabel("Advance ticket status")
                .accessibilityHint("Opens status transition sheet")
                .brandGlass(.clear, in: Capsule())
            }

            // Actions menu: Edit, Change Status, Timeline, Merge, Split, Sign-Off
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("ticket.editDetails")

                    Button {
                        showingStatus = true
                    } label: {
                        Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("ticket.changeStatus")

                    Divider()

                    Button {
                        showingTimeline = true
                    } label: {
                        Label("View Timeline", systemImage: "clock.fill")
                    }
                    .accessibilityIdentifier("ticket.timeline")

                    Divider()

                    // §4 — Merge / Split
                    Button {
                        showingMerge = true
                    } label: {
                        Label("Merge…", systemImage: "arrow.triangle.merge")
                    }
                    .accessibilityIdentifier("ticket.merge")

                    Button {
                        showingSplit = true
                    } label: {
                        Label("Split…", systemImage: "arrow.triangle.branch")
                    }
                    .accessibilityIdentifier("ticket.split")

                    // §4 — Sign-off (only when readyForPickup)
                    if case .loaded(let detail) = vm.state,
                       detail.status?.name.lowercased().contains("pickup") == true {
                        Divider()
                        Button {
                            showingSignOff = true
                        } label: {
                            Label("Customer Sign-Off", systemImage: "signature")
                        }
                        .accessibilityIdentifier("ticket.signoff")
                    }

                    // §4.2: Copy link to ticket — Universal Link
                    if case .loaded(let detail) = vm.state {
                        Divider()
                        Button {
                            let urlString = "https://app.bizarrecrm.com/tickets/\(detail.id)"
                            UIPasteboard.general.string = urlString
                        } label: {
                            Label("Copy Link", systemImage: "link")
                        }
                        .accessibilityIdentifier("ticket.copyLink")
                        .accessibilityLabel("Copy Universal Link to this ticket")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("ticket.actions")
            }
        }
    }

    // MARK: — Content

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading ticket")
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load ticket")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .loaded(let detail):
            ScrollView {
                VStack(spacing: BrandSpacing.base) {
                    CustomerCard(detail: detail)
                    InfoRow(detail: detail)

                    // §4.6 — Status chip with inline transition button
                    if let status = detail.status, let api {
                        StatusChipRow(status: status) {
                            showingTransition = true
                        }
                    }

                    if !detail.devices.isEmpty {
                        DevicesSection(devices: detail.devices)
                    }
                    if !detail.notes.isEmpty {
                        NotesSection(notes: detail.notes)
                    }

                    // §4 — Photos section
                    TicketDevicePhotoListView(
                        photos: detail.photos,
                        ticketId: detail.id,
                        uploadService: nil,
                        onUpload: nil
                    )
                    .cardBackground()

                    // §4 — Sign-off button when readyForPickup
                    if api != nil,
                       detail.status?.name.lowercased().contains("pickup") == true {
                        Button {
                            showingSignOff = true
                        } label: {
                            Label("Customer Sign-Off", systemImage: "signature")
                                .font(.brandBodyLarge())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BrandSpacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Customer sign-off for pickup")
                        .accessibilityHint("Opens signature capture for customer to sign off on repair")
                    }

                    // §4.7 — Timeline section (inline preview)
                    if let api, !detail.history.isEmpty {
                        TimelinePreviewSection(
                            ticketId: detail.id,
                            api: api,
                            history: detail.history
                        ) {
                            showingTimeline = true
                        }
                    }

                    TotalsCard(detail: detail)
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

// MARK: - Status chip row (§4.6)

private struct StatusChipRow: View {
    let status: TicketDetail.Status
    let onAdvance: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Text(status.name)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .brandGlass(.clear, in: Capsule())
                .accessibilityLabel("Status: \(status.name)")

            Spacer()

            Button {
                onAdvance()
            } label: {
                Label("Advance", systemImage: "arrow.right.circle")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advance ticket status")
            .accessibilityHint("Opens status transition options")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Timeline preview section (§4.7 — inline)

private struct TimelinePreviewSection: View {
    let ticketId: Int64
    let api: APIClient
    let history: [TicketDetail.TicketHistory]
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Timeline")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Button("Show all") { onShowAll() }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Show full timeline")
            }

            // Show up to 3 most recent history entries inline.
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                ForEach(history.prefix(3)) { entry in
                    HStack(alignment: .top, spacing: BrandSpacing.sm) {
                        Circle()
                            .fill(Color.bizarreOrange)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.stripped)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            if let ts = entry.createdAt {
                                Text(String(ts.prefix(16)))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.stripped) at \(String((entry.createdAt ?? "").prefix(16)))")
                }
            }
        }
        .cardBackground()
    }
}

// MARK: - Customer card

private struct CustomerCard: View {
    let detail: TicketDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Customer")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(detail.customer?.displayName ?? "Unknown")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
            if let phone = detail.customer?.phone, !phone.isEmpty,
               let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                Link(destination: url) {
                    Label(PhoneFormatter.format(phone), systemImage: "phone.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreTeal)
                }
                .accessibilityLabel("Call \(PhoneFormatter.format(phone))")
            }
            if let email = detail.customer?.email, !email.isEmpty,
               let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "mailto:\(encoded)") {
                Link(destination: url) {
                    Label(email, systemImage: "envelope.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreTeal)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Email \(email)")
            }
            if let org = detail.customer?.organization, !org.isEmpty {
                Label(org, systemImage: "building.2")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Organization: \(org)")
            }
        }
        .cardBackground()
    }
}

// MARK: - Info row (created + assigned)

private struct InfoRow: View {
    let detail: TicketDetail

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            InfoTile(label: "Created", value: shortDate(detail.createdAt))
            if let user = detail.assignedUser {
                InfoTile(label: "Assigned", value: user.fullName.isEmpty ? "—" : user.fullName)
            }
            if let status = detail.status {
                InfoTile(label: "Status", value: status.name)
            }
        }
    }

    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        return String(iso.prefix(10))
    }
}

private struct InfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(label).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
            Text(value).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Devices

private struct DevicesSection: View {
    let devices: [TicketDetail.TicketDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Devices").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(devices) { device in
                DeviceCard(device: device)
            }
        }
    }
}

private struct DeviceCard: View {
    let device: TicketDetail.TicketDevice

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text(device.displayName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)

            if let notes = device.additionalNotes, !notes.isEmpty {
                Text(notes)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let imei = device.imei, !imei.isEmpty {
                KeyValueLine(key: "IMEI", value: imei, mono: true)
            }
            if let serial = device.serial, !serial.isEmpty {
                KeyValueLine(key: "Serial", value: serial, mono: true)
            }
            if let code = device.securityCode, !code.isEmpty {
                KeyValueLine(key: "Passcode", value: code, mono: true)
            }
            if let price = device.total, price > 0 {
                KeyValueLine(key: "Price", value: formatMoney(price))
            }

            if let parts = device.parts, !parts.isEmpty {
                Divider().overlay(Color.bizarreOutline.opacity(0.4))
                ForEach(parts) { part in
                    HStack {
                        Text("\(part.name ?? "Part")  ×\(part.quantity ?? 1)")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        if let total = part.total {
                            Text(formatMoney(total))
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .cardBackground()
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

private struct KeyValueLine: View {
    let key: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(key)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - Notes

private struct NotesSection: View {
    let notes: [TicketDetail.TicketNote]

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Notes").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    HStack {
                        Text(note.userName)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        if note.isFlagged == true {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.bizarreError)
                                .accessibilityLabel("Flagged")
                        }
                        Spacer()
                        if let ts = note.createdAt {
                            Text(String(ts.prefix(16)))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    Text(note.stripped)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .cardBackground()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(note.userName): \(note.stripped)\(note.isFlagged == true ? ", flagged" : "")")
            }
        }
    }
}

// MARK: - Totals

// §4.2 Totals panel — subtotal, tax, discount, deposit, balance due, paid.
// `.textSelection(.enabled)` on each money value; copyable grand total.
// Deposit and paid are server-side fields on TicketDetail when present.
// Balance due = total − paid (client-side calculation until dedicated server field).
private struct TotalsCard: View {
    let detail: TicketDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Totals")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            if let subtotal = detail.subtotal {
                row("Subtotal", value: subtotal)
            }
            if let discount = detail.discount, discount > 0 {
                row("Discount", value: -discount, tint: .bizarreSuccess)
            }
            if let tax = detail.totalTax, tax > 0 {
                row("Tax", value: tax)
            }

            Divider().overlay(Color.bizarreOutline.opacity(0.4))

            // Grand total (copyable)
            HStack {
                Text("Total")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(detail.total ?? 0))
                    .font(.brandTitleLarge())
                    .bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total: \(formatMoney(detail.total ?? 0))")

            // Balance due: total − paid. Balance field not yet on TicketDetail
            // DTO — show if total > 0 as a convenience row so techs know what's owed.
            // TODO: replace with server field when /tickets/:id returns balance_due.
            let total = detail.total ?? 0
            if total > 0 {
                Divider().overlay(Color.bizarreOutline.opacity(0.2))
                HStack {
                    Text("Balance due")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text(formatMoney(total))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreWarning)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Balance due: \(formatMoney(total))")
            }
        }
        .cardBackground()
    }

    private func row(_ label: String, value: Double, tint: Color = .bizarreOnSurface) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(abs(value)))
                .font(.brandBodyMedium())
                .foregroundStyle(tint)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formatMoney(abs(value)))")
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Card background helper

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
#endif
