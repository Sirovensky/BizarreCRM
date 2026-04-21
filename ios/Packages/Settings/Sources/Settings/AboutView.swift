import SwiftUI
import Core
import DesignSystem
import Networking

/// §28/§32 parity with Android: a single About screen that surfaces the
/// bundle version, the signed-in server, and the user-visible policy /
/// support entry points. Matches the Android `AboutScreen` layout.
public struct AboutView: View {
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        List {
            Section("App") {
                row(label: "Name", value: "Bizarre CRM")
                row(label: "Version", value: "\(Platform.appVersion) (\(Platform.buildNumber))", mono: true)
            }

            Section("Shop") {
                row(label: "Server host", value: hostLabel, mono: true)
            }

            Section("Support") {
                linkRow(icon: "envelope", title: "Email support", url: "mailto:support@bizarrecrm.com", identifier: "about.supportEmail")
                linkRow(icon: "hand.raised", title: "Privacy policy", url: "https://bizarrecrm.com/privacy", identifier: "about.privacyPolicy")
                linkRow(icon: "doc.text", title: "Terms of service", url: "https://bizarrecrm.com/terms", identifier: "about.termsOfService")
            }

            Section("Legal") {
                Text("© 2026 Bizarre CRM. All rights reserved.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("About")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers

    private var hostLabel: String {
        guard let url = ServerURLStore.load() else { return "—" }
        return url.host ?? url.absoluteString
    }

    @ViewBuilder
    private func row(label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text(value)
                .font(mono ? .brandMono(size: 13) : .body)
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    @ViewBuilder
    private func linkRow(icon: String, title: String, url: String, identifier: String) -> some View {
        Button {
            guard let u = URL(string: url) else { return }
            openURL(u)
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
