import SwiftUI
import DesignSystem

// §20.3 — Conflict-resolved toast
//
// A top-of-screen glass toast that appears briefly after a sync conflict
// is successfully resolved. It names the entity and the chosen resolution
// strategy (server-wins / local-wins / merged / discarded).
//
// Usage — in ConflictDiffView or any screen that drives ConflictResolutionViewModel:
//
//   ContentView()
//       .conflictResolvedToast(phase: viewModel.phase)
//
// The toast auto-dismisses after 3 seconds and respects Reduce Motion.

// MARK: - ConflictResolvedToast

/// Internal toast view rendered inside `ConflictResolvedToastModifier`.
struct ConflictResolvedToast: View {

    let conflictId: Int
    let resolution: Resolution

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.bizarreSuccess)
                .imageScale(.medium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Conflict resolved")
                    .font(.brandLabelSmall().weight(.semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Text(subtitleText)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Copy

    private var subtitleText: String {
        switch resolution {
        case .keepServer: return "Server version kept"
        case .keepClient: return "Your version kept"
        case .merge:      return "Changes merged"
        case .manual:     return "Resolved manually"
        case .rejected:   return "Local change rejected"
        }
    }

    private var a11yLabel: String {
        "Conflict \(conflictId) resolved. \(subtitleText)."
    }
}

// MARK: - ConflictResolvedToastModifier

/// Modifier that watches a `ConflictResolutionPhase` and shows the
/// resolved toast whenever the phase enters `.resolved`.
public struct ConflictResolvedToastModifier: ViewModifier {

    public let phase: ConflictResolutionPhase

    @State private var isVisible: Bool = false
    @State private var resolvedId: Int = 0
    @State private var resolvedResolution: Resolution = .serverWins
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let autoDismissDelay: TimeInterval = 3.0

    public init(phase: ConflictResolutionPhase) {
        self.phase = phase
    }

    public func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if isVisible {
                    ConflictResolvedToast(conflictId: resolvedId, resolution: resolvedResolution)
                        .padding(.top, BrandSpacing.xs)
                        .transition(transition)
                        .animation(bannerAnimation, value: isVisible)
                }
            }
            .onChange(of: phase) { _, newPhase in
                if case .resolved(let id, let res) = newPhase {
                    resolvedId = id
                    resolvedResolution = res
                    withAnimation(bannerAnimation) { isVisible = true }
                    Task {
                        try? await Task.sleep(for: .seconds(Self.autoDismissDelay))
                        withAnimation(bannerAnimation) { isVisible = false }
                    }
                }
            }
    }

    // MARK: - Motion helpers

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }

    private var bannerAnimation: Animation {
        reduceMotion ? .linear(duration: 0) : BrandMotion.banner
    }
}

// MARK: - View extension

public extension View {
    /// §20.3 — Attach the conflict-resolved toast to this screen.
    ///
    /// Pass the current `ConflictResolutionPhase` from your ViewModel.
    /// The toast auto-dismisses after 3 s.
    func conflictResolvedToast(phase: ConflictResolutionPhase) -> some View {
        modifier(ConflictResolvedToastModifier(phase: phase))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Conflict resolved toast — server wins") {
    VStack {
        Spacer()
        Text("Content area")
        Spacer()
    }
    .conflictResolvedToast(phase: .resolved(conflictId: 42, resolution: .keepServer))
}
#endif
