import Foundation

// MARK: - ExternalLinkPresenter

/// Determines whether an external URL should be opened in
/// `SFSafariViewController` (in-app) or a `WKWebView`-based in-app browser,
/// based on link type and the allowlist outcome.
///
/// ## Decision logic
///
/// | Condition                           | Presentation      |
/// |-------------------------------------|-------------------|
/// | Public tracking / pay / estimate    | `.safari`         |
/// | URL passes allowlist                | `.safari`         |
/// | URL blocked by allowlist            | `.blocked`        |
/// | Non-HTTPS scheme (tel:, mailto:, …) | `.system`         |
///
/// ## Usage
/// ```swift
/// let presenter = ExternalLinkPresenter(allowlistValidator: validator)
/// switch presenter.presentation(for: url) {
/// case .safari(let url):   // present BrandedSafariView(url: url)
/// case .system(let url):   // UIApplication.open(url)
/// case .blocked(let reason): // show error / ignore
/// }
/// ```
///
/// Thread-safe: all state is immutable after init.
public struct ExternalLinkPresenter: Sendable {

    // MARK: - Presentation

    /// How the caller should handle the URL.
    public enum Presentation: Sendable, Equatable {
        /// Open in `SFSafariViewController` / `BrandedSafariView`.
        case safari(URL)
        /// Delegate to the OS (`UIApplication.open`). Used for non-HTTP schemes.
        case system(URL)
        /// Do not open; the URL failed the allowlist check.
        case blocked(reason: String)
    }

    // MARK: - Link classification

    /// Categories assigned to URLs before routing.
    public enum LinkKind: Sendable, Equatable {
        case publicTracking
        case publicPayment
        case publicEstimate
        case generic
        case nonHTTP
    }

    // MARK: - Properties

    private let allowlistValidator: LinkAllowlistValidator

    // MARK: - Init

    public init(allowlistValidator: LinkAllowlistValidator) {
        self.allowlistValidator = allowlistValidator
    }

    // MARK: - Public API

    /// Classify `url` and return the appropriate `Presentation`.
    public func presentation(for url: URL) -> Presentation {
        let kind = classify(url)

        switch kind {
        case .nonHTTP:
            // tel:, mailto:, etc. — hand off to OS; never open in-app.
            return .system(url)

        case .publicTracking, .publicPayment, .publicEstimate:
            // Public links are always opened in Safari — they bypass the
            // tenant allowlist because they are already scoped to the
            // canonical BizarreCRM host.
            return .safari(url)

        case .generic:
            switch allowlistValidator.validate(url) {
            case .allowed:
                return .safari(url)
            case .blocked(let reason):
                return .blocked(reason: reason)
            }
        }
    }

    /// Classify a URL without performing the allowlist check.
    public func classify(_ url: URL) -> LinkKind {
        guard let scheme = url.scheme?.lowercased() else { return .nonHTTP }
        guard scheme == "https" || scheme == "http" else { return .nonHTTP }

        let path = url.path
        if path.hasPrefix("/track/") { return .publicTracking }
        if path.hasPrefix("/pay/") { return .publicPayment }
        if path.hasPrefix("/estimate/") { return .publicEstimate }

        return .generic
    }
}
