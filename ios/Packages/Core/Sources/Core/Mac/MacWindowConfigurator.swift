import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §23.2 Mac window size + title configurator
//
// Sets minimum window size and per-scene window titles on macOS
// ("Designed for iPad"). No-ops on iPhone / iPad native.
//
// Minimum size: 900×600 (§23.2).
// Preferred size: 1280×800 (§23.2).
// Window title: derived from the active scene's content (e.g. "Ticket #1234 - BizarreCRM").
//
// Usage — call once from your scene delegate or RootView onAppear:
//   MacWindowConfigurator.configure(scene: windowScene, title: "BizarreCRM")
//   MacWindowConfigurator.configure(scene: windowScene, title: "Ticket #1234 - BizarreCRM")

public enum MacWindowConfigurator {

    // MARK: - Constants

    /// Minimum window width required by §23.2.
    public static let minimumWidth: CGFloat  = 900
    /// Minimum window height required by §23.2.
    public static let minimumHeight: CGFloat = 600
    /// Default preferred launch width.
    public static let preferredWidth: CGFloat  = 1280
    /// Default preferred launch height.
    public static let preferredHeight: CGFloat = 800

    // MARK: - Configuration

    /// Apply Mac window constraints and set the title.
    ///
    /// Silently no-ops on non-Mac platforms so call sites need no `#if` guards.
    ///
    /// - Parameters:
    ///   - windowScene: The `UIWindowScene` to configure.
    ///   - title: The window title string. Defaults to "BizarreCRM".
    @MainActor
    public static func configure(
        _ windowScene: AnyObject?,   // UIWindowScene — typed as AnyObject to avoid UIKit import at callsite
        title: String = "BizarreCRM"
    ) {
        #if targetEnvironment(macCatalyst)
        // Mac Catalyst path — not used (we use "Designed for iPad").
        #elseif canImport(UIKit)
        guard
            let scene = windowScene as? UIWindowScene,
            UIDevice.current.userInterfaceIdiom == .mac || ProcessInfo.processInfo.isiOSAppOnMac
        else { return }

        // Set minimum / preferred sizes via UIWindowScene.sizeRestrictions
        if let restrictions = scene.sizeRestrictions {
            restrictions.minimumSize  = CGSize(width: minimumWidth,  height: minimumHeight)
            restrictions.maximumSize  = CGSize(width: .infinity,     height: .infinity)
        }

        // Set window title so the title-bar reads e.g. "Ticket #1234 - BizarreCRM".
        scene.title = title
        #endif
    }

    // MARK: - Dynamic title helpers

    /// Build a window title for a ticket detail scene.
    public static func titleForTicket(id: Int64, customerName: String? = nil) -> String {
        if let name = customerName {
            return "Ticket #\(id) · \(name) — BizarreCRM"
        }
        return "Ticket #\(id) — BizarreCRM"
    }

    /// Build a window title for a customer detail scene.
    public static func titleForCustomer(name: String) -> String {
        "\(name) — BizarreCRM"
    }

    /// Build a window title for a POS / register scene.
    public static func titleForPOS(locationName: String? = nil) -> String {
        if let loc = locationName { return "POS · \(loc) — BizarreCRM" }
        return "POS Register — BizarreCRM"
    }

    /// Build a window title for a Reports dashboard scene.
    public static func titleForReports() -> String {
        "Reports — BizarreCRM"
    }
}
