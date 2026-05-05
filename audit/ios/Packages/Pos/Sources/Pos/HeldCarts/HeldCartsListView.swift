#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16.14 — List of held carts shown from the POS toolbar "Held" button.
/// Tapping a row saves the current cart (if non-empty) and loads the held one.
public struct HeldCartsListView: View {
    @Environment(\.dismiss) private var dismiss

    let cart: Cart
    let onResumed: () -> Void

    @State private var heldCarts:  [HeldCart] = []
    @State private var isLoading:  Bool        = true

    public init(cart: Cart, onResumed: @escaping () -> Void) {
        self.cart      = cart
        self.onResumed = onResumed
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Group {
                    if isLoading {
                        ProgressView("Loading holds…")
                    } else if heldCarts.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Held Carts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .accessibilityIdentifier("heldCarts.refresh")
                }
            }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "cart.badge.minus")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No held carts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Use \"Hold Cart\" to save a cart and resume later.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("heldCarts.empty")
    }

    // MARK: - List

    private var list: some View {
        List {
            ForEach(heldCarts) { held in
                HeldCartRow(held: held) {
                    resume(held)
                }
                .listRowBackground(Color.bizarreSurface1)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task {
                            await HeldCartStore.shared.delete(id: held.id)
                            await reload()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func reload() async {
        isLoading  = true
        heldCarts  = await HeldCartStore.shared.loadAll()
        isLoading  = false
    }

    private func resume(_ held: HeldCart) {
        held.cart.restore(into: cart)
        BrandHaptics.success()
        onResumed()
        dismiss()
    }
}

// MARK: - HeldCartRow

private struct HeldCartRow: View {
    let held:  HeldCart
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.md) {
                // Customer chip
                if held.customerId != nil {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(held.displayTitle)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: BrandSpacing.sm) {
                        Text("\(held.itemCount) \(held.itemCount == 1 ? "item" : "items")")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(timeAgo(from: held.savedAt))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                    Text(CartMath.formatCents(held.totalCents))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                    // Expiry chip
                    if held.isExpired {
                        Text("Expired")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(held.displayTitle), \(held.itemCount) items, \(CartMath.formatCents(held.totalCents))")
        .accessibilityHint("Double tap to load into cart")
        .accessibilityIdentifier("heldCarts.row.\(held.id)")
    }

    private func timeAgo(from date: Date) -> String {
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60 { return "just now" }
        if secs < 3_600 { return "\(secs / 60)m ago" }
        return "\(secs / 3_600)h ago"
    }
}
#endif
