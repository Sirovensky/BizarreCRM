#if canImport(UIKit)
import SwiftUI
import Network
import Core
import DesignSystem

// MARK: - §36.5 Captive-portal + VPN detection

/// Network-layer diagnostics used in the Setup Wizard and Diagnostics settings.
///
/// **Captive portal:** iOS posts `kCNNetworkingAttributesProxies` changes when
/// a captive portal is detected. We probe Apple's known CNA endpoint and check
/// if the redirect lands elsewhere. A simple heuristic is used since the
/// `NEHotspotHelper` API requires an entitlement we deliberately avoid.
///
/// **VPN:** `NWPathMonitor` reports interface types including `.other` which
/// covers tunnels. `NetworkDiagnosticsViewModel` checks each path interface for
/// the `isVPN` heuristic.
///
/// Sovereignty: all probes go only to Apple's public CNA endpoint and to the
/// tenant server. No third-party analytics.

// MARK: - NetworkDiagnosticStatus

public enum NetworkDiagnosticStatus: Sendable, Equatable {
    case unknown
    case checking
    case ok
    case captivePortalDetected(portalURL: URL?)
    case vpnDetected
    case failed(reason: String)

    public var isCaptivePortal: Bool {
        if case .captivePortalDetected = self { return true }
        return false
    }

    public var isVPN: Bool { self == .vpnDetected }
    public var isOK: Bool { self == .ok }

    public var icon: String {
        switch self {
        case .unknown, .checking:           return "questionmark.circle"
        case .ok:                           return "checkmark.circle.fill"
        case .captivePortalDetected:        return "wifi.exclamationmark"
        case .vpnDetected:                  return "lock.shield"
        case .failed:                       return "xmark.circle.fill"
        }
    }

    public var iconColor: Color {
        switch self {
        case .unknown:                      return Color.bizarreOnSurfaceMuted
        case .checking:                     return Color.bizarreOrange
        case .ok:                           return Color.bizarreSuccess
        case .captivePortalDetected:        return Color.bizarreWarning
        case .vpnDetected:                  return Color.bizarreInfo
        case .failed:                       return Color.bizarreError
        }
    }
}

extension NetworkDiagnosticStatus: Hashable {}

// MARK: - NetworkDiagnosticsViewModel

@MainActor
@Observable
public final class NetworkDiagnosticsViewModel {

    // MARK: - Published state

    public private(set) var captivePortalStatus: NetworkDiagnosticStatus = .unknown
    public private(set) var vpnStatus: NetworkDiagnosticStatus = .unknown
    public private(set) var isRunning: Bool = false

    // MARK: - Dependencies

    private let urlSession: URLSession

    // Apple's lightweight Captive Network Assistance probe URL.
    // Returns HTTP 200 with a body that ends in "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>"
    // when no captive portal intercepts. Any redirect or different body indicates captive portal.
    private static let cnaProbeURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!

    // MARK: - Init

    /// Designated init. Pass `.shared` or an injected session.
    /// Production callers needing an ephemeral session should construct it
    /// in the Networking package (the only §28.3-approved path) and inject.
    ///
    /// Default is `.shared` — sufficient for the CNA probe since
    /// `URLSession.shared` respects system proxy settings.
    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Run

    public func runDiagnostics() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        async let captive: Void = checkCaptivePortal()
        async let vpn: Void     = checkVPN()
        await captive
        await vpn
    }

    // MARK: - Captive-portal check

    private func checkCaptivePortal() async {
        captivePortalStatus = .checking

        do {
            var request = URLRequest(url: Self.cnaProbeURL)
            request.addValue("CaptiveNetworkSupport/1.0 wispr", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await urlSession.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                captivePortalStatus = .failed(reason: "Unexpected response type.")
                return
            }

            // Check if we were redirected to a non-Apple URL (captive portal sign-in page)
            if let finalURL = http.url, finalURL.host != "captive.apple.com" {
                captivePortalStatus = .captivePortalDetected(portalURL: finalURL)
                return
            }

            // Check body for the known success token
            let body = String(data: data, encoding: .utf8) ?? ""
            let isSuccess = body.contains("Success")
            captivePortalStatus = isSuccess ? .ok : .captivePortalDetected(portalURL: http.url)

        } catch URLError.notConnectedToInternet {
            captivePortalStatus = .failed(reason: "No internet connection.")
        } catch {
            // A captive portal often blocks or redirects entirely — treat connection
            // errors on this probe as a possible captive portal.
            captivePortalStatus = .captivePortalDetected(portalURL: nil)
        }
    }

    // MARK: - VPN detection

    private func checkVPN() async {
        vpnStatus = .checking

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "setup.network.diagnostics.vpn")
        monitor.start(queue: queue)

        // Give NWPathMonitor a moment to populate
        try? await Task.sleep(for: .milliseconds(300))
        let path = monitor.currentPath
        monitor.cancel()

        // Check if any active interface looks like a VPN / tunnel
        // `isVPNLike` uses the interface type.
        let hasVPN = path.availableInterfaces.contains { isVPNInterface($0) }

        if hasVPN {
            vpnStatus = .vpnDetected
        } else if path.status == .unsatisfied {
            vpnStatus = .failed(reason: "No network path available.")
        } else {
            vpnStatus = .ok
        }
    }

    /// Heuristic: VPN/tunnel interfaces appear as `.other` with names like `utun0`,
    /// `ppp0`, `ipsec0`, or `tun0`. We check the interface name prefix.
    private func isVPNInterface(_ iface: NWInterface) -> Bool {
        let name = iface.name.lowercased()
        let vpnPrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wireguard"]
        return vpnPrefixes.contains(where: { name.hasPrefix($0) })
            || iface.type == .other
    }
}

// MARK: - SetupNetworkWarningBanner

/// Inline warning banner shown in the Setup Wizard and Diagnostics settings
/// when a captive portal or VPN is detected.
///
/// - Captive portal: warns that the portal may intercept setup traffic;
///   offers "Open portal" button to launch `SFSafariViewController`.
/// - VPN: notes that VPN may interfere with local-IP printer/terminal connections.
public struct SetupNetworkWarningBanner: View {

    public let captivePortalStatus: NetworkDiagnosticStatus
    public let vpnStatus: NetworkDiagnosticStatus

    /// Called when the user taps "Open portal". Passes the portal URL.
    public let onOpenPortal: ((URL) -> Void)?

    public init(
        captivePortalStatus: NetworkDiagnosticStatus,
        vpnStatus: NetworkDiagnosticStatus,
        onOpenPortal: ((URL) -> Void)? = nil
    ) {
        self.captivePortalStatus = captivePortalStatus
        self.vpnStatus = vpnStatus
        self.onOpenPortal = onOpenPortal
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            if case .captivePortalDetected(let url) = captivePortalStatus {
                captivePortalBanner(url: url)
            }
            if vpnStatus.isVPN {
                vpnBanner
            }
        }
    }

    // MARK: - Captive portal banner

    private func captivePortalBanner(url: URL?) -> some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.bizarreWarning)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("Captive portal detected")
                    .font(.brandLabelLarge().bold())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Your Wi-Fi requires you to sign in before using the internet. Setup traffic may be blocked until you complete the portal login.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let url {
                    Button {
                        onOpenPortal?(url)
                    } label: {
                        Label("Open portal", systemImage: "arrow.up.right.square")
                            .font(.brandLabelSmall().bold())
                            .foregroundStyle(Color.bizarreOrange)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open captive portal login page")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .brandGlass(
            .regular,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md),
            tint: Color.bizarreWarning.opacity(0.10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreWarning.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - VPN banner

    private var vpnBanner: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.bizarreInfo)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                Text("VPN detected")
                    .font(.brandLabelLarge().bold())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("An active VPN may interfere with connections to local-IP devices (printers, card terminals). If you experience connection issues, try disabling the VPN temporarily.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .brandGlass(
            .regular,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md),
            tint: Color.bizarreInfo.opacity(0.08)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(Color.bizarreInfo.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#endif
