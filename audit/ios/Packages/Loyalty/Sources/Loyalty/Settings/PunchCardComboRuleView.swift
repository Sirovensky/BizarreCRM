import SwiftUI
import DesignSystem
import Networking
import Core

// §38 — Punch card combo rule settings:
//   "No stacking with other discounts unless configured"
// Tenant admin configures whether punch card rewards can be combined with
// other active discounts (coupons, membership discounts, LTV-tier perks).
//
// Enforcement: PunchCardRedemptionSheet shows the stacking toggle only when
// this tenant setting allows it. The `allowStacking` flag sent to the server
// is also validated server-side on POST /loyalty/punch-cards/:id/redeem.

// MARK: - Model

public struct PunchCardComboRuleSettings: Codable, Sendable {
    /// If false (default), punch card rewards cannot stack with any other discount.
    public var allowStackingByDefault: Bool
    /// Discount types explicitly excluded from stacking even when `allowStackingByDefault` is true.
    public var excludedDiscountTypes: [String]  // e.g. ["membership", "coupon", "ltv_tier"]

    public init(allowStackingByDefault: Bool = false, excludedDiscountTypes: [String] = []) {
        self.allowStackingByDefault = allowStackingByDefault
        self.excludedDiscountTypes = excludedDiscountTypes
    }

    enum CodingKeys: String, CodingKey {
        case allowStackingByDefault  = "allow_stacking_by_default"
        case excludedDiscountTypes   = "excluded_discount_types"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class PunchCardComboRuleViewModel {
    public private(set) var isLoading = true
    public var settings: PunchCardComboRuleSettings = .init()
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var savedSuccessfully = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getPunchCardComboRules()
        } catch {
            AppLog.ui.warning("Punch card combo rules fetch failed (may be 404): \(error.localizedDescription, privacy: .public)")
            settings = .init()
        }
    }

    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        savedSuccessfully = false
        defer { isSaving = false }
        do {
            settings = try await api.updatePunchCardComboRules(settings)
            savedSuccessfully = true
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    public func toggleExclusion(_ type: String) {
        if settings.excludedDiscountTypes.contains(type) {
            settings.excludedDiscountTypes.removeAll { $0 == type }
        } else {
            settings.excludedDiscountTypes.append(type)
        }
    }
}

// MARK: - View

/// Settings sub-page: Settings → Loyalty → Punch Cards → Combo rules.
public struct PunchCardComboRuleView: View {
    @State private var vm: PunchCardComboRuleViewModel
    @State private var showSavedToast = false

    private let discountTypes: [(key: String, label: String)] = [
        ("membership", "Membership discounts"),
        ("coupon",     "Coupon codes"),
        ("ltv_tier",   "LTV tier perks"),
        ("promo",      "Promotional prices")
    ]

    public init(api: APIClient) {
        _vm = State(wrappedValue: PunchCardComboRuleViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    stackingToggleSection
                    if vm.settings.allowStackingByDefault {
                        exclusionsSection
                    }
                    explainerSection
                    if let err = vm.errorMessage {
                        Section {
                            Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                        }
                        .listRowBackground(Color.bizarreError.opacity(0.08))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Punch Card Combo Rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(vm.isSaving ? "Saving…" : "Save") {
                    Task {
                        await vm.save()
                        if vm.savedSuccessfully { showSavedToast = true }
                    }
                }
                .disabled(vm.isSaving || vm.isLoading)
                .fontWeight(.semibold)
            }
        }
        .task { await vm.load() }
        .toast(isPresented: $showSavedToast, message: "Saved")
    }

    // MARK: - Sections

    private var stackingToggleSection: some View {
        Section("Stacking rule") {
            Toggle("Allow stacking with other discounts", isOn: $vm.settings.allowStackingByDefault)
                .accessibilityLabel("Allow punch card to stack with other discounts: \(vm.settings.allowStackingByDefault ? "on" : "off")")
            Text(vm.settings.allowStackingByDefault
                 ? "Punch card rewards CAN be combined with other discounts by default."
                 : "Punch card rewards CANNOT stack with other discounts (default).")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var exclusionsSection: some View {
        Section("Discount types excluded even when stacking is on") {
            ForEach(discountTypes, id: \.key) { dt in
                Toggle(dt.label, isOn: Binding(
                    get: { vm.settings.excludedDiscountTypes.contains(dt.key) },
                    set: { _ in vm.toggleExclusion(dt.key) }
                ))
                .accessibilityLabel("\(dt.label): \(vm.settings.excludedDiscountTypes.contains(dt.key) ? "excluded" : "allowed")")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var explainerSection: some View {
        Section {
            Label("This rule is enforced both in the app and server-side. Staff can override at redemption time if their role allows it.", systemImage: "info.circle")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}

// MARK: - Toast helper (local)

private extension View {
    func toast(isPresented: Binding<Bool>, message: String) -> some View {
        overlay(alignment: .bottom) {
            if isPresented.wrappedValue {
                Text(message)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .padding(.horizontal, BrandSpacing.lg)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.bizarreSuccess, in: Capsule())
                    .padding(.bottom, BrandSpacing.xl)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { isPresented.wrappedValue = false }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel(message)
            }
        }
        .animation(.easeInOut, value: isPresented.wrappedValue)
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/loyalty/punch-card-combo-rules`
    func getPunchCardComboRules() async throws -> PunchCardComboRuleSettings {
        try await get("/api/v1/loyalty/punch-card-combo-rules", as: PunchCardComboRuleSettings.self)
    }

    /// `PATCH /api/v1/loyalty/punch-card-combo-rules`
    @discardableResult
    func updatePunchCardComboRules(_ settings: PunchCardComboRuleSettings) async throws -> PunchCardComboRuleSettings {
        try await patch("/api/v1/loyalty/punch-card-combo-rules", body: settings, as: PunchCardComboRuleSettings.self)
    }
}
