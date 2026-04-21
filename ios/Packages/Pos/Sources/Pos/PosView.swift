#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Hardware
import Networking
import Inventory
import Customers

/// POS root screen. §16.4 wires the customer attach flow.
public struct PosView: View {
    @State private var cart = Cart()
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

    /// §16.7 / §16.9 — the POS toolbar "Process return" entry and the
    /// post-sale receipt-send flow both need the live `APIClient`. Kept
    /// optional so preview / Mac-designed-for-iPad builds without auth
    /// still compile; both surfaces fall back to a typed "Coming soon"
    /// message when `api` is nil.
    private let api: APIClient?
    private let customerRepo: CustomerRepository?

    public init(
        repo: InventoryRepository? = nil,
        api: APIClient? = nil,
        customerRepo: CustomerRepository? = nil
    ) {
        if let repo {
            _search = State(wrappedValue: PosSearchViewModel(repo: repo))
        } else {
            _search = State(wrappedValue: PosSearchViewModel(repo: PosDisabledRepository()))
        }
        self.api = api
        self.customerRepo = customerRepo
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await search.load() }
        .sheet(isPresented: $showingCustomLine) {
            PosCustomLineSheet { item in cart.add(item) }
        }
        .sheet(item: $postSale) { vm in
            PosPostSaleView(vm: vm)
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
                }
            }
        }
        .sheet(isPresented: $showingCartSheet) {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: { showingCartSheet = false; startCharge() },
                    onOpenDrawer: openDrawer,
                    onChangeCustomer: customerRepo == nil ? nil : {
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
    }

    private var compactLayout: some View {
        NavigationStack {
            PosSearchPanel(
                search: search,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                showsCustomerCTAs: !cart.hasCustomer,
                onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                onCreateCustomer: api == nil ? nil : { showingCreateCustomer = true },
                onFindCustomer: customerRepo == nil ? nil : { showingCustomerPicker = true }
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

    private var regularLayout: some View {
        NavigationSplitView {
            PosSearchPanel(
                search: search,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                showsCustomerCTAs: !cart.hasCustomer,
                onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                onCreateCustomer: api == nil ? nil : { showingCreateCustomer = true },
                onFindCustomer: customerRepo == nil ? nil : { showingCustomerPicker = true }
            )
            .navigationTitle("Items")
            .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 540)
        } detail: {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: startCharge,
                    onOpenDrawer: openDrawer,
                    onChangeCustomer: customerRepo == nil ? nil : { showingCustomerPicker = true },
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

    private var posToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCustomLine = true } label: { Image(systemName: "plus") }
                    .keyboardShortcut("N", modifiers: .command)
                    .accessibilityLabel("Add custom line")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { showingReturns = true } label: {
                    Label("Process return", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
                .accessibilityLabel("Process return")
                .accessibilityIdentifier("pos.toolbar.returns")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) { cart.clear() } label: {
                    Label("Clear cart", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .accessibilityLabel("Clear cart")
                .disabled(cart.isEmpty)
            }
        }
    }

    private func pick(_ item: Networking.InventoryListItem) {
        let line = PosCartMapper.cartItem(from: item)
        cart.add(line)
        BrandHaptics.success()
    }

    private func startCharge() {
        guard !cart.isEmpty else { return }
        BrandHaptics.tapMedium()
        postSale = buildPostSaleViewModel()
    }

    /// Assemble the post-sale view model from the current cart. Snapshots
    /// the render output so the sheet is immune to subsequent cart edits
    /// (e.g. the Next-sale clear).
    private func buildPostSaleViewModel() -> PosPostSaleViewModel {
        let snapshot = PosReceiptPayloadBuilder.build(cart: cart)
        let text = PosReceiptRenderer.text(snapshot)
        let html = PosReceiptRenderer.html(snapshot)
        return PosPostSaleViewModel(
            totalCents: cart.totalCents,
            methodLabel: "Placeholder — pending §17.3",
            receiptText: text,
            receiptHtml: html,
            defaultEmail: cart.customer?.email,
            defaultPhone: cart.customer?.phone,
            api: api,
            nextSale: { [weak cart] in cart?.clear() }
        )
    }

    private func openDrawer() { /* §17.4 stub */ }
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
}
#endif
