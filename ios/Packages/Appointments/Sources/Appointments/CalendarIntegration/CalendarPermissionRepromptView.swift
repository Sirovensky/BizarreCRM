import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

// MARK: - CalendarPermissionRepromptView

/// Shown when the user has previously denied calendar access and we need to
/// explain — clearly and without alarm — why the app wants it and how to
/// re-enable it in Settings.
///
/// Trigger this view when `CalendarPermissionHelper.currentStatus()` returns
/// `.denied` and the user tries to enable calendar sync from
/// `CalendarSyncSettings` or the appointment detail "Add to Calendar" action.
///
/// Design rationale:
///  - Neutral, informative copy. No "We need" language. No guilt-tripping.
///  - Two CTAs: "Open Settings" (primary) and "Not Now" (secondary / dismiss).
///  - Presented as a sheet (.medium detent) so it doesn't feel modal-blocking.
///  - The view never calls `requestAccess()` itself — iOS only shows the system
///    prompt once. Re-enabling must go via Settings.
public struct CalendarPermissionRepromptView: View {

    @Environment(\.dismiss) private var dismiss

    /// Optional closure called after the user taps "Open Settings".
    /// Defaults to opening `UIApplication.openSettingsURLString`.
    public var onOpenSettings: (() -> Void)?

    public init(onOpenSettings: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    iconArea
                    Spacer().frame(height: BrandSpacing.lg)
                    textArea
                    Spacer().frame(height: BrandSpacing.xl)
                    actionButtons
                    Spacer()
                }
                .padding(.horizontal, BrandSpacing.xl)
            }
            .navigationTitle("Calendar Access")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .accessibilityLabel("Dismiss, do not enable calendar access")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var iconArea: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreOrange.opacity(0.12))
                .frame(width: 88, height: 88)
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.bizarreOrange)
        }
        .accessibilityHidden(true)
    }

    private var textArea: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Add appointments to your calendar")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(
                "BizarreCRM can mirror your scheduled appointments into the Calendar app " +
                "so they appear alongside your other events. Calendar access was previously " +
                "turned off — you can re-enable it in iPhone Settings."
            )
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            // Step-by-step path hint so the user doesn't have to hunt.
            stepHint
        }
    }

    /// Compact "Settings > Privacy & Security > Calendars > BizarreCRM" path label.
    private var stepHint: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "info.circle")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Settings › Privacy & Security › Calendars › BizarreCRM")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, BrandSpacing.xs)
        .accessibilityLabel(
            "To enable: open Settings, then Privacy and Security, then Calendars, then BizarreCRM."
        )
    }

    private var actionButtons: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                openSettings()
                dismiss()
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .controlSize(.large)
            .accessibilityLabel("Open iPhone Settings to enable calendar access")

            Button("Not Now") {
                dismiss()
            }
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .accessibilityLabel("Dismiss, keep calendar access off for now")
        }
    }

    // MARK: - Helpers

    private func openSettings() {
        if let handler = onOpenSettings {
            handler()
            return
        }
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
