#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §6.2 Full movement history — cursor-based, offline-first
// GET /api/v1/inventory/:sku/movements?cursor=&limit=50
// Implements the top-of-doc cursor pagination contract (same as §20.5).

// MARK: - Network response

public struct InventoryMovementsPage: Decodable, Sendable {
    public let movements: [InventoryMovementEntry]
    public let nextCursor: String?
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case movements
        case nextCursor = "next_cursor"
        case hasMore    = "has_more"
    }
}

public struct InventoryMovementEntry: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let type: String?
    public let quantity: Double?
    public let reason: String?
    public let reference: String?
    public let userName: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, quantity, reason, reference
        case userName  = "user_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public var typeDisplay: String {
        switch type?.lowercased() {
        case "receive":      return "Received"
        case "sale":         return "Sold"
        case "adjust":       return "Adjusted"
        case "transfer_in":  return "Transfer In"
        case "transfer_out": return "Transfer Out"
        case "damage":       return "Damage"
        case "shrinkage":    return "Shrinkage"
        case "return":       return "Return"
        default:             return type?.capitalized ?? "Movement"
        }
    }

    public var isInbound: Bool {
        guard let t = type?.lowercased() else { return false }
        return ["receive", "return", "transfer_in", "adjust"].contains(t)
    }
}

// MARK: - APIClient extension (append-only)

public extension APIClient {
    /// §6.2 GET /api/v1/inventory/:itemId/movements?cursor=&limit=50
    func listInventoryMovements(itemId: Int64, cursor: String? = nil, limit: Int = 50) async throws -> InventoryMovementsPage {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let c = cursor { query.append(URLQueryItem(name: "cursor", value: c)) }
        return try await get("/api/v1/inventory/\(itemId)/movements",
                             query: query,
                             as: InventoryMovementsPage.self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class InventoryMovementHistoryViewModel {
    public private(set) var movements: [InventoryMovementEntry] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isLoadingMore: Bool = false
    public private(set) var hasMore: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var isOfflineCached: Bool = false

    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private let itemId: Int64
    @ObservationIgnored private let api: APIClient?

    public init(itemId: Int64, api: APIClient?) {
        self.itemId = itemId
        self.api = api
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        defer { isLoading = false }
        guard let api else { return }
        do {
            let page = try await api.listInventoryMovements(itemId: itemId, cursor: nil)
            movements = page.movements
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch is URLError {
            isOfflineCached = true
            // Offline: display what was already loaded (cached from prior online session)
            if movements.isEmpty {
                errorMessage = "Offline — movement history unavailable."
            }
        } catch {
            AppLog.ui.error("MovementHistory load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor, let api else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.listInventoryMovements(itemId: itemId, cursor: cursor)
            movements.append(contentsOf: page.movements)
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            AppLog.ui.error("MovementHistory loadMore failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - View

/// Full movement history sheet — presented from InventoryDetailView.
public struct InventoryMovementHistoryView: View {
    @State private var vm: InventoryMovementHistoryViewModel

    public init(itemId: Int64, api: APIClient?) {
        _vm = State(wrappedValue: InventoryMovementHistoryViewModel(itemId: itemId, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Movement History")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading movement history")
        } else if let err = vm.errorMessage, vm.movements.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.movements.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No movement history yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("No movement history")
        } else {
            List {
                if vm.isOfflineCached {
                    Section {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: "wifi.slash").foregroundStyle(.bizarreWarning).accessibilityHidden(true)
                            Text("Offline — showing cached history. Go online to load more.")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreWarning)
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }

                ForEach(vm.movements) { entry in
                    MovementRow(entry: entry)
                        .listRowBackground(Color.bizarreSurface1)
                }

                // Footer — load more / end of list
                if vm.hasMore {
                    Section {
                        Button("Load more") { Task { await vm.loadMore() } }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Load more movement history")
                    }
                    .listRowBackground(Color.bizarreSurface1)
                } else if !vm.movements.isEmpty {
                    Section {
                        Text("All \(vm.movements.count) movements loaded.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Movement row

private struct MovementRow: View {
    let entry: InventoryMovementEntry

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            // Direction indicator
            Image(systemName: entry.isInbound ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(entry.isInbound ? .bizarreSuccess : .bizarreError)
                .font(.system(size: 20))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(entry.typeDisplay)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    if let qty = entry.quantity {
                        Text("\(entry.isInbound ? "+" : "")\(formatQty(qty))")
                            .font(.brandTitleMedium())
                            .monospacedDigit()
                            .foregroundStyle(entry.isInbound ? .bizarreSuccess : .bizarreError)
                    }
                }
                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let ref = entry.reference, !ref.isEmpty {
                    Text("Ref: \(ref)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
                HStack(spacing: BrandSpacing.sm) {
                    if let user = entry.userName, !user.isEmpty {
                        Text(user).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    if let dateStr = entry.createdAt, let date = parseDate(dateStr) {
                        Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.typeDisplay)"
            + (entry.quantity.map { ", \($0 > 0 ? "+" : "")\(formatQty($0))" } ?? "")
            + (entry.reason.map { ", \($0)" } ?? "")
        )
    }

    private func formatQty(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func parseDate(_ s: String) -> Date? {
        let fmts = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                    "yyyy-MM-dd'T'HH:mm:ssZ",
                    "yyyy-MM-dd HH:mm:ss"]
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in fmts {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

#endif
