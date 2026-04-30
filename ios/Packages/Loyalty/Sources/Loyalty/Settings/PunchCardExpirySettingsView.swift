#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Networking

// §38.5 — Optional punch expiry 12 months after last activity, and tenant
// config for whether punch cards are shared across locations vs per-location.

// MARK: - PunchCardExpiryPolicy

/// Tenant-level punch card expiry policy.
public struct PunchCardExpiryPolicy: Codable, Sendable, Equatable {
    /// Whether punches expire after inactivity. Default false.
    public var expiryEnabled: Bool
    /// Months of inactivity before punches expire. Default 12.
    public var inactivityMonths: Int
    /// Whether punch cards are shared across all tenant locations (true)
    /// or isolated per location (false). Default true.
    public var sharedAcrossLocations: Bool

    public init(
        expiryEnabled: Bool = false,
        inactivityMonths: Int = 12,
        sharedAcrossLocations: Bool = true
    ) {
        self.expiryEnabled = expiryEnabled
        self.inactivityMonths = inactivityMonths
        self.sharedAcrossLocations = sharedAcrossLocations
    }
}

// MARK: - PunchCardExpirySettingsViewModel

@Observable
@MainActor
public final class PunchCardExpirySettingsViewModel {
    public var policy: PunchCardExpiryPolicy = .init()
    public var isLoading = false
    public var isSaving = false
    public var errorMessage: String?
    public var didSave = false

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let dto = try await api.getPunchCardExpiryPolicy()
            policy = PunchCardExpiryPolicy(
                expiryEnabled: dto.expiryEnabled,
                inactivityMonths: dto.inactivityMonths,
                sharedAcrossLocations: dto.sharedAcrossLocations
            )
        } catch {
            // Non-fatal: use defaults if server returns 404 (feature not yet deployed).
            policy = PunchCardExpiryPolicy()
        }
        isLoading = false
    }

    public func save() async {
        isSaving = true
        errorMessage = nil
        do {
            let dto = PunchCardExpiryPolicyDTO(
                expiryEnabled: policy.expiryEnabled,
                inactivityMonths: policy.inactivityMonths,
                sharedAcrossLocations: policy.sharedAcrossLocations
            )
            let savedDTO = try await api.savePunchCardExpiryPolicy(dto)
            policy = PunchCardExpiryPolicy(
                expiryEnabled: savedDTO.expiryEnabled,
                inactivityMonths: savedDTO.inactivityMonths,
                sharedAcrossLocations: savedDTO.sharedAcrossLocations
            )
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - PunchCardExpirySettingsView

/// Admin settings screen for punch card expiry + location sharing.
/// §38.5 — "Optional punch expiry 12mo after last activity" +
///          "Tenant config: cards shared across locations vs per-location".
public struct PunchCardExpirySettingsView: View {
    @State private var vm: PunchCardExpirySettingsViewModel

    public init(api: APIClient) {
        _vm = State(initialValue: PunchCardExpirySettingsViewModel(api: api))
    }

    public var body: some View {
        Form {
            // §38.5 — Expiry
            Section {
                Toggle("Enable punch expiry", isOn: $vm.policy.expiryEnabled)
                    .accessibilityLabel("Enable punch card expiry after inactivity")

                if vm.policy.expiryEnabled {
                    Stepper(
                        "Expire after \(vm.policy.inactivityMonths) month\(vm.policy.inactivityMonths == 1 ? "" : "s") of inactivity",
                        value: $vm.policy.inactivityMonths,
                        in: 1...24
                    )
                    .accessibilityLabel("Months of inactivity before punch cards expire, currently \(vm.policy.inactivityMonths)")
                }
            } header: {
                Text("Punch Expiry")
            } footer: {
                if vm.policy.expiryEnabled {
                    Text("Customers who haven't visited in \(vm.policy.inactivityMonths) months will have their punch counts reset. They are notified before expiry via their preferred channel.")
                        .font(.brandLabelSmall())
                } else {
                    Text("Punch card counts never expire. Customers retain progress indefinitely.")
                        .font(.brandLabelSmall())
                }
            }

            // §38.5 — Location sharing
            Section {
                Toggle("Shared across locations", isOn: $vm.policy.sharedAcrossLocations)
                    .accessibilityLabel("Punch cards shared across all tenant locations")
            } header: {
                Text("Multi-Location")
            } footer: {
                Text(vm.policy.sharedAcrossLocations
                    ? "Customers accumulate punches at any location. The card is shared tenant-wide."
                    : "Each location tracks its own punch cards independently.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }

            Section {
                Button {
                    Task { await vm.save() }
                } label: {
                    if vm.isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save Policy").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .disabled(vm.isSaving || vm.isLoading)
                .accessibilityLabel(vm.isSaving ? "Saving" : "Save punch card expiry policy")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .navigationTitle("Punch Card Settings")
        .task { await vm.load() }
        .onChange(of: vm.didSave) { _, saved in
            if saved {
                // Parent can dismiss or show toast; no automatic dismiss.
            }
        }
    }
}
#endif
