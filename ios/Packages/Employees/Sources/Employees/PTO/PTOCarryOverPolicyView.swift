import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PTOCarryOverPolicyView
//
// §46.3 — Tenant-configured carry-over + expiry policy for PTO.
// Settings → Team → Time Off → Carry-Over & Expiry.
// Shows "X days expire Dec 31" banner on employee PTO balance screen.

public struct PTOCarryOverPolicy: Codable, Sendable {
    public var carryOverEnabled: Bool
    public var maxCarryOverDays: Int
    public var expiryMonth: Int  // 1-12; 12 = December
    public var expiryDay: Int    // 1-31

    public init(
        carryOverEnabled: Bool = false,
        maxCarryOverDays: Int = 5,
        expiryMonth: Int = 12,
        expiryDay: Int = 31
    ) {
        self.carryOverEnabled = carryOverEnabled
        self.maxCarryOverDays = maxCarryOverDays
        self.expiryMonth = expiryMonth
        self.expiryDay = expiryDay
    }

    /// Human-readable expiry string, e.g. "Dec 31".
    public var expiryDisplayString: String {
        var comps = DateComponents()
        comps.month = expiryMonth
        comps.day   = expiryDay
        comps.year  = Calendar.current.component(.year, from: Date())
        if let date = Calendar.current.date(from: comps) {
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return fmt.string(from: date)
        }
        return "\(expiryMonth)/\(expiryDay)"
    }

    enum CodingKeys: String, CodingKey {
        case carryOverEnabled  = "carry_over_enabled"
        case maxCarryOverDays  = "max_carry_over_days"
        case expiryMonth       = "expiry_month"
        case expiryDay         = "expiry_day"
    }
}

@MainActor
@Observable
public final class PTOCarryOverPolicyViewModel {
    public var policy: PTOCarryOverPolicy = .init()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            policy = try await api.getPTOCarryOverPolicy()
        } catch {
            AppLog.ui.error("PTOCarryOverPolicy load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            policy = try await api.updatePTOCarryOverPolicy(policy)
        } catch {
            AppLog.ui.error("PTOCarryOverPolicy save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct PTOCarryOverPolicyView: View {
    @State private var vm: PTOCarryOverPolicyViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: PTOCarryOverPolicyViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Enable Carry-Over", isOn: $vm.policy.carryOverEnabled)
                    .accessibilityLabel("Enable PTO carry-over to next year")

                if vm.policy.carryOverEnabled {
                    Stepper(
                        "Max Days: \(vm.policy.maxCarryOverDays)",
                        value: $vm.policy.maxCarryOverDays,
                        in: 0...30
                    )
                    .accessibilityLabel("Maximum carry-over days: \(vm.policy.maxCarryOverDays)")
                }
            } header: {
                Text("Carry-Over")
            } footer: {
                Text(vm.policy.carryOverEnabled
                     ? "Employees may carry up to \(vm.policy.maxCarryOverDays) unused PTO days into the next year."
                     : "Unused PTO does not carry over. All remaining days expire at the end of the period."
                )
                .font(.brandLabelSmall())
            }

            Section {
                Stepper(
                    "Month: \(monthName(vm.policy.expiryMonth))",
                    value: $vm.policy.expiryMonth,
                    in: 1...12
                )
                .accessibilityLabel("Expiry month: \(monthName(vm.policy.expiryMonth))")

                Stepper(
                    "Day: \(vm.policy.expiryDay)",
                    value: $vm.policy.expiryDay,
                    in: 1...31
                )
                .accessibilityLabel("Expiry day: \(vm.policy.expiryDay)")
            } header: {
                Text("Expiry Date")
            } footer: {
                Text("Unused PTO expires on \(vm.policy.expiryDisplayString) each year. Employees see a warning banner 30 days before.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.bizarreError) }
            }
        }
        .navigationTitle("Carry-Over & Expiry")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(vm.isSaving ? "Saving…" : "Save") {
                    Task { await vm.save() }
                }
                .disabled(vm.isSaving)
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel("Save policy")
            }
        }
        .task { await vm.load() }
    }

    private func monthName(_ m: Int) -> String {
        let fmt = DateFormatter()
        guard m >= 1, m <= 12 else { return "\(m)" }
        return fmt.shortMonthSymbols[m - 1]
    }
}

// MARK: - PTOExpiryBanner

/// Shows "X days expire Dec 31" on employee PTO balance tiles.
public struct PTOExpiryBanner: View {
    public let expiringDays: Int
    public let expiryDateString: String

    public init(expiringDays: Int, expiryDateString: String) {
        self.expiringDays = expiringDays
        self.expiryDateString = expiryDateString
    }

    public var body: some View {
        if expiringDays > 0 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("\(expiringDays) day\(expiringDays == 1 ? "" : "s") expire \(expiryDateString)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(BrandSpacing.sm)
            .background(Color.bizarreOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(expiringDays) PTO day\(expiringDays == 1 ? "" : "s") expire on \(expiryDateString)")
        }
    }
}

// MARK: - APIClient extensions

extension APIClient {
    func getPTOCarryOverPolicy() async throws -> PTOCarryOverPolicy {
        try await get("/api/v1/settings/pto/carry-over", as: PTOCarryOverPolicy.self)
    }

    func updatePTOCarryOverPolicy(_ policy: PTOCarryOverPolicy) async throws -> PTOCarryOverPolicy {
        try await patch("/api/v1/settings/pto/carry-over", body: policy, as: PTOCarryOverPolicy.self)
    }
}
