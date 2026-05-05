#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Related sidebar (iPad only).
//
// Shown on iPad in landscape as a 280pt trailing column beside the main
// ticket detail scroll view. Contains:
//   - Recent tickets from the same customer (GET /customers/:id/tickets)
//   - Photo wallet (last 6 photos from detail.photos)
//   - Health score + LTV tier chips (from customer analytics)
//
// Gate: only rendered when !Platform.isCompact. iPhone sees nothing.

// MARK: - ViewModel

@MainActor
@Observable
final class TicketRelatedSidebarViewModel {
    private(set) var recentTickets: [TicketSummary] = []
    private(set) var isLoadingTickets: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    let customerId: Int64
    let currentTicketId: Int64

    init(api: APIClient, customerId: Int64, currentTicketId: Int64) {
        self.api = api
        self.customerId = customerId
        self.currentTicketId = currentTicketId
    }

    func load() async {
        isLoadingTickets = true
        defer { isLoadingTickets = false }
        do {
            // GET /api/v1/customers/:id/tickets — returns [TicketSummary]
            let all = try await api.get(
                "/api/v1/customers/\(customerId)/tickets",
                query: nil,
                as: [TicketSummary].self
            )
            // Exclude current ticket to avoid self-reference
            recentTickets = Array(all.filter { $0.id != currentTicketId }.prefix(5))
        } catch {
            AppLog.ui.warning("Related sidebar load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

/// §4.2 — iPad-only sidebar shown in the main TicketDetailView.
/// Displayed as a 280pt trailing panel via `NavigationSplitView` or `HStack`.
public struct TicketRelatedSidebar: View {
    @State private var vm: TicketRelatedSidebarViewModel
    let photos: [TicketDetail.TicketPhoto]
    let onSelectTicket: (_ ticketId: Int64) -> Void

    public init(
        api: APIClient,
        customerId: Int64,
        currentTicketId: Int64,
        photos: [TicketDetail.TicketPhoto],
        onSelectTicket: @escaping (_ ticketId: Int64) -> Void
    ) {
        _vm = State(wrappedValue: TicketRelatedSidebarViewModel(
            api: api,
            customerId: customerId,
            currentTicketId: currentTicketId
        ))
        self.photos = photos
        self.onSelectTicket = onSelectTicket
    }

    public var body: some View {
        // Only show on iPad / regular width
        if !Platform.isCompact {
            sidebarContent
                .task { await vm.load() }
        }
    }

    // MARK: - Sidebar content

    private var sidebarContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Photo wallet section (max 6 photos)
                if !photos.isEmpty {
                    photoWallet
                }

                // Recent tickets from same customer
                recentTicketsSection
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurface1)
    }

    // MARK: - Photo wallet

    private var photoWallet: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Photos")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 100))], spacing: BrandSpacing.xs) {
                ForEach(photos.prefix(6)) { photo in
                    if let urlStr = photo.url, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.bizarreSurface1)
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    )
                            }
                        }
                        .hoverEffect(.highlight)
                        .accessibilityLabel("Ticket photo")
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurfaceBase, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Recent tickets

    private var recentTicketsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recent tickets")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            if vm.isLoadingTickets {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(BrandSpacing.md)
                    .accessibilityLabel("Loading recent tickets")
            } else if vm.recentTickets.isEmpty {
                Text("No other tickets")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BrandSpacing.sm)
            } else {
                ForEach(vm.recentTickets) { ticket in
                    Button { onSelectTicket(ticket.id) } label: {
                        RelatedTicketRow(ticket: ticket)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurfaceBase, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Related ticket row

private struct RelatedTicketRow: View {
    let ticket: TicketSummary

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            HStack {
                Text(ticket.orderId)
                    .font(.brandMono(size: 13))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                Spacer()
                if let status = ticket.status {
                    Text(status.name)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.2), in: Capsule())
                }
            }
            if let firstDevice = ticket.firstDevice {
                Text(firstDevice.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Text(formatMoney(Double(ticket.total) / 100.0))
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ticket.orderId), \(ticket.status?.name ?? "Unknown status"), \(formatMoney(Double(ticket.total) / 100.0))")
    }

    private func statusColor(_ status: TicketSummary.Status) -> Color {
        switch status.group {
        case .inProgress: return .bizarreOrange
        case .waiting:    return .yellow
        case .complete:   return .bizarreSuccess
        case .cancelled:  return .bizarreOnSurfaceMuted
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

private extension TicketSummary.FirstDevice {
    var displayName: String {
        let parts = [deviceName, serviceName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.joined(separator: " — ")
    }
}
#endif
