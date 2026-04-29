import SwiftUI
import Observation
import Core
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif
// POSThemeOverride is defined in DesignSystem (POSThemeModifier.swift)

// MARK: - Models

public enum AppTheme: String, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    #if canImport(UIKit)
    public var colorScheme: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        }
    }
    #endif
}

public enum AccentColor: String, CaseIterable, Sendable {
    case orange  = "orange"
    case teal    = "teal"
    case magenta = "magenta"

    public var displayName: String {
        switch self {
        case .orange:  return "Orange"
        case .teal:    return "Teal"
        case .magenta: return "Magenta"
        }
    }

    public var color: Color {
        switch self {
        case .orange:  return .bizarreOrange
        case .teal:    return .bizarreTeal
        case .magenta: return .bizarreMagenta
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class AppearanceViewModel: Sendable {

    var theme: AppTheme = .system
    var accent: AccentColor = .orange
    var isCompact: Bool = false
    var fontScale: Double = 1.0
    var reduceMotion: Bool = false
    /// §19.4 — overrides system "Reduce Transparency" accessibility setting for this app only.
    var reduceTransparency: Bool = false
    /// §19.4 — persists to `@AppStorage("pos.theme.override")` so
    /// `POSThemeModifier` in `RootView` resolves the right token set.
    var posThemeOverride: POSThemeOverride = .system

    private let defaults: UserDefaults
    /// §19.4 Sounds + Haptics — backed by HapticsSettings (DesignSystem).
    var soundsEnabled: Bool = true
    var hapticsEnabled: Bool = true

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func load() {
        theme = AppTheme(rawValue: defaults.string(forKey: "appearance.theme") ?? "") ?? .system
        accent = AccentColor(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .orange
        isCompact = defaults.bool(forKey: "appearance.compact")
        fontScale = defaults.object(forKey: "appearance.fontScale") as? Double ?? 1.0
        reduceMotion = defaults.bool(forKey: "appearance.reduceMotion")
        reduceTransparency = defaults.bool(forKey: "appearance.reduceTransparency")
        posThemeOverride = POSThemeOverride(rawValue: defaults.string(forKey: "pos.theme.override") ?? "") ?? .system
        soundsEnabled = HapticsSettings.shared.soundsEnabled
        hapticsEnabled = HapticsSettings.shared.hapticsEnabled
    }

    func save() {
        defaults.set(theme.rawValue, forKey: "appearance.theme")
        defaults.set(accent.rawValue, forKey: "appearance.accent")
        defaults.set(isCompact, forKey: "appearance.compact")
        defaults.set(fontScale, forKey: "appearance.fontScale")
        defaults.set(reduceMotion, forKey: "appearance.reduceMotion")
        defaults.set(reduceTransparency, forKey: "appearance.reduceTransparency")
        defaults.set(posThemeOverride.rawValue, forKey: "pos.theme.override")
        HapticsSettings.shared.soundsEnabled = soundsEnabled
        HapticsSettings.shared.hapticsEnabled = hapticsEnabled

        #if canImport(UIKit)
        applyTheme()
        #endif
    }

    #if canImport(UIKit)
    private func applyTheme() {
        let style = theme.colorScheme
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
    #endif
}

// MARK: - View

public struct AppearancePage: View {
    @State private var vm: AppearanceViewModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(defaults: UserDefaults = .standard) {
        _vm = State(initialValue: AppearanceViewModel(defaults: defaults))
    }

    public var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $vm.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("App theme")
                .accessibilityIdentifier("appearance.theme")
            }

            Section("Accent color") {
                HStack(spacing: BrandSpacing.base) {
                    ForEach(AccentColor.allCases, id: \.self) { color in
                        Button {
                            vm.accent = color
                            vm.save()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 36, height: 36)
                                if vm.accent == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .accessibilityLabel("\(color.displayName) accent\(vm.accent == color ? ", selected" : "")")
                        .accessibilityIdentifier("appearance.accent.\(color.rawValue)")
                    }
                    Spacer()
                }
                .padding(.vertical, BrandSpacing.xxs)
            }

            Section("Density") {
                Toggle("Compact rows", isOn: $vm.isCompact)
                    .accessibilityIdentifier("appearance.compact")
            }

            Section {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    HStack {
                        Text("Font scale")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text(String(format: "%.0f%%", vm.fontScale * 100))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.fontScale, in: 0.8...1.4, step: 0.1)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Font scale \(Int(vm.fontScale * 100)) percent")
                        .accessibilityIdentifier("appearance.fontScale")
                }
            } header: {
                Text("Font size")
            }

            Section {
                Toggle("Reduce motion (override system)", isOn: $vm.reduceMotion)
                    .accessibilityIdentifier("appearance.reduceMotion")
                Toggle("Reduce transparency (override system)", isOn: $vm.reduceTransparency)
                    .accessibilityIdentifier("appearance.reduceTransparency")
            } header: {
                Text("Motion & Accessibility")
            } footer: {
                Text("These override your device's Accessibility settings for Bizarre CRM only. Reducing transparency uses solid backgrounds instead of glass materials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("App sounds", isOn: $vm.soundsEnabled)
                    .accessibilityLabel("App sounds master toggle")
                    .accessibilityIdentifier("appearance.soundsEnabled")
                Toggle("Haptics", isOn: $vm.hapticsEnabled)
                    .accessibilityLabel("Haptics master toggle")
                    .accessibilityIdentifier("appearance.hapticsEnabled")
            } header: {
                Text("Sounds & Haptics")
            } footer: {
                Text("Controls in-app sounds (scan chime, success/error) and haptic feedback. Your device's system sounds and Siri are unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // §wave-5 — POS-specific theme override. Stored in
            // `@AppStorage("pos.theme.override")` and read by
            // `POSThemeModifier` which is applied at the authenticated
            // shell level in `RootView`.
            Section {
                Picker("POS theme", selection: $vm.posThemeOverride) {
                    Text("System").tag(POSThemeOverride.system)
                    Text("Light").tag(POSThemeOverride.light)
                    Text("Dark").tag(POSThemeOverride.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("POS theme override")
                .accessibilityIdentifier("appearance.posTheme")
            } header: {
                Text("Point of Sale")
            } footer: {
                Text("Overrides the device appearance for the POS screen only. \"System\" follows your device setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .accessibilityIdentifier("appearance.apply")
            }
        }
        .onChange(of: vm.theme) { _, _ in vm.save() }
        .onChange(of: vm.posThemeOverride) { _, _ in vm.save() }
        .onChange(of: vm.reduceTransparency) { _, _ in vm.save() }
        .onChange(of: vm.soundsEnabled) { _, _ in vm.save() }
        .onChange(of: vm.hapticsEnabled) { _, _ in vm.save() }
    }
}
