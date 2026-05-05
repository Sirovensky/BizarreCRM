import SwiftUI
import Observation
import Core
import DesignSystem
import Persistence

#if canImport(UIKit)
import UIKit
#endif

// MARK: - §19.2 Security settings page
//
// Auto-lock timeout, biometric app-lock on cold launch, privacy snapshot.
// §19.2 PIN enrollment: 6-digit PIN for quick re-auth (locally enforced).

// MARK: - Auto-lock timeout

public enum AutoLockTimeout: String, CaseIterable, Sendable, Identifiable {
    case immediately  = "immediately"
    case oneMinute    = "1min"
    case fiveMinutes  = "5min"
    case fifteenMinutes = "15min"
    case never        = "never"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .immediately:    return "Immediately"
        case .oneMinute:      return "1 minute"
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .never:          return "Never"
        }
    }

    /// Duration in seconds; nil = never auto-lock.
    public var seconds: TimeInterval? {
        switch self {
        case .immediately:    return 0
        case .oneMinute:      return 60
        case .fiveMinutes:    return 300
        case .fifteenMinutes: return 900
        case .never:          return nil
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SecuritySettingsViewModel {
    // §19.2 Auto-lock
    public var autoLockTimeout: AutoLockTimeout = .fiveMinutes

    // §19.2 App lock with biometric on cold launch
    public var biometricAppLockEnabled: Bool = false

    // §19.2 Privacy snapshot — blur app in App Switcher
    public var privacySnapshotEnabled: Bool = false

    private let defaults: UserDefaults

    private static let autoLockKey       = "security.autoLock"
    private static let biometricLockKey  = "security.biometricLock"
    private static let privacySnapKey    = "security.privacySnapshot"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        autoLockTimeout = AutoLockTimeout(rawValue: defaults.string(forKey: Self.autoLockKey) ?? "") ?? .fiveMinutes
        biometricAppLockEnabled = defaults.bool(forKey: Self.biometricLockKey)
        privacySnapshotEnabled  = defaults.bool(forKey: Self.privacySnapKey)
    }

    public func save() {
        defaults.set(autoLockTimeout.rawValue, forKey: Self.autoLockKey)
        defaults.set(biometricAppLockEnabled,  forKey: Self.biometricLockKey)
        defaults.set(privacySnapshotEnabled,   forKey: Self.privacySnapKey)
        applyPrivacySnapshot()
    }

    /// Apply or remove the privacy snapshot window-level protection.
    /// On iOS 13+ we use `UIWindow.isHidden = false` with a secure field
    /// underneath; the canonical approach is to present a blur overlay
    /// when `UIApplication.willResignActiveNotification` fires.
    public func applyPrivacySnapshot() {
        // The actual blur-on-background logic is in App/AppServices.swift
        // (Agent 10 territory — we just publish the preference here so that
        //  layer can read it from UserDefaults).
        AppLog.ui.debug("SecuritySettingsViewModel: privacySnapshot=\(self.privacySnapshotEnabled, privacy: .public)")
    }

    /// Called from AppDelegate when the app moves to background.
    /// Returns `true` if the caller should apply a blur snapshot.
    public static func shouldApplySnapshot() -> Bool {
        UserDefaults.standard.bool(forKey: privacySnapKey)
    }

    /// Called from AppDelegate at cold launch to determine if biometric gate needed.
    public static func shouldGateOnBiometric() -> Bool {
        UserDefaults.standard.bool(forKey: biometricLockKey)
    }

    /// Returns the effective auto-lock duration stored in UserDefaults.
    public static func autoLockDuration() -> AutoLockTimeout {
        AutoLockTimeout(rawValue: UserDefaults.standard.string(forKey: autoLockKey) ?? "") ?? .fiveMinutes
    }
}

// MARK: - View

public struct SecuritySettingsPage: View {
    @State private var vm: SecuritySettingsViewModel
    @State private var showPINSetup: Bool = false
    @State private var pinSheetMode: PINSetupViewModel.Mode = .set
    @State private var hasPIN: Bool = PINStore.shared.isEnrolled

    public init(defaults: UserDefaults = .standard) {
        _vm = State(initialValue: SecuritySettingsViewModel(defaults: defaults))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Form {
                pinSection
                autoLockSection
                biometricSection
                privacySection
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Security")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet(mode: pinSheetMode) {
                hasPIN = PINStore.shared.isEnrolled
                showPINSetup = false
            }
        }
    }

    // MARK: - §19.2 PIN

    @ViewBuilder
    private var pinSection: some View {
        Section {
            if hasPIN {
                Button {
                    pinSheetMode = .change
                    showPINSetup = true
                } label: {
                    HStack(spacing: BrandSpacing.md) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 18))
                            .foregroundStyle(.bizarreOrange)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Change PIN")
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Update your 6-digit quick-access PIN.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("security.changePIN")

                Button(role: .destructive) {
                    pinSheetMode = .change   // uses currentEntry verification before clear
                    showPINSetup = true
                } label: {
                    HStack(spacing: BrandSpacing.md) {
                        Image(systemName: "lock.slash")
                            .font(.system(size: 18))
                            .foregroundStyle(.bizarreError)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text("Remove PIN")
                            .font(.brandBodyLarge())
                    }
                }
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("security.removePIN")
            } else {
                Button {
                    pinSheetMode = .set
                    showPINSetup = true
                } label: {
                    HStack(spacing: BrandSpacing.md) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.bizarreOrange)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set up PIN")
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Add a 6-digit PIN for quick re-authentication.")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("security.setPIN")
            }
        } header: {
            Text("Quick-Access PIN")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("A 6-digit PIN lets staff re-authenticate quickly without biometrics. Stored locally on this device.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Auto-lock

    @ViewBuilder
    private var autoLockSection: some View {
        Section {
            Picker("Auto-lock", selection: $vm.autoLockTimeout) {
                ForEach(AutoLockTimeout.allCases) { timeout in
                    Text(timeout.displayName).tag(timeout)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: vm.autoLockTimeout) { _, _ in vm.save() }
            .accessibilityLabel("Auto-lock timeout")
            .accessibilityIdentifier("security.autoLock")
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Auto-Lock")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("The app will lock and require re-authentication after the selected period of inactivity.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Biometric app lock on cold launch

    @ViewBuilder
    private var biometricSection: some View {
        Section {
            Toggle(isOn: $vm.biometricAppLockEnabled) {
                HStack(spacing: BrandSpacing.md) {
                    Image(systemName: "faceid")
                        .font(.system(size: 18))
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Require biometric on open")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Face ID / Touch ID required each time you open the app from background.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .tint(.bizarreOrange)
            .onChange(of: vm.biometricAppLockEnabled) { _, _ in vm.save() }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Require biometric on open, \(vm.biometricAppLockEnabled ? "on" : "off")")
            .accessibilityIdentifier("security.biometricLock")
        } header: {
            Text("App Lock")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Privacy snapshot

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Toggle(isOn: $vm.privacySnapshotEnabled) {
                HStack(spacing: BrandSpacing.md) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide app in App Switcher")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("Blurs the app preview in the iOS App Switcher to protect customer data.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
            .tint(.bizarreOrange)
            .onChange(of: vm.privacySnapshotEnabled) { _, _ in vm.save() }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Hide app in App Switcher, \(vm.privacySnapshotEnabled ? "on" : "off")")
            .accessibilityIdentifier("security.privacySnapshot")
        } header: {
            Text("Privacy")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("This setting applies when you press the home button or switch apps.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        SecuritySettingsPage()
    }
}
#endif
