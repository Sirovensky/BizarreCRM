import SwiftUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
import StoreKit
#endif

// MARK: - §19.24 About page — licenses, device info, App Store review, secret 7-tap

// MARK: - Session engagement counter (for App Store review trigger)

public enum AppEngagementCounter {
    private static let key      = "com.bizarrecrm.sessionCount"
    private static let ratedKey = "com.bizarrecrm.storeReviewRequested"

    /// Increment on each authenticated session start. Returns the new total.
    @discardableResult
    public static func increment() -> Int {
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        return count
    }

    public static var count: Int { UserDefaults.standard.integer(forKey: key) }

    /// Request an App Store review if we've had ≥ 10 engaged sessions and
    /// have not requested before.
    @MainActor
    public static func requestReviewIfEligible() {
        guard count >= 10,
              !UserDefaults.standard.bool(forKey: ratedKey) else { return }
        UserDefaults.standard.set(true, forKey: ratedKey)
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            SKStoreReviewController.requestReview(in: scene)
        }
        #endif
    }
}

// MARK: - AboutView

/// §28/§32 parity with Android: a single About screen that surfaces the
/// bundle version, the signed-in server, and the user-visible policy /
/// support entry points. Matches the Android `AboutScreen` layout.
///
/// §19.24 additions:
/// - Device info (iOS version, model, free storage).
/// - Licenses link (NSAcknowledgments / open-source).
/// - App Store review prompt (SKStoreReviewController, N sessions gate).
/// - Secret gesture: long-press version row 7 times → Diagnostics unlock banner.
public struct AboutView: View {
    @Environment(\.openURL) private var openURL

    // Secret 7-tap to unlock Diagnostics
    @State private var versionTapCount = 0
    @State private var showDiagnosticsUnlocked = false

    public init() {}

    public var body: some View {
        List {
            // MARK: App section
            Section("App") {
                row(label: "Name", value: "Bizarre CRM")

                // Version row with 7-tap secret gesture → Diagnostics
                HStack {
                    Text("Version")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Spacer()
                    Text("\(Platform.appVersion) (\(Platform.buildNumber))")
                        .font(.brandMono(size: 13))
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.3) {
                    versionTapCount += 1
                    if versionTapCount >= 7 {
                        versionTapCount = 0
                        showDiagnosticsUnlocked = true
                    }
                }
                .accessibilityLabel("Version \(Platform.appVersion) build \(Platform.buildNumber)")
                .accessibilityHint("Long-press 7 times to unlock diagnostics")
                .accessibilityIdentifier("about.version")
            }

            // MARK: Device section
            Section("Device") {
                row(label: "iOS version", value: deviceOSVersion, mono: true)
                row(label: "Model",       value: deviceModel,     mono: true)
                row(label: "Free storage", value: freeStorageLabel, mono: true)
            }

            // MARK: Shop section
            Section("Shop") {
                row(label: "Server host", value: hostLabel, mono: true)
            }

            // MARK: Support section
            Section("Support") {
                linkRow(icon: "envelope",  title: "Email support",    url: "mailto:support@bizarrecrm.com", identifier: "about.supportEmail")
                linkRow(icon: "hand.raised", title: "Privacy policy", url: "https://bizarrecrm.com/privacy", identifier: "about.privacyPolicy")
                linkRow(icon: "doc.text",  title: "Terms of service", url: "https://bizarrecrm.com/terms", identifier: "about.termsOfService")

                Button {
                    Task { @MainActor in AppEngagementCounter.requestReviewIfEligible() }
                } label: {
                    HStack {
                        Image(systemName: "star")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                        Text("Rate Bizarre CRM")
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                    }
                }
                .accessibilityIdentifier("about.rateApp")
            }

            // MARK: Open-source section
            Section("Open Source") {
                NavigationLink(destination: LicensesView()) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                        Text("Third-party licenses")
                            .foregroundStyle(.bizarreOnSurface)
                    }
                }
                .accessibilityIdentifier("about.licenses")
            }

            // MARK: Legal section
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
        .overlay(alignment: .bottom) {
            if showDiagnosticsUnlocked {
                DiagnosticsUnlockedBanner {
                    showDiagnosticsUnlocked = false
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(BrandMotion.snappy, value: showDiagnosticsUnlocked)
                .onAppear {
                    // Auto-dismiss after 4 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation(BrandMotion.snappy) {
                            showDiagnosticsUnlocked = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Device info helpers

    private var deviceOSVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private var deviceModel: String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }

    private var freeStorageLabel: String {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return "—" }
        let gb = Double(free) / 1_000_000_000
        return String(format: "%.1f GB", gb)
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

// MARK: - Diagnostics unlock banner (§19.24 secret gesture)

private struct DiagnosticsUnlockedBanner: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics unlocked")
                    .font(.brandBodyMedium().bold())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Settings → Diagnostics is now visible.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, interactive: false)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diagnostics unlocked. Settings Diagnostics is now visible.")
    }
}

// MARK: - Licenses view (NSAcknowledgments)

/// Renders third-party open-source licenses sourced from
/// `Acknowledgements.plist` (auto-generated by `scripts/gen-acknowledgements.sh`
/// — Agent 10 tooling scope). Falls back to inline credits.
public struct LicensesView: View {
    public init() {}

    public var body: some View {
        let licenses = Bundle.main.url(forResource: "Acknowledgements", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [[String: Any]] }
            ?? []

        List {
            if licenses.isEmpty {
                Section {
                    Text("Open-source licenses are listed here. Run `scripts/gen-acknowledgements.sh` to generate the bundle.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                // Inline credits for known dependencies
                Section("Known dependencies") {
                    ForEach(inlineLicenses, id: \.name) { item in
                        LicenseRow(name: item.name, license: item.spdx)
                    }
                }
            } else {
                ForEach(licenses, id: \.description) { pkg in
                    if let name = pkg["Title"] as? String,
                       let body = pkg["FooterText"] as? String {
                        LicenseRow(name: name, license: body)
                    }
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Licenses")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private struct InlineLicense { let name: String; let spdx: String }

    private let inlineLicenses: [InlineLicense] = [
        InlineLicense(name: "GRDB.swift",         spdx: "MIT"),
        InlineLicense(name: "Nuke",               spdx: "MIT"),
        InlineLicense(name: "Starscream",          spdx: "Apache 2.0"),
        InlineLicense(name: "Factory",            spdx: "MIT"),
        InlineLicense(name: "Swift Algorithms",   spdx: "Apache 2.0"),
        InlineLicense(name: "Swift Collections",  spdx: "Apache 2.0"),
    ]
}

private struct LicenseRow: View {
    let name: String
    let license: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Button {
                withAnimation(BrandMotion.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text(name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityHint(expanded ? "Collapse license" : "Expand license")

            if expanded {
                Text(license)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}
