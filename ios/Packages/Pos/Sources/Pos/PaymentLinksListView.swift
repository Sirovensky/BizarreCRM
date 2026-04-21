#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

/// §41 — standalone list of recent payment links, mounted from
/// MoreMenuView → Operations. Shows status chip + amount + short token +
/// Copy URL affordance. Non-destructive: cancel is a swipe-action on
/// active rows; paid / expired rows are read-only.
public struct PaymentLinksListView: View {
    @State private var vm: PaymentLinksListViewModel
    @State private var copiedRow: Int64?

    public init(api: APIClient) {
        _vm = State(wrappedValue: PaymentLinksListViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading && vm.links.isEmpty {
                ProgressView()
            } else if vm.links.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Payment links")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .overlay(alignment: .bottom) {
            if copiedRow != nil {
                Text("Copied to clipboard")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, BrandSpacing.xl)
                    .transition(.opacity)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(vm.links) { link in
                PaymentLinkRow(
                    link: link,
                    onCopy: { copy(link: link) }
                )
                .listRowBackground(Color.bizarreSurface1)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if link.isActive {
                        Button(role: .destructive) {
                            Task { await vm.cancel(id: link.id) }
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "link")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No payment links yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Generate a link from the POS cart to send a customer a pay page.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(link: PaymentLink) {
        UIPasteboard.general.string = link.url
        BrandHaptics.tap()
        copiedRow = link.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedRow = nil
        }
    }
}

/// Observable backing store for `PaymentLinksListView`. Keeps the list +
/// loading / error state and exposes the mutation methods (cancel).
@MainActor
@Observable
public final class PaymentLinksListViewModel {
    public private(set) var links: [PaymentLink] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            links = try await api.listPaymentLinks()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not load payment links."
        }
        isLoading = false
    }

    public func cancel(id: Int64) async {
        do {
            try await api.cancelPaymentLink(id: id)
            await load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not cancel payment link."
        }
    }
}

/// Row view — status chip + amount + short token + trailing Copy button.
struct PaymentLinkRow: View {
    let link: PaymentLink
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            PaymentLinkStatusChip(status: link.statusKind)
            VStack(alignment: .leading, spacing: 2) {
                Text(CartMath.formatCents(link.amountCents))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let token = link.shortId, !token.isEmpty {
                    Text(token.prefix(12) + "…")
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.bizarreOrange)
            }
            .buttonStyle(.plain)
            .disabled(link.url.isEmpty)
            .accessibilityLabel("Copy payment URL")
            .accessibilityIdentifier("paymentLinks.row.copy")
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

/// Small colored chip for the status column.
struct PaymentLinkStatusChip: View {
    let status: PaymentLink.Status

    var body: some View {
        Text(label)
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    private var label: String {
        switch status {
        case .active:    return "ACTIVE"
        case .paid:      return "PAID"
        case .expired:   return "EXPIRED"
        case .cancelled: return "CANCELLED"
        case .unknown:   return "—"
        }
    }

    private var color: Color {
        switch status {
        case .active:    return .bizarreOrange
        case .paid:      return .green
        case .expired:   return .gray
        case .cancelled: return .secondary
        case .unknown:   return .gray
        }
    }
}
#endif
