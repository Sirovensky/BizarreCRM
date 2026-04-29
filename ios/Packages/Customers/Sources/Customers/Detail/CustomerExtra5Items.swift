#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Five additional open items
//
// 1. Birthday gift reminder chip — shows on customer detail when birthday is ≤ 14 days away.
// 2. Lifetime-spend card — formatted lifetime spend + percentile rank badge.
// 3. Anniversary chip — years-as-customer milestone badge surfaced in detail header area.
// 4. Marketing-channel preference row — read-only surface of preferred marketing channel from comm prefs.
// 5. Customer-portal magic-link copy — one-tap copy of the customer-portal deep link.

// ---------------------------------------------------------------------------
// MARK: 1 — Birthday gift reminder chip
// ---------------------------------------------------------------------------

/// Shown in the customer detail Info tab when the customer's birthday is within 14 days.
/// Taps open the birthday automation sheet.
public struct BirthdayGiftReminderChip: View {
    let detail: CustomerDetail
    let api: APIClient
    @State private var showingAutomation = false

    /// Returns the number of days until the next birthday, or nil when no birthday is stored
    /// or the birthday is more than 14 days away.
    private var daysUntilBirthday: Int? {
        // `birthday` field arrives as ISO-8601 date string "YYYY-MM-DD" in the extended
        // customer create payload; reuse the same key the server stores.
        guard let raw = detail.birthday, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let month = parts[1], day = parts[2 < parts.count ? 2 : 1]

        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        let year = today.year ?? 2026
        var nextBD = DateComponents(year: year, month: month, day: day)
        guard var nextDate = cal.date(from: nextBD) else { return nil }
        // Roll forward to next occurrence if already past this year's birthday.
        if nextDate < Date() {
            nextBD.year = year + 1
            guard let future = cal.date(from: nextBD) else { return nil }
            nextDate = future
        }
        let days = cal.dateComponents([.day], from: Date(), to: nextDate).day ?? Int.max
        return days <= 14 ? days : nil
    }

    public var body: some View {
        if let days = daysUntilBirthday {
            Button { showingAutomation = true } label: {
                HStack(spacing: BrandSpacing.xs) {
                    Image(systemName: "gift.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    Text(days == 0 ? "Birthday today!" : "Birthday in \(days)d")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreWarning)
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xs)
                .background(Color.bizarreWarning.opacity(0.13), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.bizarreWarning.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(days == 0
                ? "Birthday today — tap to configure gift automation"
                : "Birthday in \(days) days — tap to configure gift automation")
            .sheet(isPresented: $showingAutomation) {
                CustomerBirthdayAutomationSheet(
                    customerId: detail.id,
                    customerName: detail.displayName,
                    api: api
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: 2 — Lifetime-spend card
// ---------------------------------------------------------------------------

/// Card showing the customer's total lifetime spend formatted as currency, with a
/// descriptive percentile rank badge (Top 1 % / Top 10 % / Top 25 % / Standard).
/// Reads `ltvCents` from `CustomerDetail` (server-populated) and falls back to
/// `analytics.lifetimeValue` when available.
public struct CustomerLifetimeSpendCard: View {
    let detail: CustomerDetail
    let analytics: CustomerAnalytics?

    private var lifetimeDollars: Double {
        if let a = analytics, a.lifetimeValue > 0 { return a.lifetimeValue }
        if let c = detail.ltvCents, c > 0 { return Double(c) / 100.0 }
        return 0
    }

    private var formattedSpend: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: lifetimeDollars)) ?? "$\(Int(lifetimeDollars))"
    }

    private enum SpendTier {
        case top1, top10, top25, standard

        var label: String {
            switch self {
            case .top1:     return "Top 1%"
            case .top10:    return "Top 10%"
            case .top25:    return "Top 25%"
            case .standard: return "Standard"
            }
        }
        var color: Color {
            switch self {
            case .top1:     return .bizarreWarning
            case .top10:    return .bizarreTeal
            case .top25:    return .bizarreOrange
            case .standard: return .bizarreOnSurfaceMuted
            }
        }
        var icon: String {
            switch self {
            case .top1:     return "crown.fill"
            case .top10:    return "star.fill"
            case .top25:    return "star.leadinghalf.filled"
            case .standard: return "person.fill"
            }
        }
    }

    /// Heuristic thresholds — tenant analytics would replace these with real percentile
    /// data once the server exposes `/customers/:id/spend-percentile`.
    private var tier: SpendTier {
        switch lifetimeDollars {
        case 5000...:  return .top1
        case 1000...:  return .top10
        case 250...:   return .top25
        default:       return .standard
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text("Lifetime Spend")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                HStack(spacing: BrandSpacing.xxs) {
                    Image(systemName: tier.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tier.color)
                        .accessibilityHidden(true)
                    Text(tier.label)
                        .font(.brandLabelLarge())
                        .foregroundStyle(tier.color)
                }
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, BrandSpacing.xxs)
                .background(tier.color.opacity(0.12), in: Capsule())
            }

            Text(formattedSpend)
                .font(.brandDisplaySmall())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
                .accessibilityLabel("Lifetime spend: \(formattedSpend)")

            if let avg = analytics?.avgTicketValue, avg > 0 {
                let avgStr = NumberFormatter().then { $0.numberStyle = .currency; $0.currencyCode = "USD"; $0.maximumFractionDigits = 0 }.string(from: NSNumber(value: avg)) ?? "$\(Int(avg))"
                Text("Avg. ticket: \(avgStr)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

// ---------------------------------------------------------------------------
// MARK: 3 — Anniversary chip
// ---------------------------------------------------------------------------

/// Shows a "Xth year anniversary" chip in the customer detail when the anniversary
/// of `createdAt` falls within the next 7 days (or is today).
/// Intended to be placed in the header badge row alongside health / LTV chips.
public struct CustomerAnniversaryChip: View {
    let createdAt: String?

    /// (years, daysUntil) — nil when anniversary is more than 7 days away or date is missing.
    private var anniversaryInfo: (years: Int, daysUntil: Int)? {
        guard let raw = createdAt,
              let date = ISO8601DateFormatter().date(from: raw)
                ?? DateFormatter.yyyyMMdd.date(from: String(raw.prefix(10)))
        else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        let todayComps = cal.dateComponents([.year], from: Date())
        let thisYear = todayComps.year ?? 2026
        var nextAnn = DateComponents(year: thisYear, month: month, day: day)
        guard var nextDate = cal.date(from: nextAnn) else { return nil }
        if nextDate < Date() {
            nextAnn.year = thisYear + 1
            guard let future = cal.date(from: nextAnn) else { return nil }
            nextDate = future
        }
        let days = cal.dateComponents([.day], from: Date(), to: nextDate).day ?? Int.max
        guard days <= 7 else { return nil }
        // Calculate how many years as a customer this anniversary represents.
        let years = cal.dateComponents([.year], from: date, to: nextDate).year ?? 0
        return (years: years, daysUntil: days)
    }

    public var body: some View {
        if let info = anniversaryInfo {
            let label = "\(info.years)\(ordinal(info.years)) anniversary"
            let badge = info.daysUntil == 0 ? "Today!" : "in \(info.daysUntil)d"
            HStack(spacing: BrandSpacing.xxs) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreTeal)
                    .accessibilityHidden(true)
                Text("\(label) \(badge)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreTeal)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(Color.bizarreTeal.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreTeal.opacity(0.3), lineWidth: 0.5))
            .accessibilityLabel("Customer \(label) \(badge)")
        }
    }

    private func ordinal(_ n: Int) -> String {
        switch n % 10 {
        case 1 where n % 100 != 11: return "st"
        case 2 where n % 100 != 12: return "nd"
        case 3 where n % 100 != 13: return "rd"
        default: return "th"
        }
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// ---------------------------------------------------------------------------
// MARK: 4 — Marketing-channel preference row
// ---------------------------------------------------------------------------

/// Read-only surface of the customer's preferred marketing channel, loaded from the
/// existing `CustomerCommPrefsSheet` model.  Taps open the full `CustomerCommPrefsSheet`
/// so staff can update the preference inline.
public struct MarketingChannelPreferenceRow: View {
    let customerId: Int64
    let api: APIClient

    @State private var channel: CustomerPreferredChannel? = nil
    @State private var marketingOptIn: Bool = false
    @State private var showingPrefs = false

    public var body: some View {
        Button { showingPrefs = true } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: channelIcon)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marketing channel")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(channelLabel)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                Spacer(minLength: 0)
                if !marketingOptIn {
                    Text("Opted out")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, BrandSpacing.xxs)
                        .background(Color.bizarreError.opacity(0.10), in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, BrandSpacing.xxs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Marketing channel: \(channelLabel)\(marketingOptIn ? "" : ", opted out"). Tap to edit.")
        .task { await load() }
        .sheet(isPresented: $showingPrefs) {
            CustomerCommPrefsSheet(api: api, customerId: customerId)
        }
    }

    private var channelIcon: String { channel?.systemImage ?? "questionmark.circle" }
    private var channelLabel: String { channel?.displayName ?? "Not set" }

    private func load() async {
        if let prefs = try? await api.customerCommPrefs(customerId: customerId) {
            channel = prefs.preferredChannel
            marketingOptIn = prefs.marketingOptIn
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: 5 — Customer-portal magic-link copy
// ---------------------------------------------------------------------------

/// Small action chip that copies the customer self-service portal URL to the clipboard.
/// The portal URL format is: `https://app.bizarrecrm.com/portal/customer?id=<customerId>&token=<token>`
/// The token is fetched from `GET /api/v1/customers/:id/portal-link`.
///
/// Shows a brief "Copied!" confirmation via a local state toggle.
public struct CustomerPortalMagicLinkCopy: View {
    let customerId: Int64
    let api: APIClient

    @State private var isCopied = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    public var body: some View {
        Button { Task { await copyLink() } } label: {
            HStack(spacing: BrandSpacing.xs) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCopied ? .bizarreSuccess : .bizarreOrange)
                        .accessibilityHidden(true)
                }
                Text(isCopied ? "Copied!" : "Copy portal link")
                    .font(.brandLabelLarge())
                    .foregroundStyle(isCopied ? .bizarreSuccess : .bizarreOrange)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .background(
                (isCopied ? Color.bizarreSuccess : Color.bizarreOrange).opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    (isCopied ? Color.bizarreSuccess : Color.bizarreOrange).opacity(0.3),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isCopied ? "Portal link copied to clipboard" : "Copy customer portal link")
        .accessibilityHint("Generates a one-time login link for the customer self-service portal")
        .alert("Couldn't generate link", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let e = errorMessage { Text(e) }
        }
    }

    private func copyLink() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let link = try await api.customerPortalLink(customerId: customerId)
            UIPasteboard.general.string = link.url
            withAnimation(.easeInOut(duration: 0.2)) { isCopied = true }
            // Reset the "Copied!" state after 2 seconds.
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) { isCopied = false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Portal link DTO + APIClient extension

public struct CustomerPortalLinkResponse: Decodable, Sendable {
    /// Fully-qualified URL the customer can open to log into the self-service portal.
    public let url: String
    /// ISO-8601 expiry; typically 24h from generation.
    public let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
    }
}

public extension APIClient {
    /// `GET /api/v1/customers/:id/portal-link` — generate a magic-link URL for the
    /// customer self-service portal.  Each call generates a fresh single-use token.
    func customerPortalLink(customerId: Int64) async throws -> CustomerPortalLinkResponse {
        try await get("/api/v1/customers/\(customerId)/portal-link",
                      as: CustomerPortalLinkResponse.self)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Birthday field extension on CustomerDetail
// ---------------------------------------------------------------------------

// The server's `GET /customers/:id` response may include a `birthday` field
// (ISO-8601 date string, e.g. "1990-07-15") when the tenant has birthday features
// enabled.  We add it as an extension property so `CustomerDetail` does not need
// re-declaration and the main Networking package stays backward-compatible.

extension CustomerDetail {
    /// Birthday date string from the server (ISO-8601 "YYYY-MM-DD"), or nil.
    /// Read from `UserDefaults` keyed by customer ID as a local cache while the
    /// server wires the field into the GET /customers/:id response.
    public var birthday: String? {
        UserDefaults.standard.string(forKey: "customer.birthday.\(id)")
    }
}

// MARK: - NumberFormatter convenience for chain-style init

private extension NumberFormatter {
    func then(_ configure: (NumberFormatter) -> Void) -> NumberFormatter {
        configure(self)
        return self
    }
}

#endif
