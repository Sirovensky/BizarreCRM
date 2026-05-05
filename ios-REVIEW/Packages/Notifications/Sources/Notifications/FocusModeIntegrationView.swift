import SwiftUI
import DesignSystem

// MARK: - FocusModeIntegrationView

/// Read-only explainer for iOS Focus mode interaction.
/// SwiftUI cannot programmatically query Focus state, so this view documents
/// the system behavior and guides users to manage Focus directly in iOS Settings.
public struct FocusModeIntegrationView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                headerSection
                howItWorksSection
                limitationsSection
                openSettingsButton
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Focus Mode")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("iOS Focus Mode")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text("iOS Focus lets you limit interruptions by filtering which apps and people can send notifications.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("How it works with BizarreCRM")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            infoRow(
                icon: "bell.badge",
                text: "When a Focus is active, iOS decides which notifications pass through — not the app."
            )
            infoRow(
                icon: "exclamationmark.circle",
                text: "Critical events (Backup failed, Security alerts, Out of stock during sale, Payment declined) are marked Time Sensitive and break through most Focus modes."
            )
            infoRow(
                icon: "gearshape",
                text: "You can add BizarreCRM to your Focus allowlist in iOS Settings to receive all notifications during a Focus."
            )
        }
    }

    @ViewBuilder
    private var limitationsSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Limitations")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            infoRow(
                icon: "lock",
                text: "iOS does not allow apps to read the active Focus mode. BizarreCRM cannot automatically adjust behavior based on Focus."
            )
            infoRow(
                icon: "hand.raised",
                text: "Disabling all notifications in a strict Focus will also suppress Time Sensitive alerts unless the system entitlement is granted."
            )
        }
    }

    @ViewBuilder
    private var openSettingsButton: some View {
        Button {
            openFocusSettings()
        } label: {
            HStack {
                Image(systemName: "arrow.up.right.square")
                    .accessibilityHidden(true)
                Text("Open iOS Focus Settings")
            }
            .font(.brandLabelLarge())
            .foregroundStyle(.bizarreOrange)
        }
        .accessibilityLabel("Open iOS Focus Settings")
        .accessibilityHint("Opens the iOS Settings app to the Focus section")
    }

    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func openFocusSettings() {
        #if canImport(UIKit)
        // Deep-link to Focus settings page when available.
        if let url = URL(string: "App-Prefs:FOCUS"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        FocusModeIntegrationView()
    }
}
#endif
