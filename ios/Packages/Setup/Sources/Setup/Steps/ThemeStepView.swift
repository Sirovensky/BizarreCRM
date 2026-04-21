import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - ViewModel

@MainActor
@Observable
final class ThemeStepViewModel {

    // MARK: State

    var selectedTheme: AppThemeChoice = .system

    // MARK: Persistence

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Pre-populate from existing appearance setting if present
        if let raw = defaults.string(forKey: "appearance.theme"),
           let existing = AppThemeChoice(rawValue: raw) {
            selectedTheme = existing
        }
    }

    var isNextEnabled: Bool {
        Step12aValidator.isNextEnabled(theme: selectedTheme)
    }

    /// Persists via the same key used by AppearanceViewModel in the Settings package.
    func persistTheme() {
        defaults.set(selectedTheme.rawValue, forKey: "appearance.theme")
        #if canImport(UIKit)
        applyTheme()
        #endif
    }

    #if canImport(UIKit)
    private func applyTheme() {
        let style: UIUserInterfaceStyle
        switch selectedTheme {
        case .system: style = .unspecified
        case .dark:   style = .dark
        case .light:  style = .light
        }
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

// MARK: - View  (§36.2 Step 12a — Theme)

@MainActor
public struct ThemeStepView: View {
    let onValidityChanged: (Bool) -> Void
    let onNext: (AppThemeChoice) -> Void

    @State private var vm: ThemeStepViewModel

    public init(
        onValidityChanged: @escaping (Bool) -> Void,
        onNext: @escaping (AppThemeChoice) -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.onValidityChanged = onValidityChanged
        self.onNext = onNext
        _vm = State(wrappedValue: ThemeStepViewModel(defaults: defaults))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                header
                themeOptions
                previewTile
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { onValidityChanged(vm.isNextEnabled) }
        .onChange(of: vm.selectedTheme) { _, _ in
            onValidityChanged(vm.isNextEnabled)
            vm.persistTheme()
        }
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Choose Theme")
                .font(.brandHeadlineMedium())
                .foregroundStyle(Color.bizarreOnSurface)
                .padding(.top, BrandSpacing.lg)
                .accessibilityAddTraits(.isHeader)

            Text("Pick how the app looks. You can change this any time in Settings → Appearance.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var themeOptions: some View {
        VStack(spacing: BrandSpacing.sm) {
            ForEach(AppThemeChoice.allCases, id: \.self) { choice in
                themeRow(choice)
            }
        }
    }

    private func themeRow(_ choice: AppThemeChoice) -> some View {
        let isSelected = vm.selectedTheme == choice
        return Button {
            vm.selectedTheme = choice
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: themeIcon(choice))
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.bizarreOnSurface)

                    if choice == .system {
                        Text("Follows your device setting")
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(
                isSelected ? Color.bizarreOrange.opacity(0.1) : Color.bizarreSurface1.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.bizarreOrange.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.displayName)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var previewTile: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Preview")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            // Sample Dashboard tile styled for the selected theme
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Tickets")
                        .font(.brandLabelLarge())
                        .foregroundStyle(themePreviewForeground)
                    Text("12 active repairs")
                        .font(.brandBodyMedium())
                        .foregroundStyle(themePreviewMuted)
                }

                Spacer()

                Text("View all")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOrange)
            }
            .padding(BrandSpacing.md)
            .background(themePreviewBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview: Open Tickets dashboard tile in \(vm.selectedTheme.displayName) theme")
        }
    }

    // MARK: Theme preview colors

    private var themePreviewBackground: Color {
        switch vm.selectedTheme {
        case .system: return Color.bizarreSurface1.opacity(0.7)
        case .dark:   return Color(white: 0.12)
        case .light:  return Color(white: 0.96)
        }
    }

    private var themePreviewForeground: Color {
        switch vm.selectedTheme {
        case .system: return Color.bizarreOnSurface
        case .dark:   return Color.white
        case .light:  return Color.black
        }
    }

    private var themePreviewMuted: Color {
        switch vm.selectedTheme {
        case .system: return Color.bizarreOnSurfaceMuted
        case .dark:   return Color(white: 0.6)
        case .light:  return Color(white: 0.4)
        }
    }

    private func themeIcon(_ choice: AppThemeChoice) -> String {
        switch choice {
        case .system: return "circle.lefthalf.filled"
        case .dark:   return "moon.fill"
        case .light:  return "sun.max.fill"
        }
    }
}
