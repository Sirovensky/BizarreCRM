import SwiftUI
import DesignSystem

// MARK: - TrainingModeEnterSheet

/// Confirmation + warning sheet presented before activating Training Mode.
///
/// Callers own the dismiss logic:
/// ```swift
/// .sheet(isPresented: $vm.showEnterSheet) {
///     TrainingModeEnterSheet(
///         onConfirm: { vm.confirmEnable() },
///         onCancel:  { vm.cancelEnable() }
///     )
/// }
/// ```
///
/// The sheet is single-purpose: show warnings, require explicit acknowledgement,
/// then call back. No state escapes through the view — the ViewModel handles
/// all persistence.
public struct TrainingModeEnterSheet: View {

    // MARK: - Callbacks

    let onConfirm: () -> Void
    let onCancel: () -> Void

    // MARK: - Local state

    @State private var consentChecked: Bool = false

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Init

    public init(
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            scrollContent
                .navigationTitle("Enable Training Mode")
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
                .toolbar { toolbarContent }
        }
        .presentationDetents(sheetDetents)
        .presentationDragIndicator(.visible)
        #if canImport(UIKit)
        .presentationCornerRadius(DesignTokens.Radius.xl)
        #endif
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                iconHeader
                warningList
                consentRow
                actionButtons
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Icon header

    private var iconHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.bizarreWarning.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.bizarreWarning)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Training Mode / Sandbox")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Safe practice environment")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: - Warning list

    private var warningList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("What to know before enabling:")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ForEach(Self.warningItems, id: \.icon) { item in
                warningRow(icon: item.icon, text: item.text)
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.bizarreWarning)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Consent toggle

    private var consentRow: some View {
        HStack(alignment: .center, spacing: BrandSpacing.sm) {
            Toggle(isOn: $consentChecked) {
                Text("I understand this is a sandbox. No data sent to production systems.")
                    .font(.footnote)
                    .foregroundStyle(.bizarreOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel("Acknowledge training mode is a sandbox")
            .accessibilityIdentifier("trainingMode.consent")
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                onConfirm()
                dismiss()
            } label: {
                Text("Enable Training Mode")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnOrange)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreWarning)
            .disabled(!consentChecked)
            .accessibilityLabel("Enable Training Mode")
            .accessibilityIdentifier("trainingMode.enableButton")

            Button {
                onCancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.brandLabelLarge())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlassClear)
            .accessibilityLabel("Cancel")
            .accessibilityIdentifier("trainingMode.cancelButton")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .accessibilityIdentifier("trainingMode.sheetCancel")
        }
    }

    // MARK: - Sheet detents (iPhone vs iPad)

    private var sheetDetents: Set<PresentationDetent> {
        // iPad can go smaller — content is compact; iPhone needs more room.
        hSizeClass == .regular
            ? [.medium]
            : [.large, .fraction(0.85)]
    }

    // MARK: - Static content

    private struct WarningItem {
        let icon: String
        let text: String
    }

    private static let warningItems: [WarningItem] = [
        .init(
            icon: "exclamationmark.triangle.fill",
            text: "All actions are sandboxed — sales, inventory changes, and messages are simulated and never reach production."
        ),
        .init(
            icon: "bell.slash.fill",
            text: "Push notifications are suppressed while Training Mode is active."
        ),
        .init(
            icon: "eye.fill",
            text: "A persistent banner will be displayed across the app while this mode is on."
        ),
        .init(
            icon: "arrow.clockwise",
            text: "Disable at any time from Settings → Training Mode."
        ),
    ]
}
