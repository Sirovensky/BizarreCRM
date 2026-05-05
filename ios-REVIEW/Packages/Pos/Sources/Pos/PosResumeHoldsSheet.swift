#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.3 — "Resume holds" sheet. Fetches open holds from
/// `GET /api/v1/pos/held-carts` and displays a list. Tapping a row:
///   1. Calls `POST /pos/held-carts/:id/recall` to mark the cart recalled.
///   2. Deserialises the returned `cart_json` back into the active cart.
///   3. NEVER inherits a pending payment link.
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

        case .loaded(let rows):
            if rows.isEmpty {
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
                List(rows) { row in
                    PosHoldRow(row: row) {
                        BrandHaptics.success()
                        Task { @MainActor in
                            await vm.recall(row: row, into: cart)
                            onResumed()
                        }
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
    let row: PosHeldCartRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(row.displayLabel)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: BrandSpacing.sm) {
                        if let owner = row.ownerName {
                            Text(owner)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Text("·")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Text(row.createdAt.prefix(10))
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                if let total = row.totalCents {
                    Text(CartMath.formatCents(total))
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Resume hold: \(row.displayLabel)")
        .accessibilityHint("Double tap to load into cart")
        .accessibilityIdentifier("pos.holdRow.\(row.id)")
    }
}

// MARK: - View model

@MainActor
@Observable
final class PosResumeHoldsViewModel {
    enum LoadState {
        case idle
        case loading
        case loaded([PosHeldCartRow])
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
            let rows = try await api.listHeldCarts()
            loadState = .loaded(rows)
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            loadState = .unavailable("Coming soon — server endpoint pending.")
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Recall a hold from the server, then restore the full cart from its
    /// `cart_json`. Clears the active cart first — NEVER inherit a pending
    /// payment link.
    func recall(row: PosHeldCartRow, into cart: Cart) async {
        guard let api else { return }
        do {
            // Mark as recalled on the server so it disappears from the list.
            let recalled = try await api.recallHeldCart(id: row.id)
            restoreFromJson(recalled.cartJson, into: cart)
        } catch {
            // On any network error, fall back to the locally-visible cart_json.
            restoreFromJson(row.cartJson, into: cart)
        }
    }

    /// Restore the cart entirely from the JSON stored in the held-cart row.
    /// Falls back to a single synthetic line if the JSON cannot be decoded.
    private func restoreFromJson(_ cartJson: String, into cart: Cart) {
        cart.clear()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let data = cartJson.data(using: .utf8),
            let snapshot = try? decoder.decode(CartSnapshot.self, from: data)
        else {
            // Fallback: add one synthetic line so the cart isn't empty.
            cart.add(CartItem(name: "Resumed hold", unitPrice: 0))
            return
        }
        snapshot.restore(into: cart)
    }
}
#endif
