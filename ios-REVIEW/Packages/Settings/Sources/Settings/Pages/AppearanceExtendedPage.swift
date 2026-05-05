import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - §19.4 Appearance extended — glass intensity, sounds, haptics, icon

// MARK: - Models

public enum HapticIntensity: String, CaseIterable, Sendable, Identifiable {
    case subtle  = "subtle"
    case medium  = "medium"
    case strong  = "strong"
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

// MARK: - ViewModel extension (added settings on top of AppearanceViewModel)

@MainActor
@Observable
public final class AppearanceExtendedViewModel: Sendable {
    // §19.4 Glass intensity 0–100%; <30% → solid material (a11y alt)
    var glassIntensity: Double = 0.8

    // §19.4 Sounds
    var soundsEnabled: Bool = true
    var notificationSound: Bool = true
    var scanChime: Bool = true
    var successSound: Bool = true
    var errorSound: Bool = true

    // §19.4 Haptics
    var hapticsEnabled: Bool = true
    var hapticIntensity: HapticIntensity = .medium

    // §19.4 Reduce transparency
    var reduceTransparency: Bool = false

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        glassIntensity     = defaults.object(forKey: "appearance.glassIntensity") as? Double ?? 0.8
        soundsEnabled      = defaults.object(forKey: "appearance.soundsEnabled") as? Bool ?? true
        notificationSound  = defaults.object(forKey: "appearance.sound.notification") as? Bool ?? true
        scanChime          = defaults.object(forKey: "appearance.sound.scan") as? Bool ?? true
        successSound       = defaults.object(forKey: "appearance.sound.success") as? Bool ?? true
        errorSound         = defaults.object(forKey: "appearance.sound.error") as? Bool ?? true
        hapticsEnabled     = defaults.object(forKey: "appearance.hapticsEnabled") as? Bool ?? true
        hapticIntensity    = HapticIntensity(rawValue: defaults.string(forKey: "appearance.hapticIntensity") ?? "") ?? .medium
        reduceTransparency = defaults.bool(forKey: "appearance.reduceTransparency")
    }

    func save() {
        defaults.set(glassIntensity,     forKey: "appearance.glassIntensity")
        defaults.set(soundsEnabled,      forKey: "appearance.soundsEnabled")
        defaults.set(notificationSound,  forKey: "appearance.sound.notification")
        defaults.set(scanChime,          forKey: "appearance.sound.scan")
        defaults.set(successSound,       forKey: "appearance.sound.success")
        defaults.set(errorSound,         forKey: "appearance.sound.error")
        defaults.set(hapticsEnabled,     forKey: "appearance.hapticsEnabled")
        defaults.set(hapticIntensity.rawValue, forKey: "appearance.hapticIntensity")
        defaults.set(reduceTransparency, forKey: "appearance.reduceTransparency")
    }
}

// MARK: - View

/// §19.4 Glass intensity + sounds + haptics + reduce-transparency settings.
/// Designed as a sub-section to embed into `AppearancePage` (or navigated to from there).
public struct AppearanceExtendedPage: View {
    @State private var vm: AppearanceExtendedViewModel

    public init(defaults: UserDefaults = .standard) {
        _vm = State(wrappedValue: AppearanceExtendedViewModel(defaults: defaults))
    }

    public var body: some View {
        Form {
            // Glass intensity
            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    HStack {
                        Text("Glass intensity")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text("\(Int(vm.glassIntensity * 100))%")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.glassIntensity, in: 0...1, step: 0.05)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Glass intensity \(Int(vm.glassIntensity * 100)) percent")
                        .accessibilityIdentifier("appearance.glassIntensity")
                }
                Toggle("Reduce transparency", isOn: $vm.reduceTransparency)
                    .accessibilityIdentifier("appearance.reduceTransparency")
            } header: {
                Text("Glass & transparency")
            } footer: {
                Text("Below 30% glass falls back to solid material. Reduce transparency disables all glass effects.")
                    .font(.caption)
            }

            // Sounds
            Section {
                Toggle("Enable sounds", isOn: $vm.soundsEnabled)
                    .accessibilityIdentifier("appearance.soundsEnabled")
                if vm.soundsEnabled {
                    Toggle("Notification sound", isOn: $vm.notificationSound)
                        .accessibilityIdentifier("appearance.sound.notification")
                    Toggle("Scan chime", isOn: $vm.scanChime)
                        .accessibilityIdentifier("appearance.sound.scan")
                    Toggle("Success sound", isOn: $vm.successSound)
                        .accessibilityIdentifier("appearance.sound.success")
                    Toggle("Error sound", isOn: $vm.errorSound)
                        .accessibilityIdentifier("appearance.sound.error")
                }
            } header: {
                Text("Sounds")
            }

            // Haptics
            Section {
                Toggle("Enable haptic feedback", isOn: $vm.hapticsEnabled)
                    .accessibilityIdentifier("appearance.hapticsEnabled")
                if vm.hapticsEnabled {
                    Picker("Intensity", selection: $vm.hapticIntensity) {
                        ForEach(HapticIntensity.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Haptic intensity")
                    .accessibilityIdentifier("appearance.hapticIntensity")
                }
            } header: {
                Text("Haptics")
            } footer: {
                Text("Controls the physical feedback for interactions like swipes, confirmations, and alerts.")
                    .font(.caption)
            }
        }
        .navigationTitle("Appearance")
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") { vm.save() }
                    .accessibilityIdentifier("appearance.extendedApply")
            }
        }
        .onChange(of: vm.glassIntensity) { _, _ in vm.save() }
        .onChange(of: vm.reduceTransparency) { _, _ in vm.save() }
        .onChange(of: vm.hapticsEnabled) { _, _ in vm.save() }
        .onChange(of: vm.hapticIntensity) { _, _ in vm.save() }
    }
}
