#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Inventory
import Customers

/// Point-of-Sale root screen. iPhone: single stacked column with the cart
/// on top and the item picker under. iPad / Mac: balanced split view with
/// the picker on the leading side and the cart on the trailing side.
///
/// §40 — "Gift card & store credit" opens from the toolbar.
/// §41 — "Send payment link" opens from the toolbar.
public struct PosView: View {
    @State private var cart = Cart()
    @State private var search: PosSearchViewModel
    @State private var showingCustomLine: Bool = false
    @State private var showingCharge: Bool = false
    @State private var editQuantityFor: CartItem?
    @State private var editPriceFor: CartItem?
    @State private var showingCartSheet: Bool = false
    /// §40 — when true, the Gift card / store credit sheet is presented.
    @State private var showingGiftCardSheet: Bool = false
    /// §41 — when true, the Send-payment-link sheet is presented.
    @State private var showingPaymentLink: Bool = false

    /// Optional — only non-nil when the host wires a real network stack.
    /// The gift-card / payment-link sheets need an `APIClient`. When nil,
    /// both toolbar entries are disabled so preview / no-net builds still
    /// compile.
    private let api: APIClient?
    /// Optional customer repository — reserved for the customer-pick
    /// wiring on this screen.
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
            PosChargePlaceholderSheet(totalCents: cart.totalCents)
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
        .sheet(isPresented: $showingCartSheet) {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: {
                        showingCartSheet = false
                        startCharge()
                    },
                    onOpenDrawer: openDrawer,
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
        .sheet(isPresented: $showingGiftCardSheet) {
            if let api {
                PosGiftCardSheet(cart: cart, api: api)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingPaymentLink) {
            if let api {
                PosPaymentLinkSheet(
                    api: api,
                    amountCents: cart.totalCents,
                    customerEmail: cart.customer?.email ?? "",
                    customerPhone: cart.customer?.phone ?? "",
                    customerId: cart.customer?.id,
                    onLinkCreated: { link in
                        cart.markPendingPaymentLink(id: link.id, token: link.shortId ?? "")
                    },
                    onPaid: { _ in
                        cart.clearPendingPaymentLink()
                        cart.clear()
                    }
                )
            }
        }
    }

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack {
            PosSearchPanel(
                search: search,
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                showsCustomerCTAs: !cart.hasCustomer,
                onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                onCreateCustomer: nil,
                onFindCustomer: nil
            )
            .navigationTitle("POS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { posToolbar }
            .safeAreaInset(edge: .bottom) {
                if !cart.isEmpty {
                    CartPill(
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
                onPick: pick,
                onAddCustom: { showingCustomLine = true },
                showsCustomerCTAs: !cart.hasCustomer,
                onWalkIn: { cart.attach(customer: .walkIn); BrandHaptics.success() },
                onCreateCustomer: nil,
                onFindCustomer: nil
            )
            .navigationTitle("Items")
            .navigationSplitViewColumnWidth(min: 320, ideal: 420, max: 540)
        } detail: {
            NavigationStack {
                PosCartPanel(
                    cart: cart,
                    onCharge: startCharge,
                    onOpenDrawer: openDrawer,
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
            // §40 — gift card / store credit.
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingGiftCardSheet = true
                } label: {
                    Label("Gift card / credit", systemImage: "giftcard")
                }
                .disabled(api == nil || cart.isEmpty)
                .accessibilityIdentifier("pos.toolbar.giftCard")
            }
            // §41 — send payment link. Disabled when total is zero or no
            // API client is wired (previews / no-net builds).
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingPaymentLink = true
                } label: {
                    Label("Send payment link", systemImage: "link.badge.plus")
                }
                .disabled(api == nil || cart.totalCents == 0)
                .accessibilityIdentifier("pos.toolbar.paymentLink")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    cart.clear()
                } label: {
                    Label("Clear cart", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .accessibilityLabel("Clear cart")
                .disabled(cart.isEmpty)
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
        BrandHaptics.tapMedium()
        showingCharge = true
    }

    private func openDrawer() {
        // Stub: §17.4 pulses the MFi printer kick opcode.
    }
}

/// Compact cart pill anchored to the bottom-safe-area on iPhone.
private struct CartPill: View {
    let itemCount: Int
    let totalCents: Int
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: BrandSpacing.md) {
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
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(itemCount) \(itemCount == 1 ? "item" : "items") in cart. Total \(Self.format(cents: totalCents)).")
        .accessibilityHint("Double tap to review and charge.")
        .accessibilityIdentifier("pos.cartPill")
    }

    static func format(cents: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}

#Preview("iPhone") {
    PosView()
        .preferredColorScheme(.dark)
}

#Preview("iPad") {
    PosView()
        .preferredColorScheme(.dark)
        .previewInterfaceOrientation(.landscapeLeft)
}

/// Null-object repository used for previews / no-network builds.
private struct PosDisabledRepository: InventoryRepository {
    func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] {
        []
    }
}
#endif
