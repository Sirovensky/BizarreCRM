import SwiftUI

// §29.3 Image loading — branded placeholder + failure views.
//
// Two tiny SwiftUI views that any image-loading site (Nuke `LazyImage`,
// `AsyncImage`, custom thumbnail grid) can drop into its `placeholder` /
// `failure` slots without re-implementing the visual contract:
//
//   • Placeholder — soft brand-tinted SF Symbol on a faint surface fill.
//     Used while bytes are in flight. Never blank, never pure-grey.
//   • Failure    — danger-tinted SF Symbol over the same surface, with a
//     tap-to-retry hit area. The retry closure re-kicks the parent's load.
//
// Sizing is driven by `.frame` at the call site; the symbol auto-scales.

/// Placeholder shown while an image is loading. Brand-tinted SF Symbol
/// over a low-contrast surface fill. Never blank, never pure grey.
public struct BrandImagePlaceholder: View {

    private let systemImage: String
    private let tint: Color

    public init(systemImage: String = "photo", tint: Color = .bizarrePrimary) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurface1
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaledToFit()
                .padding(20)
                .foregroundStyle(tint.opacity(0.55))
        }
        .accessibilityHidden(true) // decorative — caller labels the slot
    }
}

/// Failure view shown when an image load errors. Danger-tinted SF Symbol
/// + tap to retry. The retry closure is called on tap; callers re-issue
/// the load request from there.
public struct BrandImageFailure: View {

    private let systemImage: String
    private let onRetry: () -> Void

    public init(systemImage: String = "photo.badge.exclamationmark", onRetry: @escaping () -> Void) {
        self.systemImage = systemImage
        self.onRetry = onRetry
    }

    public var body: some View {
        Button(action: onRetry) {
            ZStack {
                Color.bizarreSurface1
                VStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Color.bizarreDanger)
                    Text("Tap to retry")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
                .padding(8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Image failed to load. Tap to retry.")
        .accessibilityAddTraits(.isButton)
    }
}
