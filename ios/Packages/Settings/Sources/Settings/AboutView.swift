import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

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

            // §19.24 Device info
            Section("Device") {
                row(label: "Model", value: deviceModel, mono: false)
                    .accessibilityIdentifier("about.deviceModel")
                row(label: "iOS", value: iosVersion, mono: true)
                    .accessibilityIdentifier("about.iosVersion")
                row(label: "Free storage", value: freeStorageLabel, mono: true)
                    .accessibilityIdentifier("about.freeStorage")
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

    /// §19.24 — Human-readable device model name (e.g. "iPhone 15 Pro").
    private var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    /// §19.24 — iOS / iPadOS version string.
    private var iosVersion: String {
        #if canImport(UIKit)
        let v = UIDevice.current.systemVersion
        return "\(UIDevice.current.systemName) \(v)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    /// §19.24 — Available free storage on the device's main volume.
    private var freeStorageLabel: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "—"
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
