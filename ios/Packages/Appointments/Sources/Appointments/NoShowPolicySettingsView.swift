#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §10 No-show deposit policy settings (Settings → Appointments → No-show policy)

@MainActor
@Observable
public final class NoShowPolicySettingsViewModel {
    public var threshold: Int = 2
    public var depositDollars: String = "50.00"
    public var resetAfterDays: Int? = 365
    public var enableReset: Bool = true

    public private(set) var isLoading: Bool = false
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var showSuccess: Bool = false

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let policy = try await api.noShowDepositPolicy()
            threshold      = policy.thresholdCount
            depositDollars = String(format: "%.2f", Double(policy.depositCents) / 100.0)
            resetAfterDays = policy.resetAfterDays
            enableReset    = policy.resetAfterDays != nil
        } catch {
            AppLog.ui.error("NoShowPolicy load: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let depositCents = Int((Double(depositDollars) ?? 50.0) * 100)
            let policy = NoShowDepositPolicy(
                thresholdCount: threshold,
                depositCents: depositCents,
                resetAfterDays: enableReset ? resetAfterDays : nil
            )
            try await api.updateNoShowPolicy(policy)
            showSuccess = true
            BrandHaptics.success()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSuccess = false
        } catch {
            AppLog.ui.error("NoShowPolicy save: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

public struct NoShowPolicySettingsView: View {
    @State private var vm: NoShowPolicySettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: NoShowPolicySettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            Section("No-show deposit policy") {
                Stepper("Trigger after \(vm.threshold) no-show(s)", value: $vm.threshold, in: 1...10)
                    .accessibilityLabel("No-show threshold: \(vm.threshold)")

                HStack {
                    Text("Deposit amount ($)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    TextField("50.00", text: $vm.depositDollars)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                        .font(.brandMono(size: 15))
                        .accessibilityLabel("Deposit amount in dollars")
                }

                Toggle("Reset record after N days", isOn: $vm.enableReset)
                    .accessibilityLabel("Reset no-show count after a period of time")

                if vm.enableReset {
                    Stepper(
                        "Reset after \(vm.resetAfterDays ?? 365) day(s)",
                        value: Binding(
                            get: { vm.resetAfterDays ?? 365 },
                            set: { vm.resetAfterDays = $0 }
                        ),
                        in: 30...730, step: 30
                    )
                    .accessibilityLabel("Reset after \(vm.resetAfterDays ?? 365) days")
                }
            }
            .listRowBackground(Color.bizarreSurface1)

            Section {
                Text("After \(vm.threshold) no-show(s), a $\(vm.depositDollars) deposit will be required to book the next appointment. Customer is notified at booking.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .listRowBackground(Color.bizarreSurface1)

            if let err = vm.errorMessage {
                Section {
                    Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreError)
                }
                .listRowBackground(Color.bizarreSurface1)
            }

            Section {
                Button {
                    Task { await vm.save() }
                } label: {
                    HStack {
                        Spacer()
                        if vm.isSaving {
                            ProgressView().tint(.white)
                        } else if vm.showSuccess {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                        } else {
                            Text("Save policy")
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                }
                .disabled(vm.isSaving)
                .listRowBackground(Color.bizarreOrange)
                .accessibilityLabel("Save no-show deposit policy")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("No-show Policy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }
}

// MARK: - Per-customer no-show badge

/// Shown on appointment create when customer has prior no-shows.
public struct CustomerNoShowBadge: View {
    let record: CustomerNoShowRecord

    public init(record: CustomerNoShowRecord) {
        self.record = record
    }

    public var body: some View {
        if record.noShowCount > 0 {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(record.depositRequired ? .bizarreError : .bizarreWarning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("\(record.noShowCount) no-show(s) on record")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if record.depositRequired {
                        Text("Deposit required for this booking.")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreError)
                    }
                }
            }
            .padding(BrandSpacing.sm)
            .background(
                record.depositRequired
                    ? Color.bizarreError.opacity(0.1)
                    : Color.bizarreWarning.opacity(0.1),
                in: RoundedRectangle(cornerRadius: BrandRadius.sm)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(record.noShowCount) no-show(s)"
                + (record.depositRequired ? ". Deposit required." : "")
            )
        }
    }
}

#endif
