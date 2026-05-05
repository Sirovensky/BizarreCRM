#if canImport(PassKit)
#if canImport(UIKit)
import Foundation
import PassKit
import UIKit

/// §38 — Thin wrapper that presents a `.pkpass` blob via `PKAddPassesViewController`.
///
/// Usage:
/// ```swift
/// try LoyaltyPassPresenter().present(passData: rawPkpassData)
/// ```
///
/// The presenter finds the key window's root view controller and presents
/// the system Wallet sheet modally. All PassKit interaction is guarded
/// behind `#if canImport(PassKit)` + `#if canImport(UIKit)` so the
/// Loyalty package compiles on macOS without the frameworks.
public struct LoyaltyPassPresenter {

    public init() {}

    /// Present the Wallet add-pass sheet for `passData`.
    ///
    /// - Throws: `LoyaltyError.invalidPass` if the data cannot be parsed
    ///   as a `PKPass`.
    /// - Throws: `LoyaltyError.noRootViewController` if no suitable
    ///   view controller is found to present from.
    public func present(passData: Data) throws {
        let pass: PKPass
        do {
            pass = try PKPass(data: passData)
        } catch {
            throw LoyaltyError.invalidPass
        }

        guard let controller = PKAddPassesViewController(pass: pass) else {
            // PKAddPassesViewController returns nil when PassKit is not
            // supported on the device (e.g. simulated hardware that lacks
            // the Secure Element). Treat as an invalid pass scenario so
            // the caller can show an appropriate error.
            throw LoyaltyError.invalidPass
        }

        guard let root = rootViewController() else {
            throw LoyaltyError.noRootViewController
        }

        root.present(controller, animated: true)
    }

    // MARK: - Private

    /// Traverses the connected window scene hierarchy to find the
    /// topmost presented view controller for modal presentation.
    private func rootViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        guard let window = scene?.windows.first(where: { $0.isKeyWindow })
                ?? scene?.windows.first else {
            return nil
        }

        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - LoyaltyError

/// Domain errors surfaced by the Loyalty package.
public enum LoyaltyError: Error, LocalizedError, Sendable {
    /// The raw bytes could not be parsed as a valid `PKPass`.
    case invalidPass
    /// No root `UIViewController` was available to present from.
    case noRootViewController

    public var errorDescription: String? {
        switch self {
        case .invalidPass:
            return "The loyalty pass could not be opened. Please try again."
        case .noRootViewController:
            return "Could not find a window to present the pass from."
        }
    }
}

#endif // canImport(UIKit)
#endif // canImport(PassKit)
