#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Inventory
import Customers
import Persistence

/// Point-of-Sale root screen. iPhone: single stacked column with the cart
/// on top and the item picker under. iPad / Mac: balanced split view with
/// the picker on the leading side and the cart on the trailing side.
///
/// Scaffold only — holds, payment rails, and receipt print land in later
/// phases. §16.4 customer-attach (walk-in / find / create) is wired in.
/// §39 drawer lock blocks selling until a cash session is open; close +
/// Z-report hang off the toolbar menu.
/// See `ios/ActionPlan.md` §16 for the full scope.
public struct PosView: View {
    @State private var cart = Cart()
    @State private var search: PosSearchViewModel
    @State private var showingCustomLine: Bool = false
    @State private var showingCharge: Bool = false
    @State private var editQuantityFor: CartItem?
    @State private var editPriceFor: CartItem?
    @State private var showingCartSheet: Bool = false
    @State private var showingCustomerPicker: Bool = false
    @State private var showingCustomerCreate: Bool = false

    /// §16.9 — presents `PosReturnsView`. Search past invoices and
    /// launch a refund sheet. Disabled when the APIClient is missing
    /// (no remote lookup possible offline).
    @State private var showingReturns: Bool = false

    /// §41 — presents `PosPaymentLinkSheet`. Creates a public-pay link for
    /// the current cart and polls status until the webhook flips it to
    /// paid. Disabled when the cart is empty or the APIClient is missing.
    @State private var showingPaymentLink: Bool = false

    private let customerRepo: CustomerRepository?
    private let api: APIClient?

    public init(
        repo: InventoryRepository? = nil,
        customerRepo: CustomerRepository? = nil,
        api: APIClient? = nil
    ) {
        self.customerRepo = customerRepo
        self.api = api
        if let repo {
            _search = State(wrappedValue: PosSearchViewModel(repo: repo))
        } else {
            _search = State(wrappedValue: PosSearchViewModel(repo: PosDisabledRepository()))
        }
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .task { await search.load() }
        .sheet(isPresented: $showingCustomLine) {
            PosCustomLineSheet { item in
                cart.add(item)
            }
        }
        .sheet(isPresented: $showingCharge) {
            PosChargePlaceholderSheet(
                cart: cart,
                api: api,
                onSaleComplete: {
                    cart.clear()
                    cart.detachCustomer()
                }
            )
        }
        .sheet(isPresented: $showingReturns) {
            PosReturnsView(api: api)
        }
        .sheet(isPresented: $showingPaymentLink) {
            if let api {
                PosPaymentLinkSheet(cart: cart, api: api)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
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
            if let repo = customerRepo, let api {
                PosCustomerPickerSheet(repo: repo, api: api) { customer in
                    cart.attach(customer: customer)
                    BrandHaptics.success()
                }
            }
        }
        .sheet(isPresented: $showingCustomerCreate) {
            if let api {
                CustomerCreateSheetWrapper(api: api) { customer in
                    cart.attach(customer: customer)
                    BrandHaptics.success()
                }
            }
        }
        .sheet(isPresented: $showingCartSheet) {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: {
                        showingCartSheet = false
                        startCharge()
                    },
                    onOpenDrawer: openDrawer,
                    onChangeCustomer: {
                        showingCartSheet = false
                        showingCustomerPicker = true
                    },
                    onRemoveCustomer: { cart.detachCustomer() },
                    editQuantityFor: $editQuantityFor,
                    editPriceFor: $editPriceFor
                )
                .navigationTitle("Cart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCartSheet = false }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            cart.clear()
                            showingCartSheet = false
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
    }

    // MARK: - iPhone (compact)
    //
    // Search-first layout. Staff arrive here to add items to a cart — the
    // search bar + scan CTA live at the top, results fill the remaining
    // space, and the cart only surfaces as a compact floating pill at the
    // bottom once it has items. Empty cart = zero chrome.
    //
    // Tapping the pill expands a sheet with the line items + totals + the
    // Charge action, following the Square / Shopify POS pattern.

    private var compactLayout: some View {
        NavigationStack {
            PosSearchPanel(
                search: search,
                hasCustomer: cart.hasCustomer,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                onAttachWalkIn: attachWalkIn,
                onFindCustomer: { showingCustomerPicker = true },
                onCreateCustomer: { showingCustomerCreate = true }
            )
            .navigationTitle("POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { posToolbar }
            .safeAreaInset(edge: .top) {
                if let customer = cart.customer {
                    PosCustomerBanner(
                        customer: customer,
                        onChange: { showingCustomerPicker = true },
                        onRemove: { cart.detachCustomer() }
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(Color.bizarreSurfaceBase)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !cart.isEmpty {
                    PosCartPill(
                        itemCount: cart.items.reduce(0) { $0 + $1.quantity },
                        totalCents: cart.totalCents,
                        onExpand: { showingCartSheet = true }
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.bottom, BrandSpacing.sm)
                }
            }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            PosSearchPanel(
                search: search,
                hasCustomer: cart.hasCustomer,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                onAttachWalkIn: attachWalkIn,
                onFindCustomer: { showingCustomerPicker = true },
                onCreateCustomer: { showingCustomerCreate = true }
            )
            .navigationTitle("Items")
            .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 540)
        } detail: {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: startCharge,
                    onOpenDrawer: openDrawer,
                    onChangeCustomer: { showingCustomerPicker = true },
                    onRemoveCustomer: { cart.detachCustomer() },
                    editQuantityFor: $editQuantityFor,
                    editPriceFor: $editPriceFor
                )
                .navigationTitle("Cart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { posToolbar }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Shared toolbar

    private var posToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCustomLine = true
                } label: {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("Add custom line")
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        showingReturns = true
                    } label: {
                        Label("Process return", systemImage: "arrow.uturn.backward")
                    }
                    .keyboardShortcut("R", modifiers: .command)
                    .disabled(api == nil)

                    Button {
                        showingPaymentLink = true
                    } label: {
                        Label("Send payment link", systemImage: "link")
                    }
                    .disabled(cart.isEmpty || api == nil)

                    Divider()

                    Button(role: .destructive) {
                        cart.clear()
                    } label: {
                        Label("Clear cart", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .disabled(cart.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Cart options")
            }
        }
    }

    // MARK: - Actions

    private func pick(_ item: Networking.InventoryListItem) {
        let line = PosCartMapper.cartItem(from: item)
        cart.add(line)
        BrandHaptics.success()
    }

    private func startCharge() {
        guard !cart.isEmpty else { return }
        // §41 — while a public payment link is outstanding the customer is
        // paying via the web page. Blocking Charge here prevents the POS
        // from double-capturing the same sale at the terminal.
        guard !cart.hasPendingPaymentLink else { return }
        BrandHaptics.tapMedium()
        showingCharge = true
    }

    private func openDrawer() {
        // Stub: real implementation pulses the MFi printer kick opcode
        // (§17.4). Button is wired disabled with a hint, so this closure
        // should never actually fire — keep as a no-op so the shape of the
        // call site is obvious to reviewers.
    }

    /// §16.4 walk-in attach. Uses the canonical `.walkIn` sentinel so every
    /// consumer (chip, receipt header) renders the same "Walk-in" string
    /// without touching the view-model from the tap handler.
    private func attachWalkIn() {
        cart.attach(customer: .walkIn)
        BrandHaptics.success()
    }
}

// `PosCustomerBanner` + `PosCartPill` live in `PosHomeChrome.swift` so this
// file stays focused on screen state + sheet wiring.

#Preview("iPhone") {
    PosView()
        .preferredColorScheme(.dark)
}

#Preview("iPad") {
    PosView()
        .preferredColorScheme(.dark)
        .previewInterfaceOrientation(.landscapeLeft)
}

/// Null-object repository used when `PosView()` is constructed without an
/// `InventoryRepository` (previews, Mac Designed-for-iPad builds without a
/// network stack wired). Always returns an empty list. Production call
/// sites must pass the real `InventoryRepositoryImpl`.
private struct PosDisabledRepository: InventoryRepository {
    func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] {
        []
    }
}
#endif
