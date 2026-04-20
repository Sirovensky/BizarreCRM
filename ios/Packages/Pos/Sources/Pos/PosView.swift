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
    }

    // MARK: - iPhone (compact)

    private var compactLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PosCartPanel(
                    cart: cart,
                    onCharge: startCharge,
                    onOpenDrawer: openDrawer,
                    editQuantityFor: $editQuantityFor,
                    editPriceFor: $editPriceFor
                )
                .frame(maxHeight: .infinity)
                Divider().background(.bizarreOutline)
                PosSearchPanel(
                    search: search,
                    onPick: pick,
                    onAddCustom: { showingCustomLine = true }
                )
                .frame(maxHeight: 320)
            }
            .navigationTitle("Point of Sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { posToolbar }
        }
    }

    // MARK: - iPad (regular)

    private var regularLayout: some View {
        NavigationSplitView {
            PosSearchPanel(
                search: search,
                onPick: pick,
                onAddCustom: { showingCustomLine = true }
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
