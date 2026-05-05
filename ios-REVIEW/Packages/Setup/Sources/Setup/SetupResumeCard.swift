#if canImport(UIKit)
import SwiftUI
import Core

// MARK: - SetupResumeCard
//
// §36.3 — "Continue setup" card shown on Dashboard when the wizard was deferred
// mid-flow. Shows progress fraction and lets the user re-enter the wizard.
//
// The card receives its Notification from SetupWizardViewModel.deferWizard() via
// `.setupStatusDeferred`. It can also be driven directly with `completedSteps`.
//
// Integration:
//   SetupResumeCard(completedSteps: 4, totalSteps: 13) {
//       // present wizard
//   }

public struct SetupResumeCard: View {
    public let completedSteps: Int
    public let totalSteps: Int
    public let onResume: () -> Void

    public init(completedSteps: Int, totalSteps: Int = 13, onResume: @escaping () -> Void) {
        self.completedSteps = completedSteps
        self.totalSteps = totalSteps
        self.onResume = onResume
    }

    private var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(completedSteps) / Double(totalSteps)
    }

    public var body: some View {
        Button(action: onResume) {
            HStack(spacing: 16) {
                // Circular progress ring
                ZStack {
                    Circle()
                        .stroke(Color.bizarreOutline.opacity(0.3), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.bizarreOrange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(completedSteps)")
                        .font(.brandMono(size: 14).bold())
                        .foregroundStyle(.bizarreOrange)
                }
                .frame(width: 48, height: 48)
                .animation(.easeInOut(duration: 0.4), value: progress)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue setup")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("\(completedSteps) of \(totalSteps) steps complete")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .imageScale(.small)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .background(Color.bizarreSurface2.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.75)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup incomplete. \(completedSteps) of \(totalSteps) steps done. Tap to continue.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Cross-device resume helper

/// §36.3 — Cross-device resume: on launch after a deferred setup, call
/// `SetupCrossDeviceResumer.reconcile(server:)` to check server progress and
/// advance the local wizard step to the furthest completed position.
///
/// The server is the source of truth; the local step only moves forward.
public enum SetupCrossDeviceResumer {

    /// Advances the wizard VM's `currentStep` to match the server's furthest
    /// completed step. Only moves forward — never rewinds local progress.
    ///
    /// - Parameters:
    ///   - vm:    The `SetupWizardViewModel` to update.
    ///   - delay: Short delay to let the UI settle before loading. Default 0.3s.
    @MainActor
    public static func reconcile(vm: SetupWizardViewModel, delay: TimeInterval = 0.3) async {
        // Small pause so the wizard sheet can animate in before we mutate state.
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await vm.loadServerState()
        AppLog.ui.info("[SetupResume] Reconciled to server step \(vm.currentStep.rawValue, privacy: .public)")
    }
}

#endif
