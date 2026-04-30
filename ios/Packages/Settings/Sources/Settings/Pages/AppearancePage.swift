import SwiftUI
import Observation
import Core
import DesignSystem
// POSThemeOverride is defined in DesignSystem (POSThemeModifier.swift)
#if canImport(UIKit)
import UIKit
#endif

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
    case orange = "orange"

    public var displayName: String {
        switch self {
        case .orange: return "Orange"
        }
    }

    public var color: Color {
        switch self {
        case .orange: return .bizarrePrimary
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
    /// §19.4 Glass intensity 0–100 (100 = full glass; <30 → solid material).
    var glassIntensity: Double = 100.0
    /// §19.4 Reduce transparency — overrides system for users who find glass heavy.
    var reduceTransparency: Bool = false
    /// §19.4 Sounds master toggle.
    var soundsEnabled: Bool = true
    /// §19.4 Haptics master toggle.
    var hapticsEnabled: Bool = true
    /// §wave-5 — persists to `@AppStorage("pos.theme.override")` so
    /// `POSThemeModifier` in `RootView` resolves the right token set.
    var posThemeOverride: POSThemeOverride = .system

    private let defaults: UserDefaults

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
        glassIntensity = defaults.object(forKey: "appearance.glassIntensity") as? Double ?? 100.0
        reduceTransparency = defaults.bool(forKey: "appearance.reduceTransparency")
        soundsEnabled = defaults.object(forKey: "appearance.soundsEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "appearance.hapticsEnabled") as? Bool ?? true
        posThemeOverride = POSThemeOverride(rawValue: defaults.string(forKey: "pos.theme.override") ?? "") ?? .system
    }

    func save() {
        defaults.set(theme.rawValue, forKey: "appearance.theme")
        defaults.set(accent.rawValue, forKey: "appearance.accent")
        defaults.set(isCompact, forKey: "appearance.compact")
        defaults.set(fontScale, forKey: "appearance.fontScale")
        defaults.set(reduceMotion, forKey: "appearance.reduceMotion")
        defaults.set(glassIntensity, forKey: "appearance.glassIntensity")
        defaults.set(reduceTransparency, forKey: "appearance.reduceTransparency")
        defaults.set(soundsEnabled, forKey: "appearance.soundsEnabled")
        defaults.set(hapticsEnabled, forKey: "appearance.hapticsEnabled")
        defaults.set(posThemeOverride.rawValue, forKey: "pos.theme.override")

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
                // §19.4 — live preview thumbnails one-tap theme selection
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        ThemePreviewTile(theme: t, isSelected: vm.theme == t) {
                            vm.theme = t
                            vm.save()
                        }
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityElement(children: .contain)
            }

            // Accent-color section is hidden while the palette only ships a
            // single brand colour (cream/orange via `bizarrePrimary`). A
            // single-circle picker would be meaningless UI. Re-enable when a
            // second accent ships.
            if AccentColor.allCases.count > 1 {
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
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    HStack {
                        Text("Glass intensity")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Text("\(Int(vm.glassIntensity))%")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .monospacedDigit()
                    }
                    Slider(value: $vm.glassIntensity, in: 0...100, step: 5)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Glass intensity \(Int(vm.glassIntensity)) percent")
                        .accessibilityIdentifier("appearance.glassIntensity")
                }
                Toggle("Reduce transparency", isOn: $vm.reduceTransparency)
                    .accessibilityIdentifier("appearance.reduceTransparency")
            } header: {
                Text("Glass")
            } footer: {
                Text("Below 30% intensity, glass elements fall back to solid materials. Reduce transparency removes glass blur entirely.")
            }

            Section("Motion") {
                Toggle("Reduce motion (override system)", isOn: $vm.reduceMotion)
                    .accessibilityIdentifier("appearance.reduceMotion")
            }

            Section("Audio & haptics") {
                Toggle("Sounds", isOn: $vm.soundsEnabled)
                    .accessibilityIdentifier("appearance.sounds")
                Toggle("Haptics", isOn: $vm.hapticsEnabled)
                    .accessibilityIdentifier("appearance.haptics")
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
            // §19.4 Alternate app icon picker
            AppIconPickerSection()
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
    }
}

// MARK: - §19.4 Theme preview tile

/// Small thumbnail that previews light/dark/system appearance for a theme option.
/// Tapping selects that theme immediately (no separate Save needed — matches
/// the existing `.onChange(of: vm.theme)` auto-save at the page level).
private struct ThemePreviewTile: View {
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    /// Simulated surface colours for the mini UI mockup inside each tile.
    private var bgColor: Color {
        switch theme {
        case .system: return Color(.systemBackground)
        case .light:  return .white
        case .dark:   return Color(white: 0.13)
        }
    }

    private var textColor: Color {
        switch theme {
        case .light:  return Color(white: 0.1)
        case .dark:   return Color(white: 0.9)
        case .system: return Color(.label)
        }
    }

    private var barColor: Color {
        switch theme {
        case .light:  return Color(white: 0.85)
        case .dark:   return Color(white: 0.22)
        case .system: return Color(.secondarySystemBackground)
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BrandSpacing.xs) {
                // Mini mockup
                RoundedRectangle(cornerRadius: 10)
                    .fill(bgColor)
                    .frame(width: 80, height: 56)
                    .overlay {
                        VStack(spacing: 4) {
                            // Fake nav bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(barColor)
                                .frame(height: 10)
                                .padding(.horizontal, 6)
                                .padding(.top, 4)
                            // Fake content rows
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(textColor.opacity(0.15))
                                    .frame(height: 6)
                                    .padding(.horizontal, 10)
                            }
                            // Fake accent strip
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bizarreOrange.opacity(0.7))
                                .frame(height: 6)
                                .padding(.horizontal, 10)
                            Spacer()
                        }
                    }
                    .overlay {
                        if theme == .system {
                            // Half-and-half overlay for "system" tile
                            GeometryReader { geo in
                                Path { p in
                                    p.move(to: CGPoint(x: geo.size.width, y: 0))
                                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                                    p.closeSubpath()
                                }
                                .fill(Color(white: 0.13).opacity(0.45))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isSelected ? Color.bizarreOrange : Color.clear,
                                lineWidth: 2
                            )
                    }

                Text(theme.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(height: 14)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("appearance.themePreview.\(theme.rawValue)")
    }
}

// MARK: - §19.4 App icon picker

/// Shows alternate app icons via `UIApplication.setAlternateIconName`.
/// Falls back gracefully on macOS / simulator (where alt icons are unavailable).
private struct AppIconPickerSection: View {
    @State private var activeIcon: String? = nil
    @State private var errorMessage: String?

    /// Available alternate icon names matching the CFBundleAlternateIcons entries
    /// that will be declared in Info.plist. For now using SF Symbol names as
    /// visual stand-ins until PNG icon sets are prepared (per §19.4 note).
    private let iconOptions: [(name: String?, label: String, systemImage: String)] = [
        (nil,       "Default",    "app.badge"),
        ("Dark",    "Dark",       "app.badge.fill"),
        ("Minimal", "Minimal",    "square"),
    ]

    var body: some View {
        Section {
            ForEach(iconOptions, id: \.label) { option in
                iconRow(option)
            }
            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        } header: {
            Text("App Icon")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)
        } footer: {
            Text("Alt icon variants will be available in a future build once icon assets ship.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .task { fetchCurrentIcon() }
    }

    @ViewBuilder
    private func iconRow(_ option: (name: String?, label: String, systemImage: String)) -> some View {
        Button {
            setIcon(option.name)
        } label: {
            HStack(spacing: BrandSpacing.md) {
                // SF symbol as placeholder until PNG icon sets ship.
                RoundedRectangle(cornerRadius: 10)
                    .fill(option.name == nil ? Color.bizarreOrange : Color.bizarreSurface2)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(option.name == nil ? Color.white : Color.bizarreOnSurface)
                    }
                    .accessibilityHidden(true)

                Text(option.label)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer()

                if activeIcon == option.name {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(option.label) icon\(activeIcon == option.name ? ", selected" : "")")
        .accessibilityIdentifier("appearance.icon.\(option.label.lowercased())")
    }

    private func fetchCurrentIcon() {
        #if canImport(UIKit)
        activeIcon = UIApplication.shared.alternateIconName
        #endif
    }

    private func setIcon(_ name: String?) {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Alternate icons are not supported on this device."
            return
        }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                errorMessage = error.localizedDescription
                AppLog.ui.error("setAlternateIconName failed: \(error.localizedDescription, privacy: .public)")
            } else {
                activeIcon = name
                errorMessage = nil
            }
        }
        #endif
    }
}
