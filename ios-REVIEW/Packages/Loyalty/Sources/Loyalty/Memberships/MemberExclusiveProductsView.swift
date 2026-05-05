import SwiftUI
import DesignSystem
import Networking

// MARK: - §38.5 Exclusive Products — hidden in catalog for non-members
//
// Staff-facing view: shows products restricted to active members.
// Non-member customers see a "Members-only" lock badge on any
// inventory item that has exclusive_tier set.
// This view surfaces the admin config for which products are exclusive.

// MARK: - Model

public struct ExclusiveProductEntry: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let sku: String?
    public let requiredTierName: String
    public let retailCents: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, sku
        case requiredTierName = "required_tier_name"
        case retailCents      = "retail_cents"
    }
}

// MARK: - Members-only badge (used on inventory rows)

/// Small badge to overlay on a product tile when the item is exclusive.
/// Pass `isMember: false` to show the lock; `true` to show a checkmark.
public struct MembersOnlyBadge: View {
    public let isMember: Bool
    public let tierName: String

    public init(isMember: Bool, tierName: String) {
        self.isMember = isMember
        self.tierName = tierName
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isMember ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(isMember ? tierName : "Members Only")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isMember ? .bizarreSuccess : .bizarreWarning)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            (isMember ? Color.bizarreSuccess : Color.bizarreWarning).opacity(0.12),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                (isMember ? Color.bizarreSuccess : Color.bizarreWarning).opacity(0.35),
                lineWidth: 0.5
            )
        )
        .accessibilityLabel(isMember ? "\(tierName) member — product available" : "Members only — \(tierName) required")
    }
}

// MARK: - Admin list view

/// Admin-facing list: shows all products flagged as tier-exclusive.
/// Accessible via Settings → Memberships → Exclusive Products.
public struct MemberExclusiveProductsView: View {
    let api: APIClient

    @State private var products: [ExclusiveProductEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    public init(api: APIClient) {
        self.api = api
    }

    private var filtered: [ExclusiveProductEntry] {
        guard !searchText.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.sku ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        Group {
            if isLoading, products.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
            } else if filtered.isEmpty {
                emptyState
            } else {
                productList
            }
        }
        .searchable(text: $searchText, prompt: "Search exclusive products")
        .navigationTitle("Exclusive Products")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var productList: some View {
        List(filtered) { product in
            HStack(spacing: BrandSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let sku = product.sku {
                        Text(sku)
                            .font(.brandMono(size: 12))
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    MembersOnlyBadge(isMember: false, tierName: product.requiredTierName)
                    if let cents = product.retailCents {
                        Text("$\(String(format: "%.2f", Double(cents) / 100))")
                            .font(.brandMono(size: 13))
                            .foregroundStyle(.bizarreOnSurface)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(product.name). \(product.sku.map { "SKU: \($0)." } ?? "") " +
                "Requires \(product.requiredTierName) membership."
            )
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Exclusive Products", systemImage: "lock.open")
        } description: {
            Text("Flag inventory items as member-exclusive in the Inventory module.")
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            products = try await api.listExclusiveProducts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/membership/exclusive-products` — products restricted to active members.
    func listExclusiveProducts() async throws -> [ExclusiveProductEntry] {
        try await get("/api/v1/membership/exclusive-products",
                      as: [ExclusiveProductEntry].self)
    }
}
