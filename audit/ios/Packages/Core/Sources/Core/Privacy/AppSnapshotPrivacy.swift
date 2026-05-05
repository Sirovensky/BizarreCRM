import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI

// §28.8 Screen protection — app-switcher snapshot blur
//
// When the app moves to the background the system takes a snapshot for the
// App Switcher. We intercept `applicationWillResignActive` / `.inactive`
// scenePhase and swap the visible content for a branded blur view so no
// sensitive customer data appears in the thumbnail.
//
// This is ALWAYS on — no Settings toggle because the threat (screenshot of
// the App Switcher by a bystander) affects every user equally.
//
// Usage (in RootView or the root scene body):
//
//   .modifier(AppSnapshotPrivacyModifier())
//
// The modifier injects an opaque branded overlay whenever `scenePhase`
// transitions to `.inactive` or `.background`, then removes it on `.active`.

// MARK: - AppSnapshotPrivacyModifier

/// SwiftUI modifier that overlays a branded blur snapshot-guard whenever the
/// app enters `.inactive` or `.background` scene phase.
///
/// Attach once at the root of the view hierarchy — typically on `RootView` or
/// the outermost `WindowGroup` content view.
public struct AppSnapshotPrivacyModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public func body(content: Content) -> some View {
        ZStack {
            content
            if scenePhase != .active {
                BrandedSnapshotOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: scenePhase)
    }
}

// MARK: - BrandedSnapshotOverlay

/// Full-screen branded overlay displayed during the app-switcher snapshot.
///
/// Uses a solid background (dark adaptive) so even on older devices
/// (pre-iOS 26 without `.glassEffect`) the snapshot is opaque and shows
/// nothing of the previous UI. Avoids a DesignSystem dependency so Core
/// stays a leaf package.
private struct BrandedSnapshotOverlay: View {
    var body: some View {
        Rectangle()
            .fill(.background)
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.4))
                    Text("BizarreCRM")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(.primary.opacity(0.35))
                }
                .accessibilityHidden(true)
            )
    }
}

// MARK: - View extension convenience

public extension View {
    /// Attach the §28.8 app-switcher snapshot privacy overlay.
    ///
    /// Call once on the root view — it propagates to all children automatically.
    func appSnapshotPrivacy() -> some View {
        modifier(AppSnapshotPrivacyModifier())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Snapshot overlay") {
    BrandedSnapshotOverlay()
}
#endif
