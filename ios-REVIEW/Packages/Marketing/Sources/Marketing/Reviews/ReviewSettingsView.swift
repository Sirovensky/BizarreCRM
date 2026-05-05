import SwiftUI
import DesignSystem
import Networking

// MARK: - ReviewMonitoringSettings

/// §37.5 — Tenant-configured monitoring preferences: optional push alert when
/// external review appears, and automatic high-score nudge thresholds.
public struct ReviewMonitoringSettings: Codable, Sendable {
    /// Push an in-app alert when the tenant's review monitoring webhook fires.
    public var externalReviewAlertEnabled: Bool
    /// Minimum NPS score (0-10) to trigger a post-survey nudge. Default 9.
    public var nudgeMinNPSScore: Int
    /// Minimum CSAT score (1-5) to trigger a post-survey nudge. Default 4.
    public var nudgeMinCSATScore: Int

    public init(
        externalReviewAlertEnabled: Bool = true,
        nudgeMinNPSScore: Int = 9,
        nudgeMinCSATScore: Int = 4
    ) {
        self.externalReviewAlertEnabled = externalReviewAlertEnabled
        self.nudgeMinNPSScore = nudgeMinNPSScore
        self.nudgeMinCSATScore = nudgeMinCSATScore
    }
}

// MARK: - ReviewSettingsViewModel

@Observable
@MainActor
public final class ReviewSettingsViewModel {
    public var googleURL: String = ""
    public var yelpURL: String = ""
    public var facebookURL: String = ""
    // §37.5 monitoring settings
    public var monitoringSettings: ReviewMonitoringSettings = .init()
    public var isSaving = false
    public var errorMessage: String?
    public var didSave = false

    private let api: APIClient

    public init(api: APIClient, existing: ReviewPlatformSettings? = nil) {
        self.api = api
        if let s = existing {
            googleURL = s.googleBusinessURL?.absoluteString ?? ""
            yelpURL = s.yelpURL?.absoluteString ?? ""
            facebookURL = s.facebookURL?.absoluteString ?? ""
        }
    }

    public var isValid: Bool {
        isValidURLOrEmpty(googleURL) &&
        isValidURLOrEmpty(yelpURL) &&
        isValidURLOrEmpty(facebookURL) &&
        monitoringSettings.nudgeMinNPSScore >= 0 &&
        monitoringSettings.nudgeMinNPSScore <= 10 &&
        monitoringSettings.nudgeMinCSATScore >= 1 &&
        monitoringSettings.nudgeMinCSATScore <= 5
    }

    /// Configured platforms that have a non-empty URL — shown in list view.
    public var configuredPlatforms: [(label: String, url: URL)] {
        var result: [(String, URL)] = []
        if let u = URL(string: googleURL), !googleURL.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(("Google", u))
        }
        if let u = URL(string: yelpURL), !yelpURL.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(("Yelp", u))
        }
        if let u = URL(string: facebookURL), !facebookURL.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(("Facebook", u))
        }
        return result
    }

    public func save() async {
        guard isValid else {
            errorMessage = "One or more URLs are invalid."
            return
        }
        isSaving = true
        errorMessage = nil
        let settings = ReviewPlatformSettings(
            googleBusinessURL: URL(string: googleURL),
            yelpURL: URL(string: yelpURL),
            facebookURL: URL(string: facebookURL)
        )
        do {
            _ = try await api.saveReviewPlatformSettings(settings)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func isValidURLOrEmpty(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        guard let url = URL(string: trimmed) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }
}

// MARK: - ReviewSettingsView

/// Admin: configure review platforms, monitoring, and high-score nudge thresholds.
/// §37.5 — Settings → Reviews → list of platforms.
public struct ReviewSettingsView: View {
    @State private var vm: ReviewSettingsViewModel

    public init(api: APIClient, existing: ReviewPlatformSettings? = nil) {
        _vm = State(initialValue: ReviewSettingsViewModel(api: api, existing: existing))
    }

    public var body: some View {
        Form {
            // §37.5 — Settings → Reviews → list of platforms
            if !vm.configuredPlatforms.isEmpty {
                Section {
                    ForEach(vm.configuredPlatforms, id: \.label) { platform in
                        LabeledContent(platform.label) {
                            Text(platform.url.host ?? platform.url.absoluteString)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .accessibilityLabel("\(platform.label): \(platform.url.absoluteString)")
                    }
                } header: {
                    Text("Configured Platforms")
                } footer: {
                    Text("These platforms will appear in the customer review nudge sheet after a high rating.")
                        .font(.brandLabelSmall())
                }
            }

            Section {
                urlField(label: "Google Business URL", text: $vm.googleURL, placeholder: "https://g.page/your-business")
                urlField(label: "Yelp URL", text: $vm.yelpURL, placeholder: "https://www.yelp.com/biz/your-business")
                urlField(label: "Facebook URL", text: $vm.facebookURL, placeholder: "https://www.facebook.com/your-page")
            } header: {
                Text("Review Platform URLs")
            } footer: {
                Text("Leave blank to skip a platform. URLs must be https.")
                    .font(.brandLabelSmall())
            }

            // §37.5 — Optional external review alert push via tenant-configured monitoring
            Section {
                Toggle(isOn: $vm.monitoringSettings.externalReviewAlertEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("External Review Alerts")
                            .font(.brandLabelLarge())
                        Text("Push alert when a new external review is received via monitoring webhook.")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .accessibilityLabel("External review alert push notification")
            } header: {
                Text("Monitoring")
            } footer: {
                Text("The monitoring webhook is configured on your server. iOS never calls Google, Yelp, or Facebook APIs directly.")
                    .font(.brandLabelSmall())
            }

            // §37.5 — High-score nudge thresholds (no auto-post; no discount tie)
            Section {
                Stepper(
                    "NPS nudge threshold: \(vm.monitoringSettings.nudgeMinNPSScore)+",
                    value: $vm.monitoringSettings.nudgeMinNPSScore,
                    in: 0...10
                )
                .accessibilityLabel("Minimum NPS score to trigger review nudge, currently \(vm.monitoringSettings.nudgeMinNPSScore)")

                Stepper(
                    "CSAT nudge threshold: \(vm.monitoringSettings.nudgeMinCSATScore)+ stars",
                    value: $vm.monitoringSettings.nudgeMinCSATScore,
                    in: 1...5
                )
                .accessibilityLabel("Minimum CSAT stars to trigger review nudge, currently \(vm.monitoringSettings.nudgeMinCSATScore)")
            } header: {
                Text("High-Score Nudge")
            } footer: {
                // §37.5 — Block tying reviews to discounts (Google/Yelp ToS)
                Text("After a high score, customers are gently prompted to share their experience. This nudge is never tied to a discount or reward — doing so violates Google and Yelp Terms of Service.")
                    .font(.brandLabelSmall())
            }

            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Error: \(err)")
                }
            }

            Section {
                Button {
                    Task { await vm.save() }
                } label: {
                    if vm.isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Settings")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .disabled(!vm.isValid || vm.isSaving)
                .accessibilityLabel(vm.isSaving ? "Saving" : "Save review platform settings")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .navigationTitle("Review Settings")
    }

    private func urlField(label: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent(label) {
            TextField(placeholder, text: text)
                #if canImport(UIKit)
                .keyboardType(.URL)
                #endif
                #if canImport(UIKit)
                .autocorrectionDisabled()
                #endif
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .multilineTextAlignment(.trailing)
        }
        .accessibilityLabel("\(label) URL")
    }
}
