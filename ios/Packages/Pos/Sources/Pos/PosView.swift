#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Hardware
import Networking
import Persistence
import Sync
import Inventory
import Customers

// MARK: - PosPhase

/// Wave-5 phase machine for the POS root screen.
///
/// State transitions:
/// ```
///   .gate → .cart (customer selected/created/walk-in, or pickup loaded)
///   .cart → .tender(coordinator)
///   .tender → .receipt(payload)
///   .receipt → .gate ("New sale" button)
///   .gate / .cart → .repair(coordinator)
///   .repair → .cart (or .tender if deposit tendered inline)
/// ```
public enum PosPhase {
    /// Frame 1 — Customer gate (who is this sale for?).
    case gate
    /// Frame 2/3 — Items search + cart panel.
    case cart
    /// Frame 4 — Repair intake flow (4-step).
    case repair(PosRepairFlowCoordinator)
    /// Frame 5 — Tender method + amount entry.
    case tender(PosTenderCoordinator)
    /// Frame 6 — Receipt / post-sale confirmation.
    case receipt(PosReceiptPayload)
}

/// POS root screen. §16.4 wires the customer attach flow.
/// Wave-5 phase machine drives customer gate → cart → tender → receipt.
public struct PosView: View {
    // MARK: - Wave-5 phase machine

    /// Active POS phase. Default is `.gate` so every new session starts
    /// by asking "who is this sale for?".
    @State private var phase: PosPhase = .gate

    /// §16.28.1 bug 2 — post-gate sell-vs-service decision. Reset to
    /// `.undecided` whenever phase returns to `.gate` (next sale).
    @State private var pathChoice: PosPathChoice = .undecided

    /// Tracks when the transaction settled so `PosReceiptView` can fire
    /// its success haptic (`.sensoryFeedback(.success, trigger: paidAt)`).
    @State private var paidAt: Date = Date()

    // MARK: - Existing cart + session state

    @State private var cart = Cart()
    /// §16.12 — offline-aware checkout + cart persistence.
    @State private var cartVM = CartViewModel()
    @State private var showingOfflineQueue: Bool = false
    @State private var search: PosSearchViewModel
    @State private var showingCustomLine: Bool = false
    @State private var postSale: PosPostSaleViewModel?
    @State private var showingReturns: Bool = false
    @State private var editQuantityFor: CartItem?
    @State private var editPriceFor: CartItem?
    @State private var showingCartSheet: Bool = false
    /// §40 — Gift card / store credit sheet.
    @State private var showingGiftCardSheet: Bool = false
    @State private var showingCustomerPicker: Bool = false
    @State private var showingCreateCustomer: Bool = false
    /// §16.3 — Cart adjustment sheets
    @State private var showingDiscountSheet: Bool = false
    @State private var showingTipSheet: Bool = false
    @State private var showingFeesSheet: Bool = false
    /// §16.3 — Hold sheets
    @State private var showingHoldSheet: Bool = false
    @State private var showingResumeHoldsSheet: Bool = false
    @State private var holdToastMessage: String? = nil
    /// §16.10 / §39 — cash register drawer-lock gate. POS is sell-locked
    /// until an open session exists. `registerLoaded` prevents a flash of
    /// the open-sheet on first-render while the store is being read.
    @State private var registerSession: CashSessionRecord?
    @State private var registerLoaded: Bool = false
    @State private var showingOpenRegister: Bool = false
    @State private var showingCloseRegister: Bool = false
    @State private var showingZReport: Bool = false
    /// Snapshot of the session that was just closed so `ZReportView` has
    /// something to render after `registerSession` has been cleared.
    @State private var lastClosedSession: CashSessionRecord?
    /// §16.11 — No-sale manager PIN gate.
    @State private var showingNoSalePin: Bool = false
    /// §16.11 — Audit log viewer.
    @State private var showingAuditLog: Bool = false
    /// Active-cart toolbar — `Scan` primary action sheet.
    @State private var showingScanner: Bool = false
    /// §16.5 — v1 tender select + cash tender flow (retained, not deleted).
    @State private var showingTenderSelect: Bool = false
    @State private var cashTenderVM: CashTenderViewModel?
    @State private var tenderErrorMessage: String?
    /// §16.6 — Store-credit balance for the attached customer.
    /// Loaded lazily when the tender phase begins. Nil = not yet fetched or
    /// no customer attached. `PosTenderMethodPickerView` / `PosTenderAmountEntryView`
    /// fall back to "Avail. balance" subtitle when nil.
    // TODO(b2): wire via api.storeCredit(customerId:) once APIClient exposes the
    // GET /api/v1/store-credit/:customerId endpoint (§16.6).
    @State private var storeCreditCents: Int? = nil

    /// §16.1 / §16.2 / §16.4 — PosViewModel: permission gate, catalog filter,
    /// favorites, recently-sold, repair services, customer context.
    @State private var posVM = PosViewModel()

    /// §16.4 — Device-for-repair picker state. Presented when a service item
    /// is added to the cart and the customer has saved assets.
    @State private var showingDevicePicker: Bool = false
    /// The cart line that triggered the device picker; used to attach the
    /// selected device option via `PosDeviceAttachment`.
    @State private var devicePickerCartLineId: UUID? = nil

    /// §16.7 / §16.9 — the POS toolbar "Process return" entry and the
    /// post-sale receipt-send flow both need the live `APIClient`. Kept
    /// optional so preview / Mac-designed-for-iPad builds without auth
    /// still compile; both surfaces fall back to a typed "Coming soon"
    /// message when `api` is nil.
    private let api: APIClient?
    private let customerRepo: CustomerRepository?
    /// Closure-based DI for the cash drawer. AppServices passes
    /// `CashDrawer.shared.open` (or an `EscPosDrawerKick`-backed instance);
    /// previews and tests receive the default `NullCashDrawer`.
    private let cashDrawerOpen: @Sendable () async throws -> Void

    public init(
        repo: InventoryRepository? = nil,
        api: APIClient? = nil,
        customerRepo: CustomerRepository? = nil,
        userRole: PosUserRole = .preview,
        cashDrawerOpen: @escaping @Sendable () async throws -> Void = { throw CashDrawerError.notConnected }
    ) {
        if let repo {
            _search = State(wrappedValue: PosSearchViewModel(repo: repo))
        } else {
            _search = State(wrappedValue: PosSearchViewModel(repo: PosDisabledRepository()))
        }
        self.api = api
        self.customerRepo = customerRepo
        self.cashDrawerOpen = cashDrawerOpen
        _posVM = State(wrappedValue: PosViewModel(api: api, userRole: userRole))
    }

    public var body: some View {
        Group {
            // §16.1 Permission gate — checked before any POS surface renders.
            if !posVM.userRole.canAccessPos {
                PosAccessDeniedView(role: posVM.userRole)
            } else if !registerLoaded {
                // First-tick loading — avoid flashing the open-register
                // sheet before the store has answered.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if registerSession == nil {
                registerLockedPlaceholder
            } else {
                phaseBody
            }
        }
        .task { await search.load() }
        .task { await loadRegisterSession() }
        .task { await cartVM.restoreSnapshotIfAvailable(into: cart) }
        // §16.4 — Load customer context whenever the attached customer changes.
        .onChange(of: cart.customer?.id) { _, newId in
            Task { await posVM.loadCustomerContext(customerId: newId) }
        }
        // §16.4 — Apply tax exemption when context loads.
        .onChange(of: posVM.customerContext) { _, ctx in
            if ctx.isTaxExempt { posVM.applyTaxExemptionIfNeeded(to: cart) }
            if ctx.groupDiscountPercent != nil { posVM.applyGroupDiscountIfNeeded(to: cart) }
        }
        // §16.4 — Device picker for repair service items.
        .sheet(isPresented: $showingDevicePicker) {
            if let api, let customerId = cart.customer?.id, customerId > 0 {
                PosDevicePickerSheet(
                    customerId: customerId,
                    repository: PosDevicePickerRepositoryImpl(api: api),
                    onConfirm: { option in
                        if let lineId = devicePickerCartLineId {
                            let attachment = PosDeviceAttachment(
                                cartLineId: lineId,
                                deviceOptionId: {
                                    if case .asset(let id, _, _) = option { return id }
                                    return nil
                                }()
                            )
                            AppLog.pos.info("PosVM: device attached — \(attachment.deviceOptionId.map { String($0) } ?? "none", privacy: .public)")
                        }
                        devicePickerCartLineId = nil
                    },
                    onAddNew: {
                        devicePickerCartLineId = nil
                        // Deferred: navigate to device creation within Customers package.
                        tenderErrorMessage = "Device creation is available in the Customer profile."
                    }
                )
            }
        }
        .sheet(isPresented: $showingOfflineQueue) {
            OfflineSaleQueueView()
        }
        .overlay(alignment: .top) {
            // §16.12 — offline sale indicator chip.
            if SyncManager.shared.pendingCount > 0 {
                OfflineSaleIndicator(queueCount: SyncManager.shared.pendingCount) {
                    showingOfflineQueue = true
                }
                .padding(.top, BrandSpacing.sm)
                .animation(BrandMotion.snappy, value: SyncManager.shared.pendingCount)
            }
        }
        .overlay(alignment: .bottom) {
            // §16.12 — offline sale toast
            if let msg = cartVM.toastMessage {
                Text(msg)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, BrandSpacing.xxl)
                    .transition(.opacity)
                    .accessibilityIdentifier("pos.offlineToast")
            }
        }
        .fullScreenCover(isPresented: $showingOpenRegister) {
            // §16.10 — drawer-lock sheet. Cashier ID 0 is a placeholder
            // until the `/auth/me` propagation path wires the real user
            // ID into AppState. Sessions are local-first anyway, so the
            // record can be re-stamped on server sync (see §39).
            OpenRegisterSheet(
                cashierId: 0,
                onOpened: { record in
                    registerSession = record
                    showingOpenRegister = false
                    BrandHaptics.success()
                },
                onCancel: {
                    // Leave the sheet dismissed; the register-locked
                    // placeholder stays up so the cashier can still tap
                    // "Open register" when ready. Prevents accidental
                    // sales on an unopened drawer.
                    showingOpenRegister = false
                }
            )
        }
        .sheet(isPresented: $showingCloseRegister) {
            if let session = registerSession {
                CloseRegisterSheet(
                    session: session,
                    expectedCents: session.openingFloat + cart.totalCents,
                    closedBy: 0,
                    onClosed: { closed in
                        if closed.isOpen {
                            registerSession = closed
                        } else {
                            lastClosedSession = closed
                            registerSession = nil
                        }
                        showingCloseRegister = false
                        if !closed.isOpen {
                            showingZReport = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingZReport) {
            if let session = registerSession ?? lastClosedSession {
                ZReportView(session: session)
            }
        }
        .sheet(isPresented: $showingCustomLine) {
            PosCustomLineSheet { item in cart.add(item) }
        }
        .sheet(item: $postSale) { vm in
            PosPostSaleView(vm: vm)
        }
        .sheet(isPresented: $showingTenderSelect) {
            PosTenderSelectSheet(totalCents: cart.totalCents) {
                showingTenderSelect = false
                openCashTender()
            }
        }
        .sheet(item: $cashTenderVM) { vm in
            PosCashTenderSheet(
                vm: vm,
                onCompleted: { result in
                    cashTenderVM = nil
                    postSale = buildPostSaleViewModel(
                        methodLabel: result.methodLabel,
                        methodAmountCents: result.receivedCents,
                        invoiceId: result.invoiceId
                    )
                },
                onBack: {
                    cashTenderVM = nil
                    showingTenderSelect = true
                }
            )
        }
        .overlay(alignment: .bottom) {
            if let err = tenderErrorMessage {
                Text(err)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, BrandSpacing.xxl)
                    .transition(.opacity)
                    .onTapGesture { tenderErrorMessage = nil }
                    .accessibilityIdentifier("pos.tenderErrorToast")
            }
        }
        .sheet(isPresented: $showingReturns) {
            PosReturnsView(api: api)
        }
        .sheet(item: $editQuantityFor) { item in
            PosEditQuantitySheet(current: item.quantity) { qty in
                cart.update(id: item.id, quantity: qty)
            }
        }
        .sheet(item: $editPriceFor) { item in
            let cents = CartMath.toCents(item.unitPrice)
            PosEditPriceSheet(currentCents: cents) { newCents in
                cart.update(id: item.id, unitPriceCents: newCents)
            }
        }
        .sheet(isPresented: $showingCustomerPicker) {
            if let customerRepo {
                PosCustomerPickerSheet(
                    repo: customerRepo,
                    onPick: { picked in
                        cart.attach(customer: picked)
                        BrandHaptics.success()
                    },
                    onCreateNew: api == nil ? nil : { showingCreateCustomer = true }
                )
            } else {
                PosCustomerPickerUnavailable { showingCustomerPicker = false }
            }
        }
        .sheet(isPresented: $showingCreateCustomer) {
            if let api {
                CustomerCreateView(api: api) { id, vm in
                    let attached = PosCustomerNameFormatter.attachPayload(
                        id: id,
                        firstName: vm.firstName,
                        lastName: vm.lastName,
                        email: vm.email,
                        phone: vm.phone,
                        mobile: vm.mobile,
                        organization: vm.organization
                    )
                    cart.attach(customer: attached)
                    BrandHaptics.success()
                    // When arriving from the gate, advance to cart.
                    if case .gate = phase { phase = .cart }
                }
            }
        }
        .sheet(isPresented: $showingCartSheet) {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: { showingCartSheet = false; startChargeV5() },
                    onOpenDrawer: openDrawer,
                    onChangeCustomer: customerRepo == nil ? nil : {
                        showingCartSheet = false
                        showingCustomerPicker = true
                    },
                    onRemoveCustomer: { cart.detachCustomer() },
                    editQuantityFor: $editQuantityFor,
                    editPriceFor: $editPriceFor,
                    onShowDiscount: { showingDiscountSheet = true },
                    onShowTip: { showingTipSheet = true },
                    onShowFees: { showingFeesSheet = true },
                    customerContext: posVM.customerContext,
                    loyaltyEarnedPoints: posVM.loyaltyPointsPreview(cartTotalCents: cart.totalCents)
                )
                .navigationTitle("Cart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCartSheet = false }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            cart.clear(); showingCartSheet = false
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                        .disabled(cart.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // §16.3 — Adjustment sheets
        .sheet(isPresented: $showingDiscountSheet) {
            PosCartDiscountSheet(cart: cart)
        }
        .sheet(isPresented: $showingTipSheet) {
            PosCartTipSheet(cart: cart)
        }
        .sheet(isPresented: $showingFeesSheet) {
            PosCartFeesSheet(cart: cart)
        }
        // §16.11 — No-sale manager PIN gate.
        .sheet(isPresented: $showingNoSalePin) {
            ManagerPinSheet(
                reason: "Open drawer without sale",
                onApproved: { managerId in
                    openDrawer()
                    Task {
                        try? await PosAuditLogStore.shared.record(
                            event: PosAuditEntry.EventType.noSale,
                            cashierId: 0,
                            managerId: managerId,
                            reason: "No-sale drawer open"
                        )
                    }
                },
                onCancelled: {}
            )
        }
        // §16.11 — Audit log viewer.
        .sheet(isPresented: $showingAuditLog) {
            NavigationStack {
                PosAuditLogView()
            }
        }
        // §16.3 — Hold sheets
        .sheet(isPresented: $showingHoldSheet) {
            PosHoldCartSheet(cart: cart, api: api) { holdId in
                showingHoldSheet = false
                holdToastMessage = "Cart saved (hold #\(holdId))."
            }
        }
        .sheet(isPresented: $showingResumeHoldsSheet) {
            PosResumeHoldsSheet(cart: cart, api: api) {
                showingResumeHoldsSheet = false
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = holdToastMessage {
                Text(msg)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, BrandSpacing.xl)
                    .transition(.opacity)
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            holdToastMessage = nil
                        }
                    }
            }
        }
    }

    // MARK: - Wave-5 phase body

    /// Routes to the correct surface for the active `PosPhase`.
    @ViewBuilder
    private var phaseBody: some View {
        switch phase {
        case .gate:
            gateView

        case .cart:
            if shouldShowPathChoice {
                pathChoiceView
            } else if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }

        case .repair(let coordinator):
            if let api {
                if Platform.isCompact {
                    // iPhone: full-screen NavigationStack via RepairFlowAdapter.
                    RepairFlowAdapter(
                        coordinator: coordinator,
                        devicePickerVM: PosDevicePickerViewModel(
                            repository: PosDevicePickerRepositoryImpl(api: api)
                        )
                    )
                } else {
                    // iPad: catalog dim + cart "in progress" + step in inspector
                    // pane (mockup pos-ipad-mockups.html frames 1b–1e).
                    iPadRepairLayout(coordinator: coordinator, api: api)
                }
            } else {
                // No API — cannot run repair flow; fall back to cart.
                Color.clear.onAppear { phase = .cart }
            }

        case .tender(let coordinator):
            tenderView(coordinator: coordinator)

        case .receipt(let payload):
            receiptView(payload: payload)
        }
    }

    // MARK: - Gate view (Frame 1)

    private var gateView: some View {
        PosGateView(vm: makeGateVM())
    }

    // MARK: - Path choice (sell vs service · §16.28.1 bug 2)

    /// Show the post-gate sell-vs-service decision when:
    /// - Customer is attached (gate already cleared)
    /// - Cart is empty (no items already chosen)
    /// - Cashier hasn't picked a path yet this sale
    private var shouldShowPathChoice: Bool {
        cart.hasCustomer && cart.isEmpty && pathChoice == .undecided
    }

    @ViewBuilder
    private var pathChoiceView: some View {
        let displayName = cart.customer?.displayName ?? "this customer"
        PosPathChoiceView(
            customerName: displayName,
            onSell: { pathChoice = .selling },
            onStartRepair: startRepairFlow
        )
    }

    /// Build a `PosRepairFlowCoordinator`, attach it to the phase machine,
    /// and route `onCancel` / `onComplete` back to `.cart` (or `.gate` for
    /// a fresh sale on completion).
    @MainActor
    private func startRepairFlow() {
        guard let api else {
            // No API — cannot run repair flow; surface a typed message
            // (parity with PosPhase.repair fallback in phaseBody).
            tenderErrorMessage = "Repair check-in unavailable: no server connection."
            return
        }
        let customerId = cart.customer?.id ?? 0
        let coordinator = PosRepairRouter.makeCoordinator(
            customerId: customerId,
            customerDisplayName: cart.customer?.displayName,
            api: api,
            onCancel: {
                pathChoice = .undecided
                phase = .cart
            },
            onComplete: { _ in
                // Deposit tendered (or quote saved) → return to cart so
                // the cashier can either keep selling parts or charge.
                pathChoice = .selling
                phase = .cart
            }
        )
        phase = .repair(coordinator)
    }

    /// Reset the path choice on every return to gate so the next sale
    /// starts fresh. Called from `handleGateRoute` and the receipt's
    /// "Next sale" callback.
    private func resetPathChoice() {
        pathChoice = .undecided
    }

    private func makeGateVM() -> PosGateViewModel {
        let customerRepo: any CustomerRepository = self.customerRepo ?? PosGateNullCustomerRepository()
        let ticketsRepo: any GateTicketsRepository = {
            if let api { return DefaultGateTicketsRepository(api: api) }
            return PosGateNullTicketsRepository()
        }()
        let vm = PosGateViewModel(customerRepo: customerRepo, ticketsRepo: ticketsRepo)
        vm.onRouteSelected = { route in
            self.handleGateRoute(route)
        }
        return vm
    }

    @MainActor
    private func handleGateRoute(_ route: PosGateRoute) {
        switch route {
        case .existing(let id):
            // Load the customer detail and advance to .cart.
            Task { @MainActor in
                if let api, let detail = try? await api.customer(id: id) {
                    let customer = PosCustomer(
                        id: detail.id,
                        displayName: detail.displayName,
                        email: detail.email,
                        phone: detail.phone ?? detail.mobile
                    )
                    self.cart.attach(customer: customer)
                    BrandHaptics.success()
                }
                phase = .cart
            }

        case .createNew:
            // Present create-customer sheet; on success attach + advance.
            showingCreateCustomer = true
            // Phase transitions to .cart inside the sheet's onComplete closure
            // (see CustomerCreateView integration below).

        case .walkIn:
            self.cart.attach(customer: .walkIn)
            BrandHaptics.success()
            phase = .cart

        case .openPickup(let ticketId):
            // Load the ticket as a pre-built cart and advance to .cart.
            Task { @MainActor in
                // The cart is pre-loaded from the ticket; advance to cart phase.
                // Full ticket→cart mapping requires the Tickets package which
                // PosView does not import. We advance to .cart and let the
                // CartViewModel / PosCartPanel surface the ticket context.
                _ = ticketId // consumed by the pickup coordinator when implemented
                phase = .cart
            }
        }
    }

    // MARK: - Tender view (Frame 5)

    @ViewBuilder
    private func tenderView(coordinator: PosTenderCoordinator) -> some View {
        Group {
            if coordinator.stage == .confirmed {
                // Confirmed — build receipt payload and advance.
                Color.clear
                    .onAppear {
                        advanceToReceipt(from: coordinator)
                    }
            } else if coordinator.method != nil {
                PosTenderAmountEntryView(
                    coordinator: coordinator,
                    storeCreditBalanceCents: storeCreditCents
                )
                .onChange(of: coordinator.stage) { _, new in
                    if new == .confirmed {
                        advanceToReceipt(from: coordinator)
                    }
                }
            } else {
                PosTenderMethodPickerView(
                    coordinator: coordinator,
                    loyaltyTierLabel: nil,
                    storeCreditCents: storeCreditCents,
                    bottomBar: AnyView(EmptyView())
                )
            }
        }
        .task { await loadStoreCredit() }
    }

    /// §16.6 — Loads the attached customer's store-credit balance from the server.
    /// Silently no-ops when no customer is attached or API is unavailable.
    // TODO(b2): implement once APIClient exposes storeCredit(customerId:) for
    // GET /api/v1/store-credit/:customerId (§16.6). Current value stays nil,
    // causing PosTenderAmountEntryView to show the generic "Avail. balance" subtitle.
    private func loadStoreCredit() async {
        guard let customer = cart.customer, let customerId = customer.id, customerId > 0 else { return }
        // TODO(b2): storeCreditCents = try? await api?.storeCredit(customerId: customerId)
        _ = customerId // suppress unused-variable warning until API extension lands
    }

    private func advanceToReceipt(from coordinator: PosTenderCoordinator) {
        guard let result = coordinator.confirmResult else { return }
        let methodLabel = coordinator.appliedTenders.first.map { $0.method.displayName } ?? "Card"
        let changeCents = result.changeCents > 0 ? result.changeCents : nil
        let payload = PosReceiptPayload(
            invoiceId: result.invoiceId,
            amountPaidCents: result.totalCents,
            changeGivenCents: changeCents,
            methodLabel: methodLabel,
            customerPhone: cart.customer?.phone,
            customerEmail: cart.customer?.email
        )
        paidAt = Date()
        phase = .receipt(payload)
    }

    // MARK: - Receipt view (Frame 6)

    private func receiptView(payload: PosReceiptPayload) -> some View {
        let receiptText = PosReceiptRenderer.text(
            PosReceiptPayloadBuilder.build(
                cart: cart,
                methodLabel: payload.methodLabel,
                methodAmountCents: payload.amountPaidCents
            )
        )
        let vm = PosReceiptViewModel(
            payload: payload,
            api: api,
            onNextSale: {
                self.cart.clear()
                self.pathChoice = .undecided
                self.phase = .gate
            }
        )
        return PosReceiptView(vm: vm, receiptText: receiptText, paidAt: paidAt)
            .posCartCollapse(isCollapsed: true)
    }

    // MARK: - v5 charge entry point

    /// Called from cart's "Charge" button when the wave-5 phase machine is active.
    private func startChargeV5() {
        guard !cart.isEmpty, let api else {
            // Fall back to v1 flow when API not available.
            startCharge()
            return
        }
        BrandHaptics.tapMedium()
        Task { @MainActor in
            let handledOffline = await cartVM.checkoutIfOffline(
                cart: cart,
                cashSession: registerSession
            )
            if handledOffline {
                BrandHaptics.success()
                await cartVM.saveSnapshot(cart: cart, cashSessionId: registerSession?.id)
                return
            }
            let idempKey = UUID().uuidString
            guard let request = try? PosTransactionMapper.request(
                from: cart,
                paymentMethod: "card",
                paymentAmountCents: cart.totalCents,
                idempotencyKey: idempKey
            ) else {
                tenderErrorMessage = "Cart contains custom lines that cannot be processed."
                return
            }
            let coordinator = PosTenderCoordinator(
                totalCents: cart.totalCents,
                baseRequest: request,
                api: api
            )
            phase = .tender(coordinator)
        }
    }

    // MARK: - iPad inspector state

    /// The cart line currently open in the inspector pane. `nil` = inspector
    /// closed. Set by tapping a line in `PosIPadCartPanel`.
    @State private var editingCartItem: CartItem?

    /// Ephemeral edit buffers for the inspector pane — mirrors the selected
    /// `CartItem` fields while the cashier makes changes before Save.
    @State private var inspectorQty: Int = 1
    @State private var inspectorDiscountCents: Int = 0
    @State private var inspectorNote: String = ""

    // MARK: - Cart layouts (Frame 2/3)

    private var compactLayout: some View {
        NavigationStack {
            PosSearchPanel(
                search: search,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                showsCustomerCTAs: !cart.hasCustomer,
                onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                onCreateCustomer: api == nil ? nil : { showingCreateCustomer = true },
                onFindCustomer: customerRepo == nil ? nil : { showingCustomerPicker = true },
                posVM: posVM
            )
            .navigationTitle("POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { posToolbar }
            .safeAreaInset(edge: .bottom) {
                if !cart.isEmpty {
                    CartPill(
                        itemCount: cart.items.reduce(0) { $0 + $1.quantity },
                        totalCents: cart.totalCents,
                        customer: cart.customer,
                        onExpand: { showingCartSheet = true }
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.sm)
                }
            }
        }
    }

    /// iPad regular layout — `PosRegisterLayout` two-column split with an
    /// inspector pane that slides in from the trailing edge when a cart line
    /// is tapped for editing.
    ///
    /// Layout geometry:
    ///   - Left ~65 % — catalog (search + tile grid)
    ///   - Right ~35 % — condensed cart totals panel
    ///   - Trailing overlay — inspector pane (slides over the cart column)
    private var regularLayout: some View {
        NavigationStack {
            PosRegisterLayout(
                catalogFraction: 0.65,
                inspectorActive: editingCartItem != nil
            ) {
                // ── Topbar slot ───────────────────────────────────────
                // Empty: SwiftUI nav-bar already hosts posToolbar below.
                Color.clear.frame(height: 0)
            } catalog: {
                // ── Catalog slot ──────────────────────────────────────
                PosSearchPanel(
                    search: search,
                    onPick: pick,
                    onAddCustom: { showingCustomLine = true },
                    showsCustomerCTAs: !cart.hasCustomer,
                    onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                    onCreateCustomer: api == nil ? nil : { showingCreateCustomer = true },
                    onFindCustomer: customerRepo == nil ? nil : { showingCustomerPicker = true },
                    posVM: posVM
                )
            } cart: {
                // ── Cart slot (condensed iPad panel) ──────────────────
                // Cart-row tap → opens inspector pane (W2-MIGRATE gap).
                PosIPadCartPanel(
                    cart: cart,
                    onCharge: startChargeV5,
                    onEditItem: { item in editingCartItem = item },
                    editingItemId: editingCartItem?.id
                )
            } inspector: {
                // ── Inspector slot (sliding pane) ─────────────────────
                if let item = editingCartItem {
                    iPadInspectorPane(item: item)
                } else {
                    Color.clear
                }
            }
            .animation(BrandMotion.snappy, value: editingCartItem?.id)
            .navigationTitle("POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { posToolbar }
        }
    }

    // MARK: - iPad repair-flow layout (PosPhase.repair on regular size class)

    /// iPad-only routing for `PosPhase.repair`. Matches mockup spec
    /// `pos-ipad-mockups.html` frames 1b–1e: items area dims with a
    /// "Creating ticket…" placeholder, cart column shows a draft-state
    /// "Repair ticket — in progress" placeholder with a per-step disabled
    /// charge button, and the active repair step view slides into the
    /// trailing inspector pane with a Cancel + Continue footer.
    @ViewBuilder
    private func iPadRepairLayout(coordinator: PosRepairFlowCoordinator,
                                   api: APIClient) -> some View {
        let devicePickerVM = PosDevicePickerViewModel(
            repository: PosDevicePickerRepositoryImpl(api: api)
        )
        VStack(spacing: 0) {
            // Mockup spec — thin progress bar fills 25/50/75/100% per step.
            ProgressView(value: coordinator.currentStep.progressPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(Color.bizarrePrimary)
                .frame(height: 2)
                .accessibilityLabel(coordinator.currentStep.accessibilityDescription)
            PosRegisterLayout(
                catalogFraction: 0.65,
                inspectorActive: true
            ) {
                Color.clear.frame(height: 0)
            } catalog: {
                iPadRepairCatalogPlaceholder(coordinator: coordinator)
            } cart: {
                iPadRepairCartPlaceholder(coordinator: coordinator)
            } inspector: {
                iPadRepairInspectorPane(
                    coordinator: coordinator,
                    devicePickerVM: devicePickerVM
                )
            }
        }
        .animation(BrandMotion.snappy, value: coordinator.currentStep)
        .toolbar { repairTopbarPrincipal(coordinator: coordinator) }
    }

    /// Mockup principal title block — `New repair · <customer>` plus
    /// `Step X of 4 — <step name> · <device>` per `pos-ipad-mockups.html`.
    @ToolbarContentBuilder
    private func repairTopbarPrincipal(coordinator: PosRepairFlowCoordinator) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text("New repair · \(cart.customer?.displayName ?? "Walk-in")")
                    .font(.headline)
                    .foregroundStyle(Color.bizarreOnSurface)
                    .lineLimit(1)
                Text(coordinator.currentStep.accessibilityDescription)
                    .font(.caption2)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Items column — dimmed centered "Creating ticket…" hint per mockup
    /// (`pos-ipad-mockups.html` line 1741).
    private func iPadRepairCatalogPlaceholder(coordinator: PosRepairFlowCoordinator) -> some View {
        VStack(spacing: 12) {
            Text("🧾").font(.system(size: 56))
            Text("Creating repair ticket…")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Text(coordinator.currentStep.accessibilityDescription)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .opacity(0.45)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// Cart column — header + repair-in-progress placeholder + disabled
    /// per-step charge button (mockup line 1750-1768).
    private func iPadRepairCartPlaceholder(coordinator: PosRepairFlowCoordinator) -> some View {
        VStack(spacing: 0) {
            if let customer = cart.customer {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(customer.displayName)
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Repair ticket — in progress")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    }
                    Spacer(minLength: BrandSpacing.xs)
                    Text("Draft")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.bizarreWarning.opacity(0.18), in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                Divider().background(.bizarreOutline)
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Text("🔧").font(.system(size: 40))
                Text("Complete the inspector to start adding parts.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
            Button(action: {}) {
                Text(repairStepDisabledChargeLabel(coordinator.currentStep))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .disabled(true)
            .accessibilityIdentifier("pos.ipad.repair.disabledCharge")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func repairStepDisabledChargeLabel(_ step: RepairStep) -> String {
        switch step {
        case .pickDevice:      return "Pick device first"
        case .describeIssue:   return "Describe issue first"
        case .diagnosticQuote: return "Set diagnostic & quote first"
        case .deposit:         return "Pay deposit first"
        }
    }

    /// Inspector pane — hosts the active repair step view + footer with
    /// Cancel + Continue (per mockup line 1809-1812).
    @ViewBuilder
    private func iPadRepairInspectorPane(coordinator: PosRepairFlowCoordinator,
                                          devicePickerVM: PosDevicePickerViewModel) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(coordinator.currentStep.navigationTitle)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    if let name = coordinator.customerDisplayName {
                        Text("\(coordinator.currentStep.accessibilityDescription) · \(name)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        Text(coordinator.currentStep.accessibilityDescription)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer(minLength: BrandSpacing.xs)
                Button {
                    coordinator.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Close repair flow")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.top, BrandSpacing.md)
            .padding(.bottom, BrandSpacing.sm)

            Divider().background(.bizarreOutline)

            // Step body
            ScrollView {
                Group {
                    switch coordinator.currentStep {
                    case .pickDevice:
                        PosRepairDevicePickerView(coordinator: coordinator,
                                                   devicePickerVM: devicePickerVM)
                    case .describeIssue:
                        PosRepairSymptomView(coordinator: coordinator)
                    case .diagnosticQuote:
                        PosRepairQuoteView(coordinator: coordinator)
                    case .deposit:
                        PosRepairDepositView(coordinator: coordinator)
                    }
                }
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
            }

            Divider().background(.bizarreOutline)

            // Footer — Cancel + Skip (skippable steps only) + Continue
            HStack(spacing: BrandSpacing.sm) {
                Button(role: .destructive) {
                    coordinator.cancel()
                } label: {
                    Text("Cancel")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pos.ipad.repair.cancel")

                // Skip — only for steps where mockup CI-3 / CI-4 declares skippable
                // (.describeIssue, .diagnosticQuote). Pick-device + Deposit required.
                if coordinator.currentStep == .describeIssue ||
                   coordinator.currentStep == .diagnosticQuote {
                    Button {
                        coordinator.skipCurrent()
                    } label: {
                        Text("Skip")
                            .font(.brandTitleSmall())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BrandSpacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOnSurfaceMuted)
                    .accessibilityIdentifier("pos.ipad.repair.skip")
                }

                Button {
                    coordinator.advance()
                } label: {
                    Text(repairContinueLabel(coordinator.currentStep))
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(coordinator.isLoading)
                .accessibilityIdentifier("pos.ipad.repair.continue")
            }
            .padding(BrandSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bizarreSurface1)
    }

    private func repairContinueLabel(_ step: RepairStep) -> String {
        switch step {
        case .pickDevice:      return "Continue → issue"
        case .describeIssue:   return "Continue → quote"
        case .diagnosticQuote: return "Continue → deposit"
        case .deposit:         return "Confirm deposit"
        }
    }

    /// The inspector pane rendered inline (not as a sheet) when a cart line
    /// is tapped on iPad. Matches mockup screen 3: qty stepper / unit price
    /// display / line discount / note field / Remove + Save actions.
    @ViewBuilder
    private func iPadInspectorPane(item: CartItem) -> some View {
        VStack(spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(item.name)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    if let sku = item.sku {
                        Text("SKU \(sku)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer(minLength: BrandSpacing.xs)
                Button {
                    editingCartItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close inspector")
                .accessibilityIdentifier("pos.inspector.close")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface2)

            Divider().background(.bizarreOutline)

            ScrollView {
                VStack(spacing: 0) {
                    // ── Qty stepper ───────────────────────────────────────
                    inspectorRow {
                        HStack {
                            Text("Qty")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            HStack(spacing: 0) {
                                Button {
                                    if inspectorQty > 1 { inspectorQty -= 1 }
                                } label: {
                                    Image(systemName: "minus")
                                        .frame(width: DesignTokens.Touch.minTargetSide,
                                               height: DesignTokens.Touch.minTargetSide)
                                }
                                .buttonStyle(.plain)
                                .disabled(inspectorQty <= 1)
                                .accessibilityLabel("Decrease quantity")

                                Text("\(inspectorQty)")
                                    .font(.brandTitleMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                    .monospacedDigit()
                                    .frame(minWidth: 36)

                                Button {
                                    inspectorQty += 1
                                } label: {
                                    Image(systemName: "plus")
                                        .frame(width: DesignTokens.Touch.minTargetSide,
                                               height: DesignTokens.Touch.minTargetSide)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Increase quantity")
                            }
                            .foregroundStyle(.bizarreOrange)
                            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                        }
                    }
                    Divider().background(.bizarreOutline)

                    // ── Unit price (display only — tap editPriceFor to edit) ──
                    inspectorRow {
                        HStack {
                            Text("Unit price")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(CartMath.formatCents(CartMath.toCents(item.unitPrice)))
                                .font(.brandHeadlineMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .monospacedDigit()
                        }
                    }
                    Divider().background(.bizarreOutline)

                    // ── Line discount ─────────────────────────────────────
                    inspectorRow {
                        HStack {
                            Text("Line discount")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            if inspectorDiscountCents > 0 {
                                HStack(spacing: BrandSpacing.xs) {
                                    Text("−\(CartMath.formatCents(inspectorDiscountCents))")
                                        .font(.brandBodyLarge())
                                        .foregroundStyle(.bizarreTeal)
                                        .monospacedDigit()
                                    Button {
                                        inspectorDiscountCents = 0
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.footnote)
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove discount")
                                }
                            } else {
                                Button("+ Apply") {
                                    showingDiscountSheet = true
                                }
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreTeal)
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("pos.inspector.applyDiscount")
                            }
                        }
                    }
                    Divider().background(.bizarreOutline)

                    // ── Note field ────────────────────────────────────────
                    inspectorRow {
                        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                            Text("Note")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            TextField("Add a note for the receipt…", text: $inspectorNote, axis: .vertical)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(3, reservesSpace: true)
                                .padding(BrandSpacing.sm)
                                .background(Color.bizarreOnSurface.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5))
                                .accessibilityIdentifier("pos.inspector.note")
                        }
                    }
                }
            }

            Divider().background(.bizarreOutline)

            // ── Footer: Remove + Save ─────────────────────────────────────
            HStack(spacing: BrandSpacing.sm) {
                Button(role: .destructive) {
                    cart.removeLine(id: item.id)
                    editingCartItem = nil
                    BrandHaptics.tap()
                } label: {
                    Text("Remove")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityIdentifier("pos.inspector.remove")

                Button {
                    cart.update(id: item.id, quantity: inspectorQty)
                    if inspectorDiscountCents != item.discountCents {
                        cart.update(id: item.id, discountCents: inspectorDiscountCents)
                    }
                    if inspectorNote != (item.notes ?? "") {
                        cart.update(id: item.id, notes: inspectorNote)
                    }
                    editingCartItem = nil
                    BrandHaptics.success()
                } label: {
                    Text("Save")
                        .font(.brandTitleSmall())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("pos.inspector.save")
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1)
        }
        .background(Color.bizarreSurface1.ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, x: -4, y: 0)
        .padding(.vertical, BrandSpacing.sm)
        .padding(.trailing, BrandSpacing.xs)
        .onAppear {
            inspectorQty = item.quantity
            inspectorDiscountCents = item.discountCents
            inspectorNote = item.notes ?? ""
        }
        .onChange(of: item.id) { _, _ in
            inspectorQty = item.quantity
            inspectorDiscountCents = item.discountCents
            inspectorNote = item.notes ?? ""
        }
        .accessibilityIdentifier("pos.inspector")
    }

    /// Uniform padding wrapper for each inspector section row.
    @ViewBuilder
    private func inspectorRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mockup principal title — `New sale · <customer>` when one is attached,
    /// else falls back to `POS`.
    private var activeCartTitle: String {
        if let name = cart.customer?.displayName, !name.isEmpty {
            return "New sale · \(name)"
        }
        return "POS · new sale"
    }

    /// Subline — line count + register status. Mockup uses
    /// `iPhone 14 Pro · 3 lines · autocreating ticket #draft`. We render the
    /// device summary when present, otherwise just the line count and
    /// register-open hint.
    private var activeCartSubtitle: String {
        let lineCount = cart.items.count
        let lineLabel = lineCount == 1 ? "1 line" : "\(lineCount) lines"
        if registerSession != nil {
            return "Register open · \(lineLabel)"
        }
        return lineLabel
    }

    private var posToolbar: some ToolbarContent {
        Group {
            // Mockup principal title block — `New sale · <customer>` + sub.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(activeCartTitle)
                        .font(.headline)
                        .foregroundStyle(Color.bizarreOnSurface)
                        .lineLimit(1)
                    Text(activeCartSubtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
            // Primary — 📷 Scan (mockup `tb-btn primary`).
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }
                .accessibilityLabel("Scan barcode")
            }
            // Hold direct button (mockup `⏸ Hold (⌘H)`).
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingHoldSheet = true
                } label: {
                    Image(systemName: "pause.circle")
                }
                .keyboardShortcut("H", modifiers: .command)
                .disabled(cart.isEmpty)
                .accessibilityLabel("Hold cart")
            }
            // §16.3 — overflow "⋯" menu. Keeps the toolbar from crowding.
            // Uses `.topBarTrailing` (not `.secondaryAction`) because on iPad
            // SwiftUI wraps `.secondaryAction` items in its own auto-generated
            // "⋯" button — pairing that with a `Menu` here produced a nested
            // double-ellipsis (tap once → opens a menu whose only entry is
            // another ellipsis). `.topBarTrailing` places our Menu directly
            // in the bar so a single tap reveals the sections.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // §16.14 — payment shortcut
                    Section("Checkout") {
                        Button {
                            startCharge()
                        } label: {
                            Label("Charge cart", systemImage: "creditcard")
                        }
                        .keyboardShortcut("P", modifiers: .command)
                        .disabled(cart.isEmpty)
                        .accessibilityIdentifier("pos.toolbar.charge")

                        if customerRepo != nil {
                            Button {
                                showingCustomerPicker = true
                            } label: {
                                Label("Attach customer", systemImage: "person.crop.circle.badge.plus")
                            }
                            .keyboardShortcut("K", modifiers: .command)
                            .accessibilityIdentifier("pos.toolbar.attachCustomer")
                        }
                    }
                    // Adjustments group
                    Section("Cart adjustments") {
                        Button {
                            showingDiscountSheet = true
                        } label: {
                            Label("Add discount", systemImage: "tag")
                        }
                        .keyboardShortcut("D", modifiers: [.command, .shift])
                        .disabled(cart.isEmpty)
                        .accessibilityIdentifier("pos.toolbar.discount")

                        Button {
                            showingTipSheet = true
                        } label: {
                            Label("Add tip", systemImage: "hand.thumbsup")
                        }
                        .keyboardShortcut("T", modifiers: [.command, .shift])
                        .disabled(cart.isEmpty)
                        .accessibilityIdentifier("pos.toolbar.tip")

                        Button {
                            showingFeesSheet = true
                        } label: {
                            Label("Add fee", systemImage: "plus.circle")
                        }
                        .keyboardShortcut("F", modifiers: [.command, .shift])
                        .disabled(cart.isEmpty)
                        .accessibilityIdentifier("pos.toolbar.fees")
                    }
                    // Holds group
                    Section("Holds") {
                        Button {
                            showingHoldSheet = true
                        } label: {
                            Label("Hold cart", systemImage: "pause.circle")
                        }
                        .keyboardShortcut("H", modifiers: .command)
                        .disabled(cart.isEmpty)
                        .accessibilityIdentifier("pos.toolbar.hold")

                        Button {
                            showingResumeHoldsSheet = true
                        } label: {
                            Label("Resume holds", systemImage: "clock.arrow.circlepath")
                        }
                        .keyboardShortcut("H", modifiers: [.command, .shift])
                        .accessibilityIdentifier("pos.toolbar.resumeHolds")
                    }
                    // §16.10 — Register management
                    Section("Register") {
                        Button {
                            showingCloseRegister = true
                        } label: {
                            Label("Close register", systemImage: "lock.circle")
                        }
                        .disabled(registerSession == nil)
                        .accessibilityIdentifier("pos.toolbar.closeRegister")

                        Button {
                            showingZReport = true
                        } label: {
                            Label("View Z-report", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(registerSession == nil && lastClosedSession == nil)
                        .accessibilityIdentifier("pos.toolbar.zReport")

                        // §16.11 — No-sale / open-drawer without a transaction.
                        Button {
                            let limits = PosTenantLimits.current()
                            if limits.noSaleRequiresManager {
                                showingNoSalePin = true
                            } else {
                                openDrawer()
                                Task {
                                    try? await PosAuditLogStore.shared.record(
                                        event: PosAuditEntry.EventType.noSale,
                                        cashierId: 0,
                                        reason: "No-sale drawer open"
                                    )
                                }
                            }
                        } label: {
                            Label("No sale / open drawer", systemImage: "dollarsign.arrow.circlepath")
                        }
                        .disabled(registerSession == nil)
                        .accessibilityIdentifier("pos.toolbar.noSale")

                        Button {
                            showingAuditLog = true
                        } label: {
                            Label("View audit log", systemImage: "list.clipboard")
                        }
                        .accessibilityIdentifier("pos.toolbar.auditLog")
                    }
                    // Existing destructive actions
                    Section {
                        Button { showingReturns = true } label: {
                            Label("Process return", systemImage: "arrow.uturn.backward")
                        }
                        .keyboardShortcut("R", modifiers: [.command, .shift])
                        .accessibilityIdentifier("pos.toolbar.returns")

                        Button(role: .destructive) { cart.clear() } label: {
                            Label("Clear cart", systemImage: "trash")
                        }
                        .keyboardShortcut(.delete, modifiers: [.command, .shift])
                        .disabled(cart.isEmpty)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More options")
                        .accessibilityIdentifier("pos.toolbar.overflow")
                }
            }
        }
    }

    private func pick(_ item: Networking.InventoryListItem) {
        let line = PosCartMapper.cartItem(from: item)
        cart.add(line)
        BrandHaptics.success()
        posVM.recordSale(itemIds: [item.id])

        // §16.4 — Device picker for repair service items when a customer is attached.
        // Only prompt when the item is a service and the customer has a real ID.
        if item.isService, let customerId = cart.customer?.id, customerId > 0, api != nil {
            devicePickerCartLineId = line.id
            showingDevicePicker = true
        }
    }

    private func startCharge() {
        guard !cart.isEmpty else { return }
        BrandHaptics.tapMedium()
        Task {
            // §16.12 — offline path: if offline, enqueue instead of opening the charge sheet.
            let handledOffline = await cartVM.checkoutIfOffline(
                cart: cart,
                cashSession: registerSession
            )
            if handledOffline {
                BrandHaptics.success()
                // Persist the snapshot so the op survives app kill.
                await cartVM.saveSnapshot(cart: cart, cashSessionId: registerSession?.id)
                return
            }
            // Online path — if cart is already fully tendered (gift cards /
            // store credit), skip tender selection and go straight to post-sale.
            // Otherwise open the tender select sheet.
            if cart.isFullyTendered {
                postSale = buildPostSaleViewModel()
            } else {
                showingTenderSelect = true
            }
        }
    }

    /// Assemble the post-sale view model from the current cart. Snapshots
    /// the render output so the sheet is immune to subsequent cart edits
    /// (e.g. the Next-sale clear).
    ///
    /// - Parameters:
    ///   - methodLabel: Override the tender method label (e.g. "Cash" after a
    ///     cash transaction). When nil the label is derived from applied tenders.
    ///   - invoiceId: Server-assigned invoice ID from a completed transaction.
    private func buildPostSaleViewModel(
        methodLabel overrideLabel: String? = nil,
        methodAmountCents: Int? = nil,
        invoiceId: Int64 = -1,
        orderNumber: String? = nil
    ) -> PosPostSaleViewModel {
        let snapshot = PosReceiptPayloadBuilder.build(
            cart: cart,
            methodLabel: overrideLabel,
            methodAmountCents: methodAmountCents,
            orderNumber: orderNumber
        )
        let text = PosReceiptRenderer.text(snapshot)
        let html = PosReceiptRenderer.html(snapshot)
        let methodLabel: String = overrideLabel ?? {
            if cart.isFullyTendered {
                return cart.appliedTenders.first?.label ?? "Store credit"
            }
            return "Card"
        }()
        return PosPostSaleViewModel(
            totalCents: cart.totalCents,
            methodLabel: methodLabel,
            receiptText: text,
            receiptHtml: html,
            receiptPayload: snapshot,
            invoiceId: invoiceId,
            defaultEmail: cart.customer?.email,
            defaultPhone: cart.customer?.phone,
            api: api,
            nextSale: { [weak cart] in cart?.clear() }
        )
    }

    /// Build a `CashTenderViewModel` from the current cart and open the sheet.
    /// Throws if any cart item lacks an inventory_item_id; shows a toast instead.
    private func openCashTender() {
        guard let api else {
            // No API client — fall back to the old direct post-sale path.
            postSale = buildPostSaleViewModel(methodLabel: "Cash")
            return
        }
        do {
            let idempKey = UUID().uuidString
            let request = try PosTransactionMapper.request(
                from: cart,
                paymentMethod: TenderKind.cash.apiValue,
                paymentAmountCents: cart.totalCents,
                idempotencyKey: idempKey
            )
            cashTenderVM = CashTenderViewModel(
                totalCents: cart.totalCents,
                transactionRequest: request,
                api: api
            )
        } catch PosTransactionMapper.MapperError.customLineNotSupported(let msg) {
            tenderErrorMessage = msg
        } catch {
            tenderErrorMessage = error.localizedDescription
        }
    }

    private func openDrawer() {
        Task {
            do {
                try await cashDrawerOpen()
            } catch {
                AppLog.hardware.error("openDrawer failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// §16.10 — load any open register session on POS mount. Nil result
    /// triggers the drawer-lock placeholder. Errors are swallowed: a
    /// store failure shouldn't hide the POS tab, just keeps it locked.
    private func loadRegisterSession() async {
        let current = try? await CashRegisterStore.shared.currentSession()
        registerSession = current
        registerLoaded = true
        if current == nil && lastClosedSession == nil {
            showingOpenRegister = true
        }
    }

    /// Full-screen placeholder rendered when no register session is open.
    /// Prevents accidental sales before the cashier counts their float.
    private var registerLockedPlaceholder: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(spacing: BrandSpacing.xs) {
                    Text("Register closed")
                        .font(.brandTitleLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Open a cash register to start selling. Count the opening float before ringing up any sale.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.xl)
                }
                Button {
                    BrandHaptics.tap()
                    showingOpenRegister = true
                } label: {
                    Label("Open register", systemImage: "lock.open")
                        .font(.brandTitleSmall())
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("pos.registerLocked.open")

                if lastClosedSession != nil {
                    Button {
                        showingZReport = true
                    } label: {
                        Text("View last Z-report")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pos.registerLocked.lastZReport")
                }
            }
            .frame(maxWidth: 420)
        }
        .accessibilityIdentifier("pos.registerLocked")
    }
}

private struct CartPill: View {
    let itemCount: Int
    let totalCents: Int
    let customer: PosCustomer?
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: BrandSpacing.sm) {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "cart.fill")
                        .foregroundStyle(.bizarreOnOrange)
                        .accessibilityHidden(true)
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnOrange)
                        .monospacedDigit()
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(Color.bizarreOrange, in: Capsule())

                if let customer { CartPillCustomerChip(customer: customer) }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("Total")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(Self.format(cents: totalCents))
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to review and charge.")
        .accessibilityIdentifier("pos.cartPill")
    }

    private var accessibilityText: String {
        let items = "\(itemCount) \(itemCount == 1 ? "item" : "items")"
        let total = "Total \(Self.format(cents: totalCents))"
        if let customer { return "\(items), customer \(customer.displayName). \(total)." }
        return "\(items) in cart. \(total)."
    }

    static func format(cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}

private struct CartPillCustomerChip: View {
    let customer: PosCustomer

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                if customer.isWalkIn {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.bizarreOnOrange)
                } else {
                    Text(customer.initials)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnOrange)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            Text(customer.isWalkIn ? "Walk-in" : customer.displayName)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(Color.bizarreSurface2.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityIdentifier("pos.cartPill.customerChip")
    }
}

#Preview("iPhone") { PosView().preferredColorScheme(.dark) }
#Preview("iPad") { PosView().preferredColorScheme(.dark).previewInterfaceOrientation(.landscapeLeft) }

private struct PosDisabledRepository: InventoryRepository {
    func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] { [] }

    func listAdvanced(filter: InventoryFilter, sort: InventorySortOption,
                      advanced: InventoryAdvancedFilter, keyword: String?) async throws -> [InventoryListItem] { [] }
}

// MARK: - Wave-5 null stubs (build-safe fallbacks when DI not fully wired)

/// Null customer repository — returns empty results. Used when no real
/// `CustomerRepository` is injected (preview / unit test contexts).
private struct PosGateNullCustomerRepository: CustomerRepository {
    func list(keyword: String?) async throws -> [CustomerSummary] { [] }
    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw URLError(.unsupportedURL)
    }
    func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage {
        CustomerCursorPage(customers: [], nextCursor: nil)
    }
    func createFromContact(_ req: ContactImportCreateRequest) async throws {}
    func bulkTag(_ req: BulkTagRequest) async throws -> BulkOperationResult {
        BulkOperationResult(processed: 0, failed: 0)
    }
    func bulkDelete(_ req: BulkDeleteRequest) async throws -> BulkOperationResult {
        BulkOperationResult(processed: 0, failed: 0)
    }
}

/// Null tickets repository — returns empty pickup list. Used when no
/// `APIClient` is available in preview / test contexts.
private struct PosGateNullTicketsRepository: GateTicketsRepository {
    func readyForPickup(limit: Int) async throws -> [ReadyPickup] { [] }
}
#endif
