import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §3.4 My Queue — assigned tickets per user

// MARK: - Models

/// A ticket assigned to the current user. Decoded from GET /api/v1/tickets/my-queue.
public struct MyQueueTicket: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let orderId: String
    public let customerName: String?
    public let customerAvatarUrl: String?
    public let status: String
    public let ageInDays: Int
    public let dueDate: String?   // ISO-8601 date string (YYYY-MM-DD)

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case customerName = "customer_name"
        case customerAvatarUrl = "customer_avatar_url"
        case status
        case ageInDays = "age_in_days"
        case dueDate = "due_date"
    }
}

/// Response envelope for GET /api/v1/tickets/my-queue.
struct MyQueueResponse: Decodable {
    let success: Bool
    let data: [MyQueueTicket]?
    /// Optional field: `true` when the tenant policy blocks the requesting role
    /// from seeing team tickets. Drives the "Your shop has limited visibility" tooltip.
    let teamFilterBlocked: Bool?

    enum CodingKeys: String, CodingKey {
        case success
        case data
        case teamFilterBlocked = "team_filter_blocked"
    }
}

// MARK: - Age badge severity

private enum AgeSeverity {
    case red, amber, yellow, neutral

    static func from(days: Int) -> AgeSeverity {
        switch days {
        case 14...: return .red
        case 7..<14: return .amber
        case 3..<7:  return .yellow
        default:     return .neutral
        }
    }

    var color: Color {
        switch self {
        case .red:     return .bizarreError
        case .amber:   return .bizarreWarning
        case .yellow:  return Color.yellow.opacity(0.9)
        case .neutral: return .bizarreOnSurfaceMuted
        }
    }
}

private enum DueSeverity {
    case overdue, today, soon, later

    static func from(_ isoDate: String?) -> DueSeverity {
        guard let raw = isoDate else { return .later }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = fmt.date(from: String(raw.prefix(10))) else { return .later }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: date)
        let diff = cal.dateComponents([.day], from: today, to: due).day ?? 0
        switch diff {
        case ..<0:  return .overdue
        case 0:     return .today
        case 1...2: return .soon
        default:    return .later
        }
    }

    var color: Color {
        switch self {
        case .overdue: return .bizarreError
        case .today:   return .bizarreWarning
        case .soon:    return Color.yellow.opacity(0.9)
        case .later:   return .bizarreOnSurfaceMuted
        }
    }

    var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .today:   return "Due today"
        case .soon:    return "Due soon"
        case .later:   return "Due later"
        }
    }
}

// MARK: - ViewModel

public enum MyQueueFilter: String, CaseIterable, Identifiable, Sendable {
    case mine = "Mine"
    case mineAndTeam = "Mine + team"
    public var id: String { rawValue }
}

@MainActor
@Observable
public final class MyQueueViewModel {
    public private(set) var tickets: [MyQueueTicket] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var filter: MyQueueFilter = .mine {
        didSet {
            if oldValue != filter {
                Task { await load() }
            }
        }
    }
    /// When `true`, the "Mine + team" toggle is disabled because the tenant
    /// policy restricts this role from seeing team tickets. The UI shows a
    /// tooltip: "Your shop has limited visibility — ask an admin."
    public private(set) var isTeamFilterBlocked: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            // §3.4 — pass `scope` param so server can return mine-only vs mine+team.
            // Server ignores it gracefully if the param is unknown (backward compat).
            let scopeParam = filter == .mineAndTeam ? "&scope=team" : ""
            let resp = try await api.get(
                "/api/v1/tickets/my-queue?sort=due_asc\(scopeParam)",
                as: MyQueueResponse.self
            )
            // §3.4 — if server returned fewer results than expected due to role gate,
            // `team_filter_blocked` field (optional) indicates the toggle should be
            // shown as disabled. Decoded from envelope extension in MyQueueResponse.
            if let blocked = resp.teamFilterBlocked {
                isTeamFilterBlocked = blocked
            }
            // Sort: due date ASC, then age DESC (client mirrors server default)
            tickets = (resp.data ?? []).sorted { a, b in
                let da = DueSeverity.from(a.dueDate)
                let db = DueSeverity.from(b.dueDate)
                let aOrd = ordinal(da)
                let bOrd = ordinal(db)
                if aOrd != bOrd { return aOrd < bOrd }
                return a.ageInDays > b.ageInDays
            }
        } catch {
            AppLog.ui.error("MyQueue load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func startAutoRefresh(interval: TimeInterval = 30) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.load()
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func ordinal(_ s: DueSeverity) -> Int {
        switch s {
        case .overdue: return 0
        case .today:   return 1
        case .soon:    return 2
        case .later:   return 3
        }
    }
}

// MARK: - View

/// §3.4 My Queue — dashboard section. Always visible to every signed-in user.
/// Auto-refreshes every 30s while foregrounded.
public struct MyQueueView: View {
    @State private var vm: MyQueueViewModel
    public var onTicketTap: ((Int64) -> Void)?
    public var onStartWork: ((Int64) -> Void)?
    public var onMarkReady: ((Int64) -> Void)?
    public var onComplete: ((Int64) -> Void)?

    public init(
        api: APIClient,
        onTicketTap: ((Int64) -> Void)? = nil,
        onStartWork: ((Int64) -> Void)? = nil,
        onMarkReady: ((Int64) -> Void)? = nil,
        onComplete: ((Int64) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: MyQueueViewModel(api: api))
        self.onTicketTap = onTicketTap
        self.onStartWork = onStartWork
        self.onMarkReady = onMarkReady
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .accessibilityLabel("Loading my queue")
            } else if let err = vm.errorMessage {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
            } else if vm.tickets.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.tickets) { ticket in
                        QueueRow(
                            ticket: ticket,
                            onTap: { onTicketTap?(ticket.id) },
                            onStartWork: { onStartWork?(ticket.id) },
                            onMarkReady: { onMarkReady?(ticket.id) },
                            onComplete: { onComplete?(ticket.id) }
                        )
                        .listRowBackground(Color.bizarreSurface1)
                        Divider()
                            .padding(.leading, BrandSpacing.lg + 28)
                    }
                }
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
                )
            }
        }
        .task {
            await vm.load()
            vm.startAutoRefresh()
        }
        .onDisappear { vm.stopAutoRefresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("My queue: \(vm.tickets.count) tickets")
    }

    private var header: some View {
        HStack {
            Text("MY QUEUE")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            // §3.4 Mine / Mine+Team toggle.
            // Disabled with tooltip when tenant policy blocks team visibility for this role.
            if vm.isTeamFilterBlocked {
                Picker("Queue filter", selection: .constant(MyQueueFilter.mine)) {
                    ForEach(MyQueueFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .font(.brandLabelSmall())
                .disabled(true)
                .opacity(0.5)
                .help("Your shop has limited visibility — ask an admin.")
                .accessibilityHint("Disabled: Your shop has limited visibility — ask an admin.")
                .accessibilityIdentifier("myQueue.filter")
            } else {
                Picker("Queue filter", selection: $vm.filter) {
                    ForEach(MyQueueFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .font(.brandLabelSmall())
                .accessibilityIdentifier("myQueue.filter")
            }
        }
        .padding(.bottom, BrandSpacing.xs)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No tickets assigned to you")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Queue row

private struct QueueRow: View {
    let ticket: MyQueueTicket
    var onTap: () -> Void
    var onStartWork: () -> Void
    var onMarkReady: () -> Void
    var onComplete: () -> Void

    private var ageSeverity: AgeSeverity { .from(days: ticket.ageInDays) }
    private var dueSeverity: DueSeverity { .from(ticket.dueDate) }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: BrandSpacing.md) {
                // Avatar placeholder
                Circle()
                    .fill(Color.bizarreSurface2)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(initials)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ticket.orderId)
                            .font(.brandBodyLarge())
                            .fontWeight(.semibold)
                            .foregroundStyle(.bizarreOnSurface)
                        StatusChip(status: ticket.status)
                    }
                    if let name = ticket.customerName {
                        Text(name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // Age badge
                    Text("\(ticket.ageInDays)d")
                        .font(.brandLabelSmall())
                        .foregroundStyle(ageSeverity.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(ageSeverity.color.opacity(0.12), in: Capsule())
                        .accessibilityLabel("\(ticket.ageInDays) days old")

                    // Due-date badge
                    if ticket.dueDate != nil {
                        Text(dueSeverity.label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(dueSeverity.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(dueSeverity.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // §3.4 iPhone swipe + context menu for quick actions
        .swipeActions(edge: .leading) {
            Button { onStartWork() } label: {
                Label("Start work", systemImage: "play.fill")
            }
            .tint(.bizarreOrange)
        }
        .swipeActions(edge: .trailing) {
            Button { onComplete() } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .tint(.bizarreSuccess)
            Button { onMarkReady() } label: {
                Label("Mark ready", systemImage: "bell.badge")
            }
            .tint(.bizarreTeal)
        }
        .contextMenu {
            Button { onStartWork() } label: { Label("Start work", systemImage: "play.fill") }
            Button { onMarkReady() } label: { Label("Mark ready", systemImage: "bell.badge") }
            Button { onComplete() } label: { Label("Complete", systemImage: "checkmark.circle") }
            Divider()
            Button { onTap() } label: { Label("Open ticket", systemImage: "arrow.up.right.square") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var initials: String {
        guard let name = ticket.customerName else { return "?" }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var a11yLabel: String {
        let customer = ticket.customerName ?? "Unknown customer"
        return "Ticket \(ticket.orderId), \(customer), \(ticket.status), \(ticket.ageInDays) days old, \(dueSeverity.label)"
    }
}

// MARK: - Status chip

private struct StatusChip: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "new":        return .bizarreOrange
        case "in-progress", "in_progress", "in progress": return .bizarreTeal
        case "waiting":    return .bizarreWarning
        case "done", "completed", "closed": return .bizarreSuccess
        default:           return .bizarreOnSurfaceMuted
        }
    }

    var body: some View {
        Text(status)
            .font(.brandLabelSmall())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(status)")
    }
}
