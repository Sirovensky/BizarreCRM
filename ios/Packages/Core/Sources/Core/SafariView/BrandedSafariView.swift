#if canImport(UIKit) && canImport(SafariServices)
import SwiftUI
import SafariServices
import UIKit

// MARK: - BrandedSafariView

/// A SwiftUI view that wraps `SFSafariViewController` and applies the app's
/// brand tint color to the browser chrome (toolbar, controls).
///
/// Usage:
/// ```swift
/// BrandedSafariView(url: trackingURL)
/// ```
///
/// The `SFSafariViewController` is presented inline — use `.sheet` or
/// `.fullScreenCover` to present it modally if needed.
///
/// Thread-safe: all UIKit calls are dispatched on the main actor via SwiftUI
/// lifecycle methods.
public struct BrandedSafariView: UIViewControllerRepresentable {

    // MARK: - Properties

    /// The URL to load in the in-app browser.
    public let url: URL

    /// The tint color applied to the Safari controller's bar buttons.
    /// Defaults to the app's `.accentColor` (set in Asset Catalog).
    public var tintColor: UIColor

    /// Reader mode is available if the page content allows it.
    public var entersReaderIfAvailable: Bool

    /// The bar collapse style for SFSafariViewController.
    public var barCollapsingEnabled: Bool

    // MARK: - Init

    public init(
        url: URL,
        tintColor: UIColor = .tintColor,
        entersReaderIfAvailable: Bool = false,
        barCollapsingEnabled: Bool = true
    ) {
        self.url = url
        self.tintColor = tintColor
        self.entersReaderIfAvailable = entersReaderIfAvailable
        self.barCollapsingEnabled = barCollapsingEnabled
    }

    // MARK: - UIViewControllerRepresentable

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = entersReaderIfAvailable
        config.barCollapsingEnabled = barCollapsingEnabled

        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = tintColor
        controller.dismissButtonStyle = .close
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {
        // SFSafariViewController does not support URL mutation after creation.
        // Tint updates are applied so SwiftUI environment changes propagate.
        uiViewController.preferredControlTintColor = tintColor
    }
}

#endif
