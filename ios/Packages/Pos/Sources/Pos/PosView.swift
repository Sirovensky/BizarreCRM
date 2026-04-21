#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Inventory

/// Point-of-Sale root screen. iPhone: single stacked column with the cart
/// on top and the item picker under. iPad / Mac: balanced split view with
/// the picker on the leading side and the cart on the trailing side.
///
/// Scaffold only — customer attach, holds, payment rails, and receipt
/// print land in later phases. See `ios/ActionPlan.md` §16 for the full
/// scope.
public struct PosView: View {
    @State private var cart = Cart()
    @State private var search: PosSearchViewModel
    @State private var showingCustomLine: Bool = false
    @State private var showingCharge: Bool = false
    @State private var editQuantityFor: CartItem?
    @State private var editPriceFor: CartItem?
    @State private var showingCartSheet: Bool = false

    public init(repo: InventoryRepository? = nil) {
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
        // Stub: real implementation pulses the MFi printer kick opcode
        // (§17.4). Button is wired disabled with a hint, so this closure
        // should never actually fire — keep as a no-op so the shape of the
        // call site is obvious to reviewers.
    }
}

/// Compact cart pill anchored to the bottom-safe-area on iPhone. Only
/// surfaces when the cart has items. Shows the rolled-up item count +
/// total on the leading side and a chevron → on the trailing to signal
/// tap-to-expand. Uses brand glass so it reads as chrome floating over
/// the scrolling search results.
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
