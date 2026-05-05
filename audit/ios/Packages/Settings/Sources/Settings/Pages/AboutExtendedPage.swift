import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §19.24 About — device info + secret gesture to diagnostics

/// Extended About page replacing `AboutView` with §19.24 requirements:
/// - Device info (iOS version, model, free storage)
/// - Long-press version 7x → Diagnostics unlock
/// - App Store review prompt after N sessions
public struct AboutExtendedPage: View {
    @Environment(\.openURL) private var openURL
    @State private var versionTapCount = 0
    @State private var showDiagnostics = false

    public var onOpenDiagnostics: (() -> Void)?

    public init(onOpenDiagnostics: (() -> Void)? = nil) {
        self.onOpenDiagnostics = onOpenDiagnostics
    }

    public var body: some View {
        List {
            Section("App") {
                row(label: "Name", value: "Bizarre CRM", mono: false)
                versionRow
                row(label: "Build", value: Platform.buildNumber, mono: true)
            }

            Section("Device") {
                row(label: "Model", value: deviceModel, mono: false)
                row(label: "iOS", value: iOSVersion, mono: true)
                row(label: "Free storage", value: freeStorageLabel, mono: true)
            }

            Section("Shop") {
                row(label: "Server host", value: hostLabel, mono: true)
            }

            Section("Support") {
                linkRow(icon: "envelope",      title: "Email support",    url: "mailto:support@bizarrecrm.com", identifier: "about.supportEmail")
                linkRow(icon: "hand.raised",   title: "Privacy policy",   url: "https://bizarrecrm.com/privacy", identifier: "about.privacyPolicy")
                linkRow(icon: "doc.text",      title: "Terms of service", url: "https://bizarrecrm.com/terms",   identifier: "about.termsOfService")
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

    // MARK: - Version row with secret gesture (7 taps → Diagnostics)

    private var versionRow: some View {
        HStack {
            Text("Version")
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Spacer()
            Text("\(Platform.appVersion)")
                .font(.brandMono(size: 13))
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
            if versionTapCount > 0 && versionTapCount < 7 {
                Text("\(7 - versionTapCount) more…")
                    .font(.caption2)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            versionTapCount += 1
            if versionTapCount >= 7 {
                versionTapCount = 0
                onOpenDiagnostics?()
            }
        }
        .accessibilityIdentifier("about.version")
        .accessibilityHint("Tap 7 times to open Diagnostics")
    }

    // MARK: - Device info

    private var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    private var iOSVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private var freeStorageLabel: String {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    private var hostLabel: String {
        guard let url = ServerURLStore.load() else { return "—" }
        return url.host ?? url.absoluteString
    }

    // MARK: - Reusable rows

    @ViewBuilder
    private func row(label: String, value: String, mono: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(.bizarreOnSurfaceMuted)
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
                Image(systemName: icon).foregroundStyle(.bizarreOrange).accessibilityHidden(true)
                Text(title).foregroundStyle(.bizarreOnSurface)
                Spacer()
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
