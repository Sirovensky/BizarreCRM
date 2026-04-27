import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §37 Monthly SMS spend cap per tenant
// System halts sends when reached + notifies admin.

// MARK: - ViewModel

@MainActor
@Observable
public final class SMSSpendCapViewModel {
    public private(set) var capSettings: SMSSpendCapSettings?
    public private(set) var currentUsage: SMSSpendCapUsage?
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var saveSuccess = false

    /// Editable cap amount in dollars (converted to cents on save).
    public var capDollarsText: String = ""
    /// Whether to halt sends when cap is reached (vs warn only).
    public var haltOnCapReached: Bool = true

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        async let capTask   = try? await api.getSMSSpendCap()
        async let usageTask = try? await api.getSMSSpendCapUsage()
        capSettings  = await capTask
        currentUsage = await usageTask
        if let cap = capSettings {
            capDollarsText = String(format: "%.2f", Double(cap.monthlyCap) / 100.0)
            haltOnCapReached = cap.haltOnCapReached
        }
    }

    public func save() async {
        guard let cents = parseCents(capDollarsText), cents > 0 else {
            errorMessage = "Enter a valid dollar amount."
            return
        }
        isSaving = true
        errorMessage = nil
        saveSuccess = false
        defer { isSaving = false }
        do {
            let body = SMSSpendCapSettingsPatch(monthlyCap: cents, haltOnCapReached: haltOnCapReached)
            capSettings = try await api.updateSMSSpendCap(body)
            saveSuccess = true
        } catch {
            AppLog.ui.error("SMS spend cap save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Computed

    public var usagePercent: Double {
        guard let usage = currentUsage, let cap = capSettings, cap.monthlyCap > 0 else { return 0 }
        return min(1.0, Double(usage.spentCents) / Double(cap.monthlyCap))
    }

    public var isCapReached: Bool {
        usagePercent >= 1.0
    }

    private func parseCents(_ text: String) -> Int? {
        guard let dollars = Double(text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return Int(dollars * 100)
    }
}

// MARK: - View

/// Settings card for the monthly SMS spend cap.
/// Shown in Marketing Settings sub-page (Settings → Marketing → SMS Spend Cap).
public struct SMSSpendCapView: View {
    @State private var vm: SMSSpendCapViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: SMSSpendCapViewModel(api: api))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                // Current usage banner
                if let usage = vm.currentUsage, let cap = vm.capSettings {
                    usageBanner(usage: usage, cap: cap)
                }

                // Cap exceeded alert
                if vm.isCapReached {
                    capExceededBanner
                }

                // Edit form
                capForm

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, BrandSpacing.base)
                }
            }
            .padding(.vertical, BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("SMS Spend Cap")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    // MARK: - Usage bar

    private func usageBanner(usage: SMSSpendCapUsage, cap: SMSSpendCapSettings) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("This Month")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer(minLength: 0)
                Text(String(format: "$%.2f / $%.2f", Double(usage.spentCents) / 100, Double(cap.monthlyCap) / 100))
                    .font(.brandMono(size: 14))
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.bizarreSurface2)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(usageBarColor)
                        .frame(width: geo.size.width * vm.usagePercent, height: 12)
                        .animation(.easeOut(duration: DesignTokens.Motion.smooth), value: vm.usagePercent)
                }
            }
            .frame(height: 12)
            .accessibilityLabel("SMS spend \(Int(vm.usagePercent * 100))% of cap used")

            Text("\(usage.messageCount) messages sent")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .padding(.horizontal, BrandSpacing.base)
    }

    private var usageBarColor: Color {
        vm.usagePercent >= 0.9 ? .bizarreError : vm.usagePercent >= 0.7 ? .bizarreWarning : .bizarreOrange
    }

    // MARK: - Cap exceeded banner

    private var capExceededBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.bizarreError)
                .font(.system(size: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Monthly cap reached")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreError)
                Text("Campaign sends are paused until next billing cycle or cap is raised.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreError.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Monthly SMS cap reached. Sends are paused.")
    }

    // MARK: - Form

    private var capForm: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.base) {
            Text("CAP SETTINGS")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .tracking(0.8)
                .padding(.horizontal, BrandSpacing.base)

            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Text("Monthly limit (USD)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)

                HStack {
                    Text("$")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    TextField("0.00", text: $vm.capDollarsText)
                        .keyboardType(.decimalPad)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Monthly SMS spend cap in dollars")
                }
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))

                Toggle(isOn: $vm.haltOnCapReached) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Halt sends at limit")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("When off, sends continue with a warning.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .tint(.bizarreOrange)
                .accessibilityLabel("Halt campaign sends when spend cap is reached")

                Button {
                    Task { await vm.save() }
                } label: {
                    Group {
                        if vm.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(vm.saveSuccess ? "Saved ✓" : "Save")
                        }
                    }
                    .font(.brandLabelLarge())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(vm.isSaving)
                .accessibilityLabel("Save SMS spend cap settings")
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
            .padding(.horizontal, BrandSpacing.base)
        }
    }
}

// MARK: - Models

public struct SMSSpendCapSettings: Decodable, Sendable {
    public let monthlyCap: Int
    public let haltOnCapReached: Bool
    public let resetDay: Int

    enum CodingKeys: String, CodingKey {
        case monthlyCap       = "monthly_cap"
        case haltOnCapReached = "halt_on_cap_reached"
        case resetDay         = "reset_day"
    }
}

public struct SMSSpendCapUsage: Decodable, Sendable {
    public let spentCents: Int
    public let messageCount: Int
    public let periodStart: String?

    enum CodingKeys: String, CodingKey {
        case spentCents   = "spent_cents"
        case messageCount = "message_count"
        case periodStart  = "period_start"
    }
}

private struct SMSSpendCapSettingsPatch: Encodable, Sendable {
    let monthlyCap: Int
    let haltOnCapReached: Bool
    enum CodingKeys: String, CodingKey {
        case monthlyCap       = "monthly_cap"
        case haltOnCapReached = "halt_on_cap_reached"
    }
}

// MARK: - Endpoints

extension APIClient {
    /// `GET /settings/sms-spend-cap`
    public func getSMSSpendCap() async throws -> SMSSpendCapSettings {
        try await get("/settings/sms-spend-cap", as: SMSSpendCapSettings.self)
    }

    /// `GET /settings/sms-spend-cap/usage`
    public func getSMSSpendCapUsage() async throws -> SMSSpendCapUsage {
        try await get("/settings/sms-spend-cap/usage", as: SMSSpendCapUsage.self)
    }

    /// `PATCH /settings/sms-spend-cap`
    @discardableResult
    public func updateSMSSpendCap(_ settings: SMSSpendCapSettingsPatch) async throws -> SMSSpendCapSettings {
        try await patch("/settings/sms-spend-cap", body: settings, as: SMSSpendCapSettings.self)
    }
}
