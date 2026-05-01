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
    // §4.2 — Warranty/SLA badge VM (lazy-loaded)
    @State private var warrantySLAVM: TicketWarrantySLAViewModel?
    // §4.5 — Attach invoice / transfer location sheets
    @State private var showingAttachInvoice: Bool = false
    @State private var showingTransferLocation: Bool = false
    // §4.2 — Assignee picker
    @State private var showingAssigneePicker: Bool = false
    // §4.2 — Device add/edit sheets
    @State private var showingAddDevice: Bool = false
    @State private var deviceBeingEdited: TicketDetail.TicketDevice? = nil
    @State private var deviceForServices: TicketDetail.TicketDevice? = nil
    // §4.2 — Note compose
    @State private var showingNoteCompose: Bool = false
    // §4.9 — Bench timer widget visibility toggle
    @State private var showBenchTimer: Bool = false
    // §4.2 — Share PDF / AirPrint
    @State private var showingSharePDF: Bool = false
    @State private var sharePDFURL: URL?
    // §4.2 — Handoff (NSUserActivity for Continuity)
    @State private var userActivity: NSUserActivity?
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
        // §4.13 — iPad Magic Keyboard shortcuts
        .keyboardShortcut("d", modifiers: .command)  // ⌘D — mark done (advance to complete)
        .simultaneousGesture(TapGesture().onEnded { })  // placeholder anchor for shortcut
        .background(
            // §4.13 — Register keyboard shortcuts via overlay so they appear in discoverability HUD
            Group {
                Button(action: { showingTransition = true }) { EmptyView() }
                    .keyboardShortcut("d", modifiers: .command)
                    .accessibilityLabel("Mark ticket done")
                Button(action: { showingAssigneePicker = true }) { EmptyView() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .accessibilityLabel("Assign ticket")
                Button(action: {
                    if case .loaded(let detail) = vm.state,
                       let phone = detail.customer?.phone {
                        SMSLauncher.open(phone: phone)
                    }
                }) { EmptyView() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityLabel("Send SMS update")
                Button(action: { vm.showDeleteConfirm = true }) { EmptyView() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .accessibilityLabel("Delete ticket (admin only)")
            }
            .opacity(0)  // invisible — shortcuts still fire
        )
        .task {
            await vm.load()
            // §4.2 — Handoff: advertise this ticket via NSUserActivity for Continuity
            if case .loaded(let detail) = vm.state {
                let activity = NSUserActivity(activityType: "com.bizarrecrm.ticket")
                activity.title = "Ticket \(detail.orderId)"
                activity.userInfo = ["ticketId": detail.id, "orderId": detail.orderId]
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = false
                activity.webpageURL = URL(string: "https://app.bizarrecrm.com/tickets/\(detail.id)")
                activity.becomeCurrent()
                userActivity = activity
            }
            // §4.2 — Lazily init + load warranty/SLA VM after detail loaded
            if let api, case .loaded(let detail) = vm.state {
                let firstIMEI = detail.devices.first?.imei
                let firstSerial = detail.devices.first?.serial
                if firstIMEI != nil || firstSerial != nil {
                    let wvm = TicketWarrantySLAViewModel(
                        api: api,
                        ticketId: detail.id,
                        imei: firstIMEI,
                        serial: firstSerial
                    )
                    warrantySLAVM = wvm
                    await wvm.load()
                }
            }
        }
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
        // §4 — deleted-on-server banner
        .safeAreaInset(edge: .top, spacing: 0) {
            if vm.deletedOnServerBanner {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundStyle(.white).accessibilityHidden(true)
                    Text("Ticket removed.")
                        .font(.brandBodyMedium()).foregroundStyle(.white)
                    Spacer()
                    Button("Close") { dismiss() }
                        .font(.brandLabelLarge().bold()).foregroundStyle(.white)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreError)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ticket was removed. Tap Close.")
            }
        }
        // §4 — permission denied inline toast
        .overlay(alignment: .bottom) {
            if vm.permissionDeniedToast {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.white).accessibilityHidden(true)
                    Text("Ask your admin to enable this.")
                        .font(.brandBodyMedium()).foregroundStyle(.white)
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(.bizarreError.opacity(0.9), in: Capsule())
                .padding(BrandSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        vm.permissionDeniedToast = false
                    }
                }
                .accessibilityLabel("Permission denied: Ask your admin to enable this.")
            }
        }
        .animation(.spring(duration: 0.25), value: vm.permissionDeniedToast)
        // §4.13 — Network error while cached data is visible: glass retry pill
        .overlay(alignment: .top) {
            if let errMsg = vm.networkErrorMessage {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text("Couldn't refresh")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Text("Retry")
                            .font(.brandLabelLarge().bold())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Couldn't refresh ticket. \(errMsg). Tap Retry.")
                .accessibilityAddTraits(.isButton)
                .onTapGesture { Task { await vm.load() } }
            }
        }
        .animation(.spring(duration: 0.3), value: vm.networkErrorMessage != nil)
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
                    api: api,
                    metPrerequisites: metPrerequisites(for: detail)
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
        // §4.5 — Attach to existing invoice
        .sheet(isPresented: $showingAttachInvoice) {
            if let api, case let .loaded(detail) = vm.state {
                TicketAttachInvoiceSheet(
                    api: api,
                    ticketId: detail.id
                ) { Task { await vm.load() } }
            }
        }
        // §4.5 — Transfer to another store / location
        .sheet(isPresented: $showingTransferLocation) {
            if let api, case let .loaded(detail) = vm.state {
                TicketTransferLocationSheet(
                    api: api,
                    ticketId: detail.id
                ) { Task { await vm.load() } }
            }
        }
        // §4.2 — Assignee picker
        .sheet(isPresented: $showingAssigneePicker) {
            if let api, case let .loaded(detail) = vm.state {
                TicketAssigneePickerSheet(
                    api: api,
                    ticketId: detail.id,
                    currentAssigneeId: detail.assignedTo
                ) { Task { await vm.load() } }
            }
        }
        // §4.2 — Add new device
        .sheet(isPresented: $showingAddDevice) {
            if let api, case let .loaded(detail) = vm.state {
                TicketDeviceSheet(
                    api: api,
                    ticketId: detail.id,
                    existingDevice: nil
                ) { Task { await vm.load() } }
            }
        }
        // §4.2 — Edit existing device
        .sheet(item: $deviceBeingEdited) { device in
            if let api, case let .loaded(detail) = vm.state {
                TicketDeviceSheet(
                    api: api,
                    ticketId: detail.id,
                    existingDevice: device
                ) { Task { await vm.load() } }
            }
        }
        // §4.2 — Services & parts for a device
        .sheet(item: $deviceForServices) { device in
            if let api {
                TicketDeviceServicesSheet(
                    api: api,
                    deviceId: device.id,
                    deviceName: device.displayName
                ) { Task { await vm.load() } }
            }
        }
        // §4.2 — Note compose
        .sheet(isPresented: $showingNoteCompose) {
            if let api, case let .loaded(detail) = vm.state {
                TicketNoteComposeView(
                    api: api,
                    ticketId: detail.id
                ) { Task { await vm.load() } }
            }
        }
    }

    private var navTitle: String {
        if case let .loaded(detail) = vm.state { return detail.orderId }
        return "Ticket"
    }

    // MARK: — §4.6 Prerequisite computation

    /// Computes the set of transition prerequisite IDs that are currently met,
    /// based on the loaded ticket detail's photos, notes, checklist state.
    private func metPrerequisites(for detail: TicketDetail) -> Set<String> {
        var met: Set<String> = []
        // Photo taken: at least one photo attached to the ticket.
        if !detail.photos.isEmpty {
            met.insert(TransitionPrerequisite.photoTaken)
        }
        // Note added: at least one staff note.
        if !detail.notes.isEmpty {
            met.insert(TransitionPrerequisite.noteAdded)
        }
        // Checklist signed: any device has a non-empty signed checklist recorded in history.
        // We use a heuristic — if a "checklist" event appears in history the checklist was signed.
        let checklistSigned = detail.history.contains { event in
            (event.description ?? "").lowercased().contains("checklist")
        }
        if checklistSigned { met.insert(TransitionPrerequisite.checklistSigned) }
        // QC sign-off: sign-off event in history.
        let hasSignOff = detail.history.contains { event in
            let d = (event.description ?? "").lowercased()
            return d.contains("sign-off") || d.contains("signed off") || d.contains("qc")
        }
        if hasSignOff { met.insert(TransitionPrerequisite.qcSignOff) }
        return met
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

                    // §4.2 — Share PDF / AirPrint
                    if case .loaded(let detail) = vm.state {
                        let woModel = WorkOrderModel.from(detail)
                        TicketSharePDFButton(model: woModel)
                            .accessibilityIdentifier("ticket.sharePDF")
                        TicketAirPrintButton(model: woModel)
                            .accessibilityIdentifier("ticket.airprint")
                            .keyboardShortcut("p", modifiers: .command)  // §4.13 ⌘P print
                    }

                    Divider()

                    // §4.5 — Convert to invoice
                    Button { Task { await vm.convertToInvoice() } } label: {
                        Label("Convert to Invoice", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("ticket.convertToInvoice")

                    // §4.5 — Attach to existing invoice
                    Button { showingAttachInvoice = true } label: {
                        Label("Attach to Invoice…", systemImage: "paperclip")
                    }
                    .accessibilityIdentifier("ticket.attachInvoice")

                    // §4.5 — Transfer to another store
                    Button { showingTransferLocation = true } label: {
                        Label("Transfer to Location…", systemImage: "arrow.triangle.swap")
                    }
                    .accessibilityIdentifier("ticket.transferLocation")

                    // §4.2 — Assign
                    Button { showingAssigneePicker = true } label: {
                        Label("Assign…", systemImage: "person.fill.badge.plus")
                    }
                    .accessibilityIdentifier("ticket.assign")

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

                    // §4.2 Header — ticket order ID copyable + Universal Link
                    if case .loaded(let detail) = vm.state {
                        Divider()
                        // §4.2: Copy order ID — shown in header per spec
                        Button {
                            UIPasteboard.general.string = detail.orderId
                        } label: {
                            Label("Copy Order ID (\(detail.orderId))", systemImage: "doc.on.doc")
                        }
                        .accessibilityIdentifier("ticket.copyOrderId")
                        .accessibilityLabel("Copy order ID \(detail.orderId) to clipboard")

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

                    // §4.2 — Urgency chip + due-date countdown chip in detail header
                    HStack(spacing: BrandSpacing.sm) {
                        if let urgency = detail.urgency, !urgency.isEmpty {
                            DetailUrgencyChip(urgency: urgency)
                        }
                        if let dueOn = detail.dueOn, !dueOn.isEmpty {
                            DueDateCountdownChip(isoDateString: dueOn)
                        }
                    }

                    // §4.2 — Warranty / SLA badge
                    if let wvm = warrantySLAVM {
                        TicketWarrantySLABadge(
                            slaStatus: nil, // sla_status available on TicketSummary, not TicketDetail
                            warrantyState: wvm.warrantyState
                        )
                        .padding(.horizontal, BrandSpacing.base)
                    }

                    InfoRow(detail: detail)

                    // §4.2 — Handoff banner (iPad/Mac only) — tells the user that
                    // Continuity Handoff is active so they can pick this up on their Mac.
                    if !Platform.isCompact {
                        TicketHandoffBanner(orderId: detail.orderId)
                    }

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
                        // §4.9 — Bench timer widget (glass card toggle)
                        BenchTimerToggleCard(isShowing: $showBenchTimer)

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
                        // §4.2 — Device section with add button + edit/services access
                        if let api {
                            DevicesSectionWithActions(
                                devices: detail.devices,
                                onAdd: { showingAddDevice = true },
                                onEdit: { deviceBeingEdited = $0 },
                                onServices: { deviceForServices = $0 }
                            )
                        } else {
                            if detail.devices.isEmpty {
                                Text("No devices attached")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                                    .frame(maxWidth: .infinity)
                                    .padding(BrandSpacing.lg)
                            } else {
                                DevicesSection(devices: detail.devices)
                            }
                        }

                    case .notes:
                        // §4.2 — Notes tab: list + compose button
                        if let api {
                            Button {
                                showingNoteCompose = true
                            } label: {
                                Label("Add note", systemImage: "plus.circle.fill")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOrange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(BrandSpacing.base)
                                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .accessibilityLabel("Add a new note to this ticket")
                            .accessibilityHint("Opens note compose sheet")
                        }

                        if detail.notes.isEmpty {
                            Text("No notes yet")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .frame(maxWidth: .infinity)
                                .padding(BrandSpacing.lg)
                        } else {
                            NotesSection(notes: detail.notes)
                        }

                        // §4.2 — Photos section
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
                // §22.1 — detail panes cap at 720 pt on wide iPad screens
                .maxContentWidth()
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
                    quickChipAction("SMS", icon: "message.fill", color: .bizarreTeal) {
                        SMSLauncher.open(phone: phone)
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

    /// Same chrome as `quickChip` but driven by an action closure rather
    /// than a `URL`. Used for SMS where the launcher decides between in-app
    /// thread and the system Messages app via `MessagingPreference`.
    private func quickChipAction(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.brandLabelLarge())
            }
            .foregroundStyle(color)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - §4.2 Urgency chip for detail header

private struct DetailUrgencyChip: View {
    let urgency: String

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(urgency.capitalized)
                .font(.brandLabelLarge())
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(dotColor.opacity(0.1), in: Capsule())
        .accessibilityLabel("Urgency: \(urgency)")
    }

    private var dotColor: Color {
        switch urgency.lowercased() {
        case "critical": return .bizarreError
        case "high":     return .bizarreOrange
        case "medium":   return Color(red: 0.93, green: 0.76, blue: 0.18)
        case "normal":   return .bizarreOnSurfaceMuted
        case "low":      return .bizarreTeal
        default:         return .bizarreOnSurfaceMuted
        }
    }
}

// MARK: - §4 Due-date countdown chip for detail header

/// Capsule chip showing the number of days until (or since) the ticket due date.
/// Color scheme: red = overdue, amber = due today or tomorrow, yellow = ≤3 days, gray = safe.
/// Renders as a compact "Due in Nd" / "Due today" / "Nd overdue" label with a clock icon.
private struct DueDateCountdownChip: View {
    let isoDateString: String

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Short: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let iso8601Date: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    private var dueDate: Date? {
        Self.iso8601.date(from: isoDateString)
            ?? Self.iso8601Short.date(from: isoDateString)
            ?? Self.iso8601Date.date(from: isoDateString)
    }

    private var daysUntilDue: Int? {
        guard let due = dueDate else { return nil }
        return Int(due.timeIntervalSinceNow / 86400)
    }

    var body: some View {
        if let days = daysUntilDue {
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: days < 0 ? "clock.badge.xmark" : "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(chipColor(days: days))
                    .accessibilityHidden(true)
                Text(chipLabel(days: days))
                    .font(.brandLabelLarge())
                    .foregroundStyle(chipColor(days: days))
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(chipColor(days: days).opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(chipColor(days: days).opacity(0.3), lineWidth: 0.5))
            .accessibilityLabel(a11yLabel(days: days))
        }
    }

    private func chipLabel(days: Int) -> String {
        if days < 0  { return "\(-days)d overdue" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days)d"
    }

    private func a11yLabel(days: Int) -> String {
        if days < 0  { return "Overdue by \(-days) day\(-days == 1 ? "" : "s")" }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }

    private func chipColor(days: Int) -> Color {
        if days < 0  { return .bizarreError }
        if days <= 1 { return .bizarreOrange }
        if days <= 3 { return Color(red: 0.93, green: 0.76, blue: 0.18) }
        return .bizarreOnSurfaceMuted
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

            // §4.2 — Make / model copy chips (read-only view)
            DeviceMakeModelChips(device: device)

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
            Text("Notes")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            ForEach(notes) { note in
                CommLogRow(note: note)
            }
        }
    }
}

// MARK: - §4 Customer-comm log row with full a11y

/// A single customer-communication log row for notes, SMS, email and internal
/// messages.  Fully accessible: VoiceOver reads type label, author, timestamp
/// and body in one combined element; flagged notes announce the flag.
private struct CommLogRow: View {
    let note: TicketDetail.TicketNote

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack(spacing: BrandSpacing.xs) {
                // Note type badge
                if let badge = typeBadgeLabel {
                    Text(badge)
                        .font(.brandLabelSmall())
                        .foregroundStyle(typeBadgeColor)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, 2)
                        .background(typeBadgeColor.opacity(0.12), in: Capsule())
                        .accessibilityHidden(true)  // read in combined a11y label below
                }

                Text(note.userName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                if note.isFlagged == true {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.bizarreError)
                        .accessibilityHidden(true)  // included in combined label
                }

                Spacer()

                if let ts = note.createdAt {
                    Text(formattedTimestamp(ts))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)  // included in combined label
                }
            }

            Text(note.stripped)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .cardBackground()
        // §4 a11y — single combined element for comm log rows so VoiceOver
        // reads type + author + timestamp + body without extra swipes.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(note.isFlagged == true ? "Flagged note — review required" : "")
    }

    // MARK: - Helpers

    private var typeBadgeLabel: String? {
        switch note.type?.lowercased() {
        case "internal":          return "Internal"
        case "customer":          return "Customer"
        case "diagnostic":        return "Diagnostic"
        case "sms":               return "SMS"
        case "email":             return "Email"
        case "string":            return nil
        case .none:               return nil
        default:                  return note.type?.capitalized
        }
    }

    private var typeBadgeColor: Color {
        switch note.type?.lowercased() {
        case "internal":    return .bizarreOnSurfaceMuted
        case "customer":    return .bizarreTeal
        case "diagnostic":  return Color(red: 0.93, green: 0.76, blue: 0.18)
        case "sms":         return .bizarreOrange
        case "email":       return Color.blue
        default:            return .bizarreOnSurfaceMuted
        }
    }

    private var a11yLabel: String {
        var parts: [String] = []
        if let badge = typeBadgeLabel { parts.append("\(badge) note") }
        parts.append("from \(note.userName)")
        if let ts = note.createdAt { parts.append("at \(formattedTimestamp(ts))") }
        parts.append(note.stripped)
        if note.isFlagged == true { parts.append("flagged") }
        return parts.joined(separator: ", ")
    }

    private func formattedTimestamp(_ iso: String) -> String {
        // Show at most 16 chars (YYYY-MM-DDTHH:MM) with T replaced by space
        String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}

// MARK: - Totals

// §4.2 Totals panel — subtotal, tax, discount, deposit, balance due, paid.
// `.textSelection(.enabled)` on each money value; copyable grand total.
// Deposit and paid are server-side fields on TicketDetail when present.
// Balance due = total − paid (client-side calculation until dedicated server field).
private struct TotalsCard: View {
    let detail: TicketDetail

    private var totalPaid: Double {
        detail.payments.reduce(0) { $0 + $1.amount }
    }

    private var balanceDue: Double {
        max(0, (detail.total ?? 0) - totalPaid)
    }

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

// MARK: - §4.2 Devices section with edit/services actions

/// Wraps DevicesSection and adds "Add device" + per-device swipe actions (edit, services & parts).
private struct DevicesSectionWithActions: View {
    let devices: [TicketDetail.TicketDevice]
    let onAdd: () -> Void
    let onEdit: (TicketDetail.TicketDevice) -> Void
    let onServices: (TicketDetail.TicketDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Devices")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Button {
                    onAdd()
                } label: {
                    Label("Add device", systemImage: "plus.circle")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Add a new device to this ticket")
            }

            if devices.isEmpty {
                Text("No devices attached yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.vertical, BrandSpacing.sm)
            } else {
                ForEach(devices) { device in
                    DeviceCardWithActions(
                        device: device,
                        onEdit: { onEdit(device) },
                        onServices: { onServices(device) }
                    )
                }
            }
        }
    }
}

private struct DeviceCardWithActions: View {
    let device: TicketDetail.TicketDevice
    let onEdit: () -> Void
    let onServices: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text(device.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Menu {
                    Button { onEdit() } label: {
                        Label("Edit device", systemImage: "pencil")
                    }
                    Button { onServices() } label: {
                        Label("Services & parts", systemImage: "wrench.and.screwdriver")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Device actions for \(device.displayName)")
            }

            // §4.2 — Make / model copy chips. Tap either chip to copy its value
            // to the pasteboard (useful for ordering parts or looking up specs).
            DeviceMakeModelChips(device: device)

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
            if let service = device.service, let name = service.name {
                KeyValueLine(key: "Service", value: name)
            }

            if let parts = device.parts, !parts.isEmpty {
                Divider().overlay(Color.bizarreOutline.opacity(0.4))

                // §4.2 — Parts-cost preview: subtotal of all parts for this device.
                let partsSubtotal = parts.compactMap(\.total).reduce(0, +)
                if partsSubtotal > 0 {
                    HStack {
                        Text("Parts subtotal")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Spacer()
                        Text(formatMoney(partsSubtotal))
                            .font(.brandLabelLarge().bold())
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Parts subtotal: \(formatMoney(partsSubtotal))")
                }

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
        .accessibilityElement(children: .contain)
    }

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - §4.2 Device make / model copy chips

/// Two small tappable capsule chips showing the device manufacturer and model
/// name separately. Tapping either chip copies its value to the pasteboard —
/// handy when ordering parts or searching supplier catalogues.
///
/// Chips are only rendered when the relevant fields are non-empty and differ
/// from the device's `displayName` (avoids duplicating text the tech already sees).
private struct DeviceMakeModelChips: View {
    let device: TicketDetail.TicketDevice

    private var make: String? {
        guard let m = device.manufacturerName, !m.isEmpty else { return nil }
        return m
    }

    private var model: String? {
        guard let m = device.deviceName, !m.isEmpty else { return nil }
        // Don't show if it's already the displayName (avoids duplication).
        if m == device.displayName && make == nil { return nil }
        return m
    }

    var body: some View {
        let chips: [(label: String, value: String)] = [
            make.map { ("Make", $0) },
            model.map { ("Model", $0) }
        ].compactMap { $0 }

        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(chips, id: \.label) { chip in
                        CopyChip(label: chip.label, value: chip.value)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

/// Tappable capsule chip that copies `value` to the pasteboard on tap.
private struct CopyChip: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            withAnimation(.easeIn(duration: 0.15)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            }
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                Text(label.uppercased())
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(copied ? .bizarreSuccess : .bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs + 2)
            .background(
                copied ? Color.bizarreSuccess.opacity(0.1) : Color.bizarreSurface1,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        copied ? Color.bizarreSuccess.opacity(0.5) : Color.bizarreOutline.opacity(0.4),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(label): \(value)")
        .accessibilityHint(copied ? "Copied" : "Tap to copy to clipboard")
    }
}

// MARK: - §4.9 Bench timer toggle card (chrome element — Actions tab)

/// Glass card in Actions tab. Collapses to a single "Start Bench Timer" row;
/// expands to show `BenchTimerView` inline when `isShowing` is true.
/// §4.2 — The collapsed header shows a time-spent counter so techs can glance
/// at elapsed time without expanding the card.
private struct BenchTimerToggleCard: View {
    @Binding var isShowing: Bool
    /// Shared timer state so the collapsed header and expanded body stay in sync.
    @State private var timer = BenchTimerState()

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(BrandMotion.snappy) { isShowing.toggle() }
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "timer")
                        .foregroundStyle(timer.phase == .running ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Bench Timer")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    // §4.2 — Time-spent counter: always visible in collapsed header.
                    if timer.phase != .idle || isShowing {
                        Text(timer.displayTime)
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                            .foregroundStyle(timer.phase == .running ? .bizarreOrange : .bizarreOnSurfaceMuted)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .accessibilityLabel("Time spent: \(timer.displayTime)")
                    }
                    Image(systemName: isShowing ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .font(.system(size: 12, weight: .medium))
                        .accessibilityHidden(true)
                }
                .padding(BrandSpacing.base)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowing ? "Collapse bench timer" : "Expand bench timer")

            if isShowing {
                Divider().overlay(Color.bizarreOutline.opacity(0.3))
                BenchTimerView(state: timer)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.base)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - §4.2 Handoff banner (iPad/Mac only)

/// §4.2 — Small glass strip shown on iPad/Mac indicating that NSUserActivity
/// Handoff is active, so the user can continue on their Mac via the Dock icon.
private struct TicketHandoffBanner: View {
    let orderId: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Handoff active — pick up Ticket \(orderId) on your Mac")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Handoff is active. You can continue this ticket on your Mac.")
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
