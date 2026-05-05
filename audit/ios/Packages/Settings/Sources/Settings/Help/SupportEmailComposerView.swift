import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(MessageUI)
import MessageUI
#endif

// MARK: - SupportEmailViewModel

@MainActor
@Observable
final class SupportEmailViewModel {

    var supportEmail: String = "support@bizarreelectronics.com"
    var diagnosticsBundle: DiagnosticsBundle?
    var isLoading: Bool = false
    var loadError: String?

    private let api: (any APIClient)?
    private let bundleBuilder: DiagnosticsBundleBuilder

    init(
        api: (any APIClient)? = APIClientHolder.current,
        bundleBuilder: DiagnosticsBundleBuilder = DiagnosticsBundleBuilder()
    ) {
        self.api = api
        self.bundleBuilder = bundleBuilder
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Load diagnostics bundle
        diagnosticsBundle = await bundleBuilder.build()

        // Resolve support contact from server
        guard let api else { return }
        do {
            let contact = try await api.fetchSupportContact()
            supportEmail = contact.email
        } catch {
            loadError = error.localizedDescription
        }
    }

    var emailSubject: String {
        let version = diagnosticsBundle?.appVersion ?? Platform.appVersion
        return "BizarreCRM iOS \(version) — Support Request"
    }

    var emailBody: String {
        var lines: [String] = [
            "Hello BizarreCRM Support,",
            "",
            "Please describe your issue below:",
            "",
            "---",
            "Diagnostic Information",
            "App Version: \(diagnosticsBundle?.appVersion ?? "—")",
            "Build: \(diagnosticsBundle?.buildNumber ?? "—")",
            "iOS Version: \(diagnosticsBundle?.iosVersion ?? "—")",
            "Device: \(diagnosticsBundle?.deviceModel ?? "—")"
        ]
        if let slug = diagnosticsBundle?.tenantSlug {
            lines.append("Tenant: \(slug)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - SupportEmailComposerView

/// Send-support-email view with diagnostic bundle pre-filled.
/// Recipient resolved from `GET /tenants/me/support-contact`.
public struct SupportEmailComposerView: View {

    @State private var vm = SupportEmailViewModel()
    @State private var showMailComposer = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Contact Support")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading…")
                .accessibilityLabel("Loading support contact")
        } else {
            VStack(spacing: BrandSpacing.xl) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(spacing: BrandSpacing.sm) {
                    Text("We're Here to Help")
                        .font(.brandHeadlineMedium())
                        .foregroundStyle(.bizarreOnSurface)

                    Text("Describe your issue and we'll get back to you within one business day. Diagnostic info (app version, device model, recent error logs — no personal data) is pre-filled so our team can reproduce the problem faster.")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.base)

                    Text(vm.supportEmail)
                        .font(.brandMono(size: 14))
                        .foregroundStyle(.bizarreOrange)
                        .textSelection(.enabled)
                        .accessibilityLabel("Support email: \(vm.supportEmail)")
                }

                if let err = vm.loadError {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .multilineTextAlignment(.center)
                }

                Button("Open Mail") {
                    openMail()
                }
                .padding(.horizontal, BrandSpacing.xl)
                .padding(.vertical, BrandSpacing.md)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 12), tint: .bizarreOrange, interactive: true)
                .accessibilityLabel("Open Mail to contact support")
            }
            .padding(BrandSpacing.base)
        }
    }

    private func openMail() {
        let subject = vm.emailSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = vm.emailBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let recipient = vm.supportEmail.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "mailto:\(recipient)?subject=\(subject)&body=\(body)"
        guard let url = URL(string: urlStr) else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SupportEmailComposerView()
}
#endif
