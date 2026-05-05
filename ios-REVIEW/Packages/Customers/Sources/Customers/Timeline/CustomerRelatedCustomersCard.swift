#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.7 Related Customers Card
//
// Shows household / business links (family / coworker accounts) with
// relationship type labels. Tap any row to navigate to that customer.

// MARK: - Model

public struct CustomerRelationship: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let relatedCustomerId: Int64
    public let relatedCustomerName: String
    public let relatedCustomerPhone: String?
    public let relationshipType: RelationshipType

    public enum RelationshipType: String, Decodable, Sendable {
        case household   = "household"
        case family      = "family"
        case coworker    = "coworker"
        case business    = "business"
        case referral    = "referral"
        case other       = "other"

        var label: String {
            switch self {
            case .household: return "Household"
            case .family:    return "Family"
            case .coworker:  return "Coworker"
            case .business:  return "Business"
            case .referral:  return "Referral"
            case .other:     return "Related"
            }
        }

        var icon: String {
            switch self {
            case .household, .family: return "house"
            case .coworker, .business: return "building.2"
            case .referral:  return "person.badge.plus"
            case .other:     return "link"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case relatedCustomerId   = "related_customer_id"
        case relatedCustomerName = "related_customer_name"
        case relatedCustomerPhone = "related_customer_phone"
        case relationshipType    = "relationship_type"
    }
}

// MARK: - View

public struct CustomerRelatedCustomersCard: View {
    let customerId: Int64
    let api: APIClient
    /// Called when user taps a related customer row.
    var onSelectCustomer: ((Int64) -> Void)?

    @State private var relationships: [CustomerRelationship] = []
    @State private var isLoading = true
    @State private var showingAddSheet = false

    public init(
        customerId: Int64,
        api: APIClient,
        onSelectCustomer: ((Int64) -> Void)? = nil
    ) {
        self.customerId = customerId
        self.api = api
        self.onSelectCustomer = onSelectCustomer
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if relationships.isEmpty {
                emptyState
            } else {
                cardBody
            }
        }
        .task { await load() }
    }

    // MARK: - Card body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            ForEach(relationships) { rel in
                relationshipRow(rel)
                if rel.id != relationships.last?.id {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            Text("No linked accounts")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Related Accounts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Link a related customer")
        }
        .sheet(isPresented: $showingAddSheet) {
            Text("Link customer — coming soon")
                .font(.brandBodyMedium())
                .padding()
                .presentationDetents([.fraction(0.3)])
        }
    }

    private func relationshipRow(_ rel: CustomerRelationship) -> some View {
        Button {
            onSelectCustomer?(rel.relatedCustomerId)
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                // Avatar
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(String(rel.relatedCustomerName.prefix(1)).uppercased())
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rel.relatedCustomerName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    HStack(spacing: 4) {
                        Image(systemName: rel.relationshipType.icon)
                            .font(.caption2)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(rel.relationshipType.label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer(minLength: 0)

                if let phone = rel.relatedCustomerPhone, !phone.isEmpty {
                    Text(phone)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(rel.relatedCustomerName), \(rel.relationshipType.label). Tap to open.")
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        relationships = (try? await api.customerRelationships(customerId: customerId)) ?? []
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/:id/relationships` — linked household/business accounts.
    public func customerRelationships(customerId: Int64) async throws -> [CustomerRelationship] {
        try await get("/api/v1/customers/\(customerId)/relationships",
                      as: [CustomerRelationship].self)
    }
}

#endif
