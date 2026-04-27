#if canImport(UIKit)
import SwiftUI
import Core
import CoreImage
import CoreImage.CIFilterBuiltins
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
    // §4.2 — QR code
    @State private var showingQRCode: Bool = false
    // §4.2 — Tab layout
    @State private var activeTab: TicketDetailTab = .actions
    @Environment(\.dismiss) private var dismiss
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
        // §4.4 — delete confirmation
        .confirmationDialog(
            "Delete this ticket?",
            isPresented: $vm.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await vm.deleteTicket(); if vm.wasDeleted { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the ticket and all associated data.")
        }
        .onChange(of: vm.wasDeleted) { _, deleted in if deleted { dismiss() } }
        // §4.4 — concurrent-edit 409 banner
        .safeAreaInset(edge: .top, spacing: 0) {
            if vm.concurrentEditBanner {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(.white).accessibilityHidden(true)
                    Text("This ticket changed.")
                        .font(.brandBodyMedium()).foregroundStyle(.white)
                    Spacer()
                    Button("Reload") { Task { await vm.load() } }
                        .font(.brandLabelLarge().bold()).foregroundStyle(.white)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreOrange)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("This ticket changed elsewhere. Tap Reload to refresh.")
            }
        }
        // §4.5 — action error
        .alert("Action Failed", isPresented: Binding(
            get: { vm.actionErrorMessage != nil },
            set: { if !$0 { vm.actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.actionErrorMessage = nil }
        } message: {
            if let msg = vm.actionErrorMessage { Text(msg) }
        }
        // §4.2 — QR code sheet
        .sheet(isPresented: $showingQRCode) {
            if case let .loaded(detail) = vm.state {
                TicketQRCodeSheet(orderId: detail.orderId)
            }
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

            // Actions menu: Edit, Change Status, Timeline, QR, Convert, Duplicate, Merge, Split, Sign-Off, Delete
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button { showingEdit = true } label: {
                        Label("Edit Details", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("ticket.editDetails")

                    Button { showingStatus = true } label: {
                        Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("ticket.changeStatus")

                    Divider()

                    Button { showingTimeline = true } label: {
                        Label("View Timeline", systemImage: "clock.fill")
                    }
                    .accessibilityIdentifier("ticket.timeline")

                    // §4.2 — QR code
                    Button { showingQRCode = true } label: {
                        Label("Show QR Code", systemImage: "qrcode")
                    }
                    .accessibilityIdentifier("ticket.qrcode")

                    Divider()

                    // §4.5 — Convert to invoice
                    Button { Task { await vm.convertToInvoice() } } label: {
                        Label("Convert to Invoice", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("ticket.convertToInvoice")

                    // §4.5 — Duplicate
                    Button { Task { await vm.duplicateTicket() } } label: {
                        Label("Duplicate Ticket", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("ticket.duplicate")

                    // §4 — Merge / Split
                    Button { showingMerge = true } label: {
                        Label("Merge…", systemImage: "arrow.triangle.merge")
                    }
                    .accessibilityIdentifier("ticket.merge")

                    Button { showingSplit = true } label: {
                        Label("Split…", systemImage: "arrow.triangle.branch")
                    }
                    .accessibilityIdentifier("ticket.split")

                    // §4 — Sign-off (only when readyForPickup)
                    if case .loaded(let detail) = vm.state,
                       detail.status?.name.lowercased().contains("pickup") == true {
                        Divider()
                        Button { showingSignOff = true } label: {
                            Label("Customer Sign-Off", systemImage: "signature")
                        }
                        .accessibilityIdentifier("ticket.signoff")
                    }

                    Divider()

                    // §4.4 — Delete (destructive)
                    Button(role: .destructive) {
                        vm.showDeleteConfirm = true
                    } label: {
                        Label("Delete Ticket", systemImage: "trash")
                    }
                    .accessibilityIdentifier("ticket.delete")

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
                    // §4.2 — Copyable header + share link
                    HStack {
                        Text(detail.orderId)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .textSelection(.enabled)
                            .accessibilityLabel("Ticket ID: \(detail.orderId)")
                        Spacer()
                        ShareLink(
                            item: URL(string: "https://app.bizarrecrm.com/tickets/\(detail.id)") ?? URL(string: "https://app.bizarrecrm.com")!,
                            subject: Text("Ticket \(detail.orderId)"),
                            message: Text("View ticket \(detail.orderId)")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.bizarreOrange)
                        }
                        .accessibilityLabel("Share ticket link")
                    }
                    .padding(BrandSpacing.base)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))

                    CustomerCard(detail: detail)

                    // §4.2 — Customer quick actions
                    if let customer = detail.customer {
                        CustomerQuickActionsRow(customer: customer)
                    }

                    InfoRow(detail: detail)

                    // §4.6 — Status chip with inline transition button + server hex color
                    if let status = detail.status, let api {
                        StatusChipRow(status: status) {
                            showingTransition = true
                        }
                    }

                    // §4.2 — Tab picker (segmented on iPhone, horizontal tabs on iPad)
                    TicketDetailTabPicker(selection: $activeTab)

                    // §4.2 — Tab content
                    switch activeTab {

                    case .actions:
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

                    case .devices:
                        if detail.devices.isEmpty {
                            Text("No devices attached")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .frame(maxWidth: .infinity)
                                .padding(BrandSpacing.lg)
                        } else {
                            DevicesSection(devices: detail.devices)
                        }

                    case .notes:
                        if detail.notes.isEmpty {
                            Text("No notes yet")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .frame(maxWidth: .infinity)
                                .padding(BrandSpacing.lg)
                        } else {
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

                    case .payments:
                        TicketPaymentsTabView(payments: detail.payments)
                            .cardBackground()

                    }

                    // §4.4 — Delete button at bottom of detail
                    if api != nil {
                        Button(role: .destructive) {
                            vm.showDeleteConfirm = true
                        } label: {
                            Label("Delete Ticket", systemImage: "trash")
                                .font(.brandBodyMedium())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BrandSpacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(.bizarreError)
                        .accessibilityLabel("Delete this ticket")
                        .accessibilityHint("Shows a confirmation before deleting")
                        .disabled(vm.isDeleting)
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
    }
}

// MARK: - §4.2 QR code sheet

private struct TicketQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let orderId: String

    var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                if let qr = makeQR(orderId) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .padding(BrandSpacing.lg)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("QR code for ticket \(orderId)")
                }
                Text(orderId)
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func makeQR(_ s: String) -> UIImage? {
        let ctx = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(s.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage else { return nil }
        let scaled = ci.transformed(by: .init(scaleX: 10, y: 10))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - §4.2 Customer quick actions row

private struct CustomerQuickActionsRow: View {
    let customer: TicketDetail.Customer

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                if let phone = customer.callablePhone {
                    if let url = URL(string: "tel:\(phone.filter(\.isNumber))") {
                        quickChip("Call", icon: "phone.fill", color: .bizarreTeal, url: url)
                    }
                    if let url = URL(string: "sms:\(phone.filter(\.isNumber))") {
                        quickChip("SMS", icon: "message.fill", color: .bizarreTeal, url: url)
                    }
                    if let url = URL(string: "facetime:\(phone.filter(\.isNumber))") {
                        quickChip("FaceTime", icon: "video.fill", color: .bizarreTeal, url: url)
                    }
                }
                if let email = customer.email,
                   let enc = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "mailto:\(enc)") {
                    quickChip("Email", icon: "envelope.fill", color: .bizarreOrange, url: url)
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func quickChip(_ label: String, icon: String, color: Color, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.brandLabelLarge())
            }
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(color.opacity(0.12), in: Capsule())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Status chip row (§4.6 + §4.7 server hex color)

private struct StatusChipRow: View {
    let status: TicketDetail.Status
    let onAdvance: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.xs) {
                // §4.7 — render server hex color dot
                if let hex = status.color, let color = colorFromHex(hex) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(status.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
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

    private func colorFromHex(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
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

private struct TotalsCard: View {
    let detail: TicketDetail

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Totals").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)

            if let subtotal = detail.subtotal, subtotal != (detail.total ?? 0) {
                row("Subtotal", value: subtotal)
            }
            if let discount = detail.discount, discount > 0 {
                row("Discount", value: -discount, tint: .bizarreSuccess)
            }
            if let tax = detail.totalTax, tax > 0 {
                row("Tax", value: tax)
            }
            Divider().overlay(Color.bizarreOutline.opacity(0.4))
            HStack {
                Text("Total").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(detail.total ?? 0))
                    .font(.brandTitleLarge()).bold()
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total: \(formatMoney(detail.total ?? 0))")
        }
        .cardBackground()
    }

    private func row(_ label: String, value: Double, tint: Color = .bizarreOnSurface) -> some View {
        HStack {
            Text(label).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(formatMoney(value))
                .font(.brandBodyMedium())
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(formatMoney(value))")
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
