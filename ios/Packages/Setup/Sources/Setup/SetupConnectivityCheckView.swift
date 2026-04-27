#if canImport(UIKit)
import SwiftUI
import Network
import Core
import DesignSystem

// MARK: - §36.5 First-run connectivity check

// MARK: - CheckStatus

public enum ConnectivityCheckStatus: Sendable {
    case pending
    case checking
    case ok
    case failed(reason: String)

    public var isOK: Bool {
        if case .ok = self { return true }
        return false
    }

    public var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var icon: String {
        switch self {
        case .pending:  return "circle.dotted"
        case .checking: return "arrow.triangle.2.circlepath"
        case .ok:       return "checkmark.circle.fill"
        case .failed:   return "xmark.circle.fill"
        }
    }

    public var iconColor: Color {
        switch self {
        case .pending:  return Color.bizarreOnSurfaceMuted
        case .checking: return Color.bizarreOrange
        case .ok:       return Color.bizarreSuccess
        case .failed:   return Color.bizarreError
        }
    }
}

// MARK: - SetupConnectivityCheckViewModel

@MainActor
@Observable
public final class SetupConnectivityCheckViewModel {

    // MARK: - Checks

    public private(set) var internetStatus: ConnectivityCheckStatus = .pending
    public private(set) var serverStatus: ConnectivityCheckStatus = .pending

    public private(set) var isRunning: Bool = false
    public private(set) var allPassed: Bool = false

    // Dependencies
    private let serverURLProvider: @Sendable () -> URL?
    private let urlSession: URLSession

    // MARK: - Init

    public init(
        serverURLProvider: @escaping @Sendable () -> URL? = { nil },
        urlSession: URLSession = .shared
    ) {
        self.serverURLProvider = serverURLProvider
        self.urlSession = urlSession
    }

    // MARK: - Run checks

    public func runChecks() async {
        guard !isRunning else { return }
        isRunning = true
        allPassed = false
        defer { isRunning = false }

        await checkInternet()
        await checkServer()

        allPassed = internetStatus.isOK && serverStatus.isOK
    }

    // MARK: - Internet check (NWPathMonitor snapshot)

    private func checkInternet() async {
        internetStatus = .checking

        // NWPathMonitor provides a one-shot path without a background loop
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "setup.connectivity.internet")
        monitor.start(queue: queue)
        // Give it a moment to populate the path
        try? await Task.sleep(for: .milliseconds(400))
        let satisfied = monitor.currentPath.status == .satisfied
        monitor.cancel()

        internetStatus = satisfied ? .ok : .failed(reason: "No internet connection. Connect to Wi-Fi or cellular.")
    }

    // MARK: - Server reachability check

    private func checkServer() async {
        guard internetStatus.isOK else {
            serverStatus = .failed(reason: "Skipped — no internet.")
            return
        }

        guard let baseURL = serverURLProvider() else {
            serverStatus = .failed(reason: "Server URL not configured. Enter your shop URL on the login screen.")
            return
        }

        serverStatus = .checking

        // Health probe — try GET /health or /api/v1/auth/setup-status
        let probeURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: probeURL)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await urlSession.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...299).contains(code) || code == 401 {
                // 401 means the server is up but auth-gated — that's fine
                serverStatus = .ok
            } else {
                serverStatus = .failed(reason: "Server responded with status \(code). Check your server URL.")
            }
        } catch {
            serverStatus = .failed(reason: "Can't reach your server. Verify the URL and your network.")
        }
    }
}

// MARK: - SetupConnectivityCheckView

/// §36.5 First-run wizard step that verifies internet + server reachability.
///
/// Shown at the start of the Setup Wizard before the user enters any data.
/// Each check shows green (ok) or red (failed) with a fix link.
///
/// - iPhone: vertical list of checks, sticky Continue CTA at bottom.
/// - iPad: centred glass card (max-width 560 pt).
public struct SetupConnectivityCheckView: View {

    @State private var vm: SetupConnectivityCheckViewModel

    private let onContinue: () -> Void
    private let onSkip: () -> Void

    public init(
        viewModel: SetupConnectivityCheckViewModel = SetupConnectivityCheckViewModel(),
        onContinue: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self._vm = State(wrappedValue: viewModel)
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task { await vm.runChecks() }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.xl)
                    .padding(.bottom, BrandSpacing.lg)
            }
            actionRow
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.md)
                .brandGlass(.regular, in: Rectangle())
        }
    }

    private var iPadLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xxl) {
                content
                actionRow
            }
            .frame(maxWidth: 560)
            .padding(BrandSpacing.xxxl)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
            .padding(.horizontal, BrandSpacing.xxl)
            .padding(.top, BrandSpacing.xl)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xl) {
            // Header
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Image(systemName: "wifi.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Checking your connection")
                    .font(.brandDisplaySmall())
                    .foregroundStyle(Color.bizarreOnSurface)

                Text("Before you start, we need to verify that your device can reach the internet and your server.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Check rows
            VStack(spacing: BrandSpacing.md) {
                checkRow(
                    label: "Internet",
                    description: "Connected to the internet",
                    status: vm.internetStatus,
                    fixURL: nil
                )
                checkRow(
                    label: "Server",
                    description: "Your shop server is reachable",
                    status: vm.serverStatus,
                    fixURL: nil
                )
            }
            .padding(BrandSpacing.md)
            .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

            // Retry button when anything failed
            if !vm.isRunning && !vm.allPassed {
                Button {
                    Task { await vm.runChecks() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.brandLabelLarge())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.brandGlass)
                .accessibilityLabel("Retry connectivity checks")
            }
        }
    }

    private func checkRow(
        label: String,
        description: String,
        status: ConnectivityCheckStatus,
        fixURL: URL?
    ) -> some View {
        HStack(spacing: BrandSpacing.md) {
            // Icon
            Group {
                if case .checking = status {
                    ProgressView()
                        .tint(Color.bizarreOrange)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: status.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(status.iconColor)
                        .frame(width: 28, height: 28)
                }
            }
            .accessibilityHidden(true)

            // Labels
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(label)
                    .font(.brandBodyLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                if case .failed(let reason) = status {
                    Text(reason)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreError)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = fixURL {
                        Link("Get help", destination: url)
                            .font(.brandLabelSmall())
                            .foregroundStyle(Color.bizarreOrange)
                    }
                } else {
                    Text(description)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                }
            }

            Spacer()
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(accessibilityStatusLabel(status))")
    }

    private func accessibilityStatusLabel(_ status: ConnectivityCheckStatus) -> String {
        switch status {
        case .pending:          return "pending"
        case .checking:         return "checking"
        case .ok:               return "connected"
        case .failed(let r):    return "failed — \(r)"
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: BrandSpacing.md) {
            Button("Skip check", action: onSkip)
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityLabel("Skip connectivity check and continue anyway")

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .font(.brandLabelLarge().bold())
            .foregroundStyle(
                vm.allPassed ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted
            )
            .padding(.horizontal, BrandSpacing.xl)
            .padding(.vertical, BrandSpacing.sm)
            .brandGlass(
                .regular,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg),
                tint: vm.allPassed ? Color.bizarreOrange.opacity(0.18) : .clear,
                interactive: true
            )
            .disabled(vm.isRunning)
            .accessibilityLabel(vm.allPassed ? "Continue to setup" : "Continue anyway (some checks failed)")
        }
    }
}

#endif
