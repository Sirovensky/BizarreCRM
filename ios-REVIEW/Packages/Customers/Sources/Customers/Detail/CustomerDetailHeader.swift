#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Contacts
import ContactsUI

// MARK: - §5.2 Customer Detail Header
// avatar + name + LTV tier chip + health-score ring + VIP star

public struct CustomerDetailHeader: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?
    let api: APIClient
    var onHealthTap: () -> Void
    var onLTVTap: () -> Void

    private var health: CustomerHealthScoreResult {
        CustomerHealthScoreResult.compute(detail: detail)
    }

    private var ltvCents: Int {
        if let a = analytics, a.lifetimeValue > 0 { return Int(a.lifetimeValue * 100) }
        if let c = detail.ltvCents, c > 0 { return Int(c) }
        return 0
    }
    private var tier: LTVTier { LTVCalculator.tier(for: ltvCents) }
    private var isVIP: Bool { tier == .platinum || tier == .gold }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            ZStack(alignment: .topTrailing) {
                // Avatar circle
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(detail.initials)
                        .font(.brandDisplayMedium())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

                if isVIP {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.bizarreWarning)
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            }

            Text(detail.displayName)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            if let group = detail.customerGroupName, !group.isEmpty {
                Text(group)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            // Badge row: health ring + LTV tier
            HStack(spacing: BrandSpacing.sm) {
                // Health-score ring button
                Button { onHealthTap() } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        SmallHealthRing(score: health.value, tier: health.tier)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(healthLabel)
                                .font(.brandLabelLarge())
                                .foregroundStyle(healthColor)
                            Text("Health")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(healthColor.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Health score \(health.value) of 100, \(healthLabel). Tap for breakdown.")

                // LTV tier chip button
                Button { onLTVTap() } label: {
                    HStack(spacing: BrandSpacing.xs) {
                        Image(systemName: tier.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tier.color)
                            .accessibilityHidden(true)
                        Text(tier.label)
                            .font(.brandLabelLarge())
                            .foregroundStyle(tier.color)
                    }
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xs)
                    .background(tier.color.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(tier.color.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("LTV \(tier.label) tier. Tap for details.")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.md)
    }

    private var healthLabel: String {
        switch health.tier {
        case .green:  return "Healthy"
        case .yellow: return "At Risk"
        case .red:    return "Critical"
        }
    }
    private var healthColor: Color {
        switch health.tier {
        case .green:  return .bizarreSuccess
        case .yellow: return .bizarreWarning
        case .red:    return .bizarreError
        }
    }
}

// MARK: - Small ring (for header badge)

private struct SmallHealthRing: View {
    let score: Int
    let tier: CustomerHealthTier

    private var color: Color {
        switch tier {
        case .green:  return .bizarreSuccess
        case .yellow: return .bizarreWarning
        case .red:    return .bizarreError
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: score)
            Text("\(score)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

// MARK: - §5.2 Contact card — multi-phone, multi-email, address→Maps, birthday, comm prefs

public struct CustomerFullContactCard: View {
    let detail: CustomerDetail
    let onMapsTap: ((String) -> Void)?

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Contact")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            // Multi-phone rows
            if let rows = detail.phones, !rows.isEmpty {
                ForEach(rows) { r in
                    contactRow("phone", label: r.label ?? "Phone", value: PhoneFormatter.format(r.phone), mono: true)
                }
            } else {
                if let m = detail.mobile, !m.isEmpty {
                    contactRow("phone", label: "Mobile", value: PhoneFormatter.format(m), mono: true)
                }
                if let p = detail.phone, !p.isEmpty, p != detail.mobile {
                    contactRow("phone", label: "Phone", value: PhoneFormatter.format(p), mono: true)
                }
            }

            // Multi-email rows
            if let rows = detail.emails, !rows.isEmpty {
                ForEach(rows) { r in
                    contactRow("envelope", label: r.label ?? "Email", value: r.email)
                }
            } else if let e = detail.email, !e.isEmpty {
                contactRow("envelope", label: "Email", value: e)
            }

            // Address (tap → Maps)
            if let addr = detail.addressLine {
                Button {
                    let q = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    if let url = URL(string: "maps://?q=\(q)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(alignment: .top, spacing: BrandSpacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.bizarreOrange)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Address")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Text(addr)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(.vertical, BrandSpacing.xxs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Address: \(addr). Open in Maps.")
            }

            if let org = detail.organization, !org.isEmpty {
                contactRow("building.2", label: "Organization", value: org)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func contactRow(_ icon: String, label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(value)
                    .font(mono ? .brandMono(size: 14) : .brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - §5.2 Share vCard + Add to iOS Contacts

public struct CustomerVCardActions: View {
    let detail: CustomerDetail
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    @State private var showingContactVC = false
    @State private var vcardData: Data?

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Button {
                generateVCard()
                showingShareSheet = true
            } label: {
                Label("Share vCard", systemImage: "square.and.arrow.up")
                    .font(.brandLabelLarge())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreOrange)
            .accessibilityLabel("Share customer as vCard")

            Button {
                generateVCard()
                showingContactVC = true
            } label: {
                Label("Add to Contacts", systemImage: "person.badge.plus")
                    .font(.brandLabelLarge())
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.bizarreTeal)
            .accessibilityLabel("Add customer to iOS Contacts")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = vcardData {
                VCardShareSheet(vcardData: data, displayName: detail.displayName)
            }
        }
        .sheet(isPresented: $showingContactVC) {
            if let data = vcardData,
               let contacts = try? CNContactVCardSerialization.contacts(with: data),
               let contact = contacts.first {
                ContactViewControllerRepresentable(contact: contact)
            }
        }
    }

    private func generateVCard() {
        let mutableContact = CNMutableContact()
        mutableContact.givenName = detail.firstName ?? ""
        mutableContact.familyName = detail.lastName ?? ""
        if let org = detail.organization, !org.isEmpty {
            mutableContact.organizationName = org
        }
        // Phones
        var phones: [CNLabeledValue<CNPhoneNumber>] = []
        if let m = detail.mobile, !m.isEmpty {
            phones.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: m)))
        }
        if let p = detail.phone, !p.isEmpty, p != detail.mobile {
            phones.append(CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: p)))
        }
        if let rows = detail.phones {
            for r in rows {
                let cnLabel = r.label.map { l -> String in
                    switch l.lowercased() {
                    case "mobile": return CNLabelPhoneNumberMobile
                    case "work":   return CNLabelWork
                    default:       return CNLabelHome
                    }
                } ?? CNLabelHome
                phones.append(CNLabeledValue(label: cnLabel, value: CNPhoneNumber(stringValue: r.phone)))
            }
        }
        mutableContact.phoneNumbers = phones

        // Emails
        var emailValues: [CNLabeledValue<NSString>] = []
        if let e = detail.email, !e.isEmpty {
            emailValues.append(CNLabeledValue(label: CNLabelHome, value: e as NSString))
        }
        if let rows = detail.emails {
            for r in rows {
                let label = r.label?.lowercased() == "work" ? CNLabelWork : CNLabelHome
                emailValues.append(CNLabeledValue(label: label, value: r.email as NSString))
            }
        }
        mutableContact.emailAddresses = emailValues

        // Address
        if let a1 = detail.address1, !a1.isEmpty {
            let addr = CNMutablePostalAddress()
            addr.street = a1
            addr.city = detail.city ?? ""
            addr.state = detail.state ?? ""
            addr.postalCode = detail.postcode ?? ""
            addr.country = detail.country ?? ""
            mutableContact.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: addr)]
        }

        if let data = try? CNContactVCardSerialization.data(with: [mutableContact]) {
            vcardData = data
        }
    }
}

// MARK: - Share sheet wrapper

private struct VCardShareSheet: UIViewControllerRepresentable {
    let vcardData: Data
    let displayName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Write to temp file so it can be shared as .vcf
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(displayName).vcf")
        try? vcardData.write(to: url)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CNContactViewController wrapper

private struct ContactViewControllerRepresentable: UIViewControllerRepresentable {
    let contact: CNContact

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = CNContactViewController(forUnknownContact: contact)
        vc.contactStore = CNContactStore()
        vc.allowsEditing = true
        vc.allowsActions = false
        return UINavigationController(rootViewController: vc)
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - §5.2 Delete customer confirm dialog

public struct CustomerDeleteButton: View {
    let customerId: Int64
    let displayName: String
    let openTicketCount: Int
    let api: APIClient
    var onDeleted: () -> Void

    @State private var showingConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
            }

            Button(role: .destructive) {
                showingConfirm = true
            } label: {
                Group {
                    if isDeleting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Delete Customer", systemImage: "trash")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreError)
            .disabled(isDeleting)
            .accessibilityLabel("Delete customer \(displayName)")
            .confirmationDialog(
                "Delete \(displayName)?",
                isPresented: $showingConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task { await deleteCustomer() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if openTicketCount > 0 {
                    Text("This customer has \(openTicketCount) open ticket\(openTicketCount == 1 ? "" : "s"). Deleting is irreversible.")
                } else {
                    Text("This action cannot be undone.")
                }
            }
        }
    }

    private func deleteCustomer() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await api.deleteCustomer(id: customerId)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - §5.2 Membership card on customer detail

public struct CustomerMembershipCard: View {
    let customerId: Int64
    let api: APIClient

    @State private var membershipInfo: CustomerMembershipInfo?
    @State private var isLoading = true

    public var body: some View {
        Group {
            if let info = membershipInfo {
                membershipView(info)
            } else if !isLoading {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // GET /api/v1/memberships?customer_id=:id
        if let info = try? await api.customerMembership(customerId: customerId) {
            membershipInfo = info
        }
    }

    @ViewBuilder
    private func membershipView(_ info: CustomerMembershipInfo) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "star.circle.fill")
                    .foregroundStyle(.bizarreWarning)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
                Text("Membership")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Text(info.planName)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreWarning)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
            }

            if let nextBilling = info.nextBillingDate {
                HStack {
                    Text("Next billing:")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(String(nextBilling.prefix(10)))
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }

            if let perks = info.perksDescription, !perks.isEmpty {
                Text(perks)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreWarning.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreWarning.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - DTO

public struct CustomerMembershipInfo: Decodable, Sendable {
    public let id: Int64
    public let planName: String
    public let status: String
    public let nextBillingDate: String?
    public let perksDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case planName = "plan_name"
        case nextBillingDate = "next_billing_date"
        case perksDescription = "perks_description"
    }
}

// MARK: - APIClient extension for customer membership

extension APIClient {
    /// `GET /api/v1/memberships?customer_id=:id` — active membership for this customer.
    public func customerMembership(customerId: Int64) async throws -> CustomerMembershipInfo {
        let items = [URLQueryItem(name: "customer_id", value: String(customerId))]
        return try await get("/api/v1/memberships", query: items, as: CustomerMembershipInfo.self)
    }
}

#endif
