import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - EstimateDetailView

/// Detail view for a single estimate.
/// Phase-4 addition: "Convert to Ticket" toolbar action via `EstimateConvertSheet`.
/// Remaining detail sections (§8.2) remain `[ ]` and will ship in a follow-up.
public struct EstimateDetailView: View {
    private let estimate: Estimate
    private let api: APIClient
    private let onTicketCreated: @MainActor (Int64) -> Void

    @State private var showConvertSheet: Bool = false

    public init(
        estimate: Estimate,
        api: APIClient,
        onTicketCreated: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        self.estimate = estimate
        self.api = api
        self.onTicketCreated = onTicketCreated
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    headerCard
                    placeholderSections
                }
                .padding(BrandSpacing.lg)
            }
        }
        .navigationTitle(estimate.orderId ?? "Estimate")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showConvertSheet = true
                    } label: {
                        Label("Convert to Ticket", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityLabel("Convert estimate to a service ticket")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Estimate actions")
                #if os(macOS)
                .keyboardShortcut("k", modifiers: [.command, .shift])
                #endif
            }
        }
        .sheet(isPresented: $showConvertSheet) {
            EstimateConvertSheet(
                estimate: estimate,
                api: api,
                onSuccess: { ticketId in
                    showConvertSheet = false
                    onTicketCreated(ticketId)
                }
            )
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text(estimate.orderId ?? "EST-?")
                    .font(.brandMono(size: 18))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                if let status = estimate.status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, BrandSpacing.sm)
                        .padding(.vertical, BrandSpacing.xxs)
                        .foregroundStyle(.bizarreOnSurface)
                        .background(Color.bizarreSurface2, in: Capsule())
                        .accessibilityLabel("Status: \(status.capitalized)")
                }
            }
            Text(estimate.customerName)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
            if let total = estimate.total {
                Text(formatMoney(total))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                    .accessibilityLabel("Total: \(formatMoney(total))")
            }
            if let until = estimate.validUntil, !until.isEmpty {
                Text("Valid until \(String(until.prefix(10)))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Placeholder for §8.2 detail sections

    private var placeholderSections: some View {
        VStack(spacing: BrandSpacing.md) {
            Text("Line items, approval, versioning — §8.2")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(BrandSpacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}
