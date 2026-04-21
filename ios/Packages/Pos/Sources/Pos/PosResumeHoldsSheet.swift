#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.3 — "Resume holds" sheet. Fetches open holds from `GET /pos/holds`
/// and displays a list. Tapping a row inserts it back into a fresh cart:
///   1. `cart.clear()` — start clean.
///   2. Re-add items from the hold (item names/quantities; price from the
///      hold payload).
///   3. NEVER inherit a pending payment link.
/// `onResumed` closure fires so the caller can dismiss the sheet.
///
/// 404/501 fallback: "Coming soon" banner, same pattern as §16.9 refunds.
struct PosResumeHoldsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cart: Cart
    let api: APIClient?
    /// Fires after successfully inserting a hold back into the cart.
    let onResumed: () -> Void

    @State private var vm: PosResumeHoldsViewModel

    init(cart: Cart, api: APIClient?, onResumed: @escaping () -> Void) {
        self.cart = cart
        self.api = api
        self.onResumed = onResumed
        _vm = State(wrappedValue: PosResumeHoldsViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Resume a Hold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh holds")
                    .accessibilityIdentifier("pos.resumeHolds.refresh")
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .idle, .loading:
            VStack(spacing: BrandSpacing.md) {
                ProgressView()
                Text("Loading holds…")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable(let message):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreWarning)
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("pos.resumeHolds.unavailable")

        case .failed(let message):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreError)
                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("pos.resumeHolds.error")

        case .loaded(let holds):
            if holds.isEmpty {
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "cart.badge.minus")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("No holds saved yet.")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Use \"Hold cart\" to save a cart and resume it later.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("pos.resumeHolds.empty")
            } else {
                List(holds) { hold in
                    PosHoldRow(hold: hold) {
                        BrandHaptics.success()
                        vm.resume(hold: hold, into: cart)
                        onResumed()
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Hold row

private struct PosHoldRow: View {
    let hold: PosHold
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(hold.note ?? "Hold #\(hold.id)")
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: BrandSpacing.sm) {
                        Text("\(hold.itemsCount) \(hold.itemsCount == 1 ? "item" : "items")")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("·")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text(hold.createdAt.prefix(10))
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                Text(CartMath.formatCents(hold.totalCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Resume hold: \(hold.note ?? "Hold \(hold.id)"), \(hold.itemsCount) items, \(CartMath.formatCents(hold.totalCents))")
        .accessibilityHint("Double tap to load into cart")
        .accessibilityIdentifier("pos.holdRow.\(hold.id)")
    }
}

// MARK: - View model

@MainActor
@Observable
final class PosResumeHoldsViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded([PosHold])
        case failed(String)
        case unavailable(String)
    }

    private(set) var loadState: LoadState = .idle

    @ObservationIgnored private let api: APIClient?

    init(api: APIClient?) {
        self.api = api
    }

    func load() async {
        guard let api else {
            loadState = .unavailable("Coming soon — server endpoint pending.")
            return
        }
        loadState = .loading
        do {
            let holds = try await api.listHolds()
            loadState = .loaded(holds)
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            loadState = .unavailable("Coming soon — server endpoint pending.")
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Insert the hold's items into a fresh cart. Clears first per spec —
    /// NEVER inherit a pending payment link.
    func resume(hold: PosHold, into cart: Cart) {
        // We only have summary data in `PosHold`; a full resume would require
        // a GET /pos/holds/:id endpoint with line detail. For now we restore
        // what the summary gives us (items count / total) and create a single
        // placeholder line. When the server ships GET by id, replace with
        // line-by-line restoration.
        cart.clear()
        // Insert a synthetic custom line carrying the hold total.
        // This is the "safe floor" — better than an empty cart. A richer
        // implementation reads per-line detail from the hold response.
        let unitPrice = Decimal(hold.totalCents) / 100
        let resumedLine = CartItem(
            name: hold.note ?? "Resumed hold #\(hold.id)",
            unitPrice: unitPrice
        )
        cart.add(resumedLine)
    }
}
#endif
