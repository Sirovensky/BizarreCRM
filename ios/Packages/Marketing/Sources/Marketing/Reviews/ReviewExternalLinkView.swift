#if canImport(UIKit)
import SwiftUI
import SafariServices

// §37.5 — Sovereignty: external review links always open in SFSafariViewController,
// never via a third-party SDK. iOS app never calls Google / Yelp / Facebook APIs
// directly (§28 data sovereignty).

// MARK: - ReviewExternalLinkView

/// Wraps `SFSafariViewController` for presenting external review platform URLs.
/// Use this instead of `openURL` so we stay within the app's web view sandbox
/// and avoid any third-party-SDK dependency.
public struct ReviewExternalLinkView: UIViewControllerRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.preferredControlTintColor = UIColor(named: "bizarreOrange") ?? .systemOrange
        return vc
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - ReviewExternalLinkModifier

/// View modifier that presents a review platform URL in SFSafariViewController.
///
/// Usage:
/// ```swift
/// Button("Open Google") { reviewURL = googleURL }
///     .reviewExternalLink(url: $reviewURL)
/// ```
public struct ReviewExternalLinkModifier: ViewModifier {
    @Binding var url: URL?

    public func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { url.map { IdentifiableURL(url: $0) } },
            set: { url = $0?.url }
        )) { identifiable in
            ReviewExternalLinkView(url: identifiable.url)
                .ignoresSafeArea()
        }
    }
}

public extension View {
    /// Present a review platform URL in `SFSafariViewController` when `url` is non-nil.
    /// Sovereignty: never calls third-party review APIs. External links open in Safari (§37.5).
    func reviewExternalLink(url: Binding<URL?>) -> some View {
        modifier(ReviewExternalLinkModifier(url: url))
    }
}

// MARK: - IdentifiableURL (internal helper)

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
#endif
