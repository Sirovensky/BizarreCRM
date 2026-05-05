import SwiftUI
import Observation
import Networking
import DesignSystem

// MARK: - RecentTicketsViewModel
//
// Loads the 3 most-recent tickets for a given customer from
// `GET /api/v1/tickets?customer_id=<id>&pagesize=3&sort_by=created_at&sort_order=DESC`.
//
// Route ground-truth: packages/server/src/routes/tickets.routes.ts
// BLOCKER: The `GET /api/v1/tickets` list route does NOT support a `customer_id`
// query parameter (confirmed by reading tickets.routes.ts — no `req.query.customer_id`
// handling exists). Workaround: pass `keyword` = customer full name so the route's
// keyword JOIN searches customer first_name/last_name, then filter client-side by
// `customerId`. This is best-effort; if two customers share a name, extra tickets
// may appear in the keyword result but are filtered out by the client-side guard.
// When the server gains `customer_id` filter support, replace the keyword approach
// with a direct `customer_id` query item.

@MainActor
@Observable
public final class RecentTicketsViewModel {

    // MARK: State

    public private(set) var tickets: [TicketSummary] = []
    public private(set) var state: LoadState = .idle

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded        // success (may be empty)
        case noCustomer    // conversation has no linked customer — hide section
        case error(String)

        public static func == (lhs: LoadState, rhs: LoadState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.loaded, .loaded), (.noCustomer, .noCustomer):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: Max tickets shown
    public static let maxTickets = 3

    // MARK: Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var loadedForCustomerId: Int64?

    // MARK: Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: Load

    /// Loads recent tickets for `customerId`.
    /// - Parameter customerName: Used as keyword for the server-side search (workaround for
    ///   missing `customer_id` query param on tickets list endpoint).
    public func load(customerId: Int64, customerName: String?) async {
        guard customerId > 0 else {
            state = .noCustomer
            return
        }
        // Avoid redundant re-fetch when already loaded for this customer.
        if loadedForCustomerId == customerId, state == .loaded { return }

        state = .loading
        do {
            let keyword = customerName.flatMap { $0.isEmpty ? nil : $0 }
            let response = try await api.listTickets(
                filter: .all,
                keyword: keyword,
                pageSize: 20   // fetch a small page; client filters by customer_id
            )
            let filtered = response.tickets
                .filter { $0.customerId == customerId }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(RecentTicketsViewModel.maxTickets)
            tickets = Array(filtered)
            loadedForCustomerId = customerId
            state = .loaded
        } catch {
            let msg = error.localizedDescription
            state = .error(msg)
        }
    }

    /// Resets state so the next `load` will re-fetch (e.g. customer changed).
    public func reset() {
        tickets = []
        state = .idle
        loadedForCustomerId = nil
    }
}

// MARK: - RecentTicketsSection

/// Compact horizontal strip shown above the conversation detail when the
/// selected thread has a linked customer. Shows up to 3 recent tickets;
/// hidden gracefully when no customer is linked or when load fails silently.
struct RecentTicketsSection: View {
    let api: APIClient
    let customerId: Int64
    var onOpenTicket: ((Int64) -> Void)?

    @State private var vm: RecentTicketsViewModel

    init(api: APIClient, customerId: Int64, onOpenTicket: ((Int64) -> Void)?) {
        self.api = api
        self.customerId = customerId
        self.onOpenTicket = onOpenTicket
        _vm = State(wrappedValue: RecentTicketsViewModel(api: api))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .noCustomer, .idle:
                EmptyView()
            case .loading:
                loadingStrip
            case .loaded:
                if vm.tickets.isEmpty {
                    EmptyView()
                } else {
                    ticketStrip
                }
            case .error:
                // Silent failure — hide the section, don't interrupt the user.
                EmptyView()
            }
        }
        .task(id: customerId) {
            vm.reset()
            await vm.load(customerId: customerId, customerName: nil)
        }
    }

    // MARK: - Loading state

    private var loadingStrip: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "ticket")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            ProgressView()
                .scaleEffect(0.6)
            Text("Loading tickets…")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color.bizarreSurface1)
        .accessibilityHidden(true)
    }

    // MARK: - Ticket strip

    private var ticketStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(vm.tickets) { ticket in
                        ticketChip(ticket)
                    }
                }
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .background(Color.bizarreSurface1)
    }

    private var sectionHeader: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Image(systemName: "ticket")
                .font(.system(size: 11))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Recent Tickets")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.top, BrandSpacing.xs)
    }

    private func ticketChip(_ ticket: TicketSummary) -> some View {
        Button {
            onOpenTicket?(ticket.id)
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                // Status colour dot
                if let color = ticket.status?.color, let uiColor = Color(hex: color) {
                    Circle()
                        .fill(uiColor)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                } else {
                    Circle()
                        .fill(Color.bizarreOnSurfaceMuted)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("#\(ticket.orderId)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let statusName = ticket.status?.name {
                        Text(statusName)
                            .font(.system(size: 10))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreSurfaceBase, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ticketA11yLabel(ticket))
        #if !os(macOS)
        .hoverEffect(.highlight)
        #endif
    }

    private func ticketA11yLabel(_ ticket: TicketSummary) -> String {
        var parts = ["Ticket \(ticket.orderId)"]
        if let name = ticket.status?.name { parts.append(name) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Color(hex:) helper (local — avoids importing DesignSystem internals)

private extension Color {
    /// Creates a `Color` from a 6-digit hex string like `"#FF5733"` or `"FF5733"`.
    /// Returns `nil` for malformed input.
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        guard hex.count == 6,
              let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double(value         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
