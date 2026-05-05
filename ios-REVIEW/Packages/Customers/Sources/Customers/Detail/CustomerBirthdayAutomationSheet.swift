#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Birthday Automation — per-customer opt-in
//
// - Day-of auto-send SMS or email template ("Happy birthday! Here's $10 off")
// - Per-customer opt-in for birthday automation (default: off)
// - Privacy: never show birth date in lists / leaderboards
// - Age-derived features off by default
// - Exclusion: last-60-days visited customers get less salesy message
// - Exclusion: churned customers get reactivation variant

// MARK: - Birthday automation preferences DTO

public struct CustomerBirthdayAutomationPrefs: Codable, Sendable {
    /// Customer has opted into birthday automations.
    public var optedIn: Bool
    /// Preferred channel for birthday message (nil = use tenant default).
    public var preferredChannel: BirthdayChannel?
    /// Exclude from full promo if visited in last N days (nil = use tenant default).
    public var recentVisitExclusionDays: Int?
    /// Whether to inject a unique coupon code (§37) with 7-day expiry in the birthday message.
    public var injectCoupon: Bool
    /// Template ID for the coupon to inject (tenant-configured; nil = use tenant default).
    public var couponTemplateId: String?

    public init(
        optedIn: Bool = false,
        preferredChannel: BirthdayChannel? = nil,
        recentVisitExclusionDays: Int? = nil,
        injectCoupon: Bool = false,
        couponTemplateId: String? = nil
    ) {
        self.optedIn = optedIn
        self.preferredChannel = preferredChannel
        self.recentVisitExclusionDays = recentVisitExclusionDays
        self.injectCoupon = injectCoupon
        self.couponTemplateId = couponTemplateId
    }

    public enum BirthdayChannel: String, Codable, Sendable, CaseIterable {
        case sms    = "sms"
        case email  = "email"
        case push   = "push"
        case none   = "none"

        var label: String {
            switch self {
            case .sms:   return "SMS"
            case .email: return "Email"
            case .push:  return "Push notification"
            case .none:  return "None (skip)"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case optedIn               = "opted_in"
        case preferredChannel      = "preferred_channel"
        case recentVisitExclusionDays = "recent_visit_exclusion_days"
        case injectCoupon          = "inject_coupon"
        case couponTemplateId      = "coupon_template_id"
    }
}

// MARK: - Sheet view

public struct CustomerBirthdayAutomationSheet: View {
    let customerId: Int64
    let customerName: String
    let api: APIClient
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var prefs: CustomerBirthdayAutomationPrefs = .init(optedIn: false)
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    public init(
        customerId: Int64,
        customerName: String,
        api: APIClient,
        onSave: (() -> Void)? = nil
    ) {
        self.customerId = customerId
        self.customerName = customerName
        self.api = api
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $prefs.optedIn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Birthday Automation")
                                .font(.brandBodyMedium())
                            Text("Auto-send template on day of birthday")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .tint(.bizarreOrange)
                } header: {
                    Text("Automation")
                } footer: {
                    Text("Age and birth date are never shown in lists, leaderboards, or analytics. Date is used only to schedule the birthday message.")
                        .font(.brandLabelSmall())
                }

                if prefs.optedIn {
                    Section("Channel") {
                        Picker("Send via", selection: Binding(
                            get: { prefs.preferredChannel ?? .sms },
                            set: { prefs.preferredChannel = $0 }
                        )) {
                            ForEach(CustomerBirthdayAutomationPrefs.BirthdayChannel.allCases,
                                    id: \.rawValue) { ch in
                                Text(ch.label).tag(ch)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                            Text("If visited in last \(prefs.recentVisitExclusionDays ?? 60) days")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Send a lighter, less salesy message to recent visitors; churned customers receive a reactivation variant instead.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)

                            Stepper(
                                "\(prefs.recentVisitExclusionDays ?? 60) days",
                                value: Binding(
                                    get: { prefs.recentVisitExclusionDays ?? 60 },
                                    set: { prefs.recentVisitExclusionDays = $0 }
                                ),
                                in: 7...180,
                                step: 7
                            )
                            .font(.brandBodyMedium())
                        }
                    } header: {
                        Text("Exclusion rules")
                    } footer: {
                        Text("Server applies tenant-level exclusion rules in addition to these per-customer settings.")
                            .font(.brandLabelSmall())
                    }

                    // §5 — Inject unique coupon (§37) per recipient with 7-day expiry
                    Section {
                        Toggle(isOn: $prefs.injectCoupon) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Inject Unique Coupon")
                                    .font(.brandBodyMedium())
                                Text("Generate a one-time code per recipient (7-day expiry)")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Inject unique coupon with 7-day expiry")

                        if prefs.injectCoupon {
                            HStack {
                                Text("Coupon template")
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Spacer()
                                Text(prefs.couponTemplateId ?? "Tenant default")
                                    .font(.brandLabelLarge())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Coupon template: \(prefs.couponTemplateId ?? "Tenant default")")
                        }
                    } header: {
                        Text("Coupon")
                    } footer: {
                        Text("The server generates a unique code per recipient and embeds it in the birthday message. The code expires 7 days after the customer's birthday.")
                            .font(.brandLabelSmall())
                    }

                    Section {
                        LabeledContent("Age-derived features", value: "Off by default")
                        LabeledContent("Birthday in lists", value: "Never shown")
                    } header: {
                        Text("Privacy & Compliance")
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .navigationTitle("Birthday Automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(isLoading || isSaving)
            .overlay {
                if isLoading { ProgressView() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let p = try? await api.getCustomerBirthdayPrefs(customerId: customerId) {
            prefs = p
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await api.setCustomerBirthdayPrefs(customerId: customerId, prefs: prefs)
            onSave?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/:id/birthday-prefs` — load birthday automation prefs.
    public func getCustomerBirthdayPrefs(customerId: Int64) async throws -> CustomerBirthdayAutomationPrefs {
        try await get("/api/v1/customers/\(customerId)/birthday-prefs",
                      as: CustomerBirthdayAutomationPrefs.self)
    }

    /// `PUT /api/v1/customers/:id/birthday-prefs` — save birthday automation prefs.
    public func setCustomerBirthdayPrefs(
        customerId: Int64,
        prefs: CustomerBirthdayAutomationPrefs
    ) async throws {
        try await put("/api/v1/customers/\(customerId)/birthday-prefs",
                      body: prefs, as: EmptyResponse.self)
    }
}

#endif
