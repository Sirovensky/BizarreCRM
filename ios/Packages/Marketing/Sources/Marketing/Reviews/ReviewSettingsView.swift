import SwiftUI
import DesignSystem
import Networking

// MARK: - ReviewSettingsViewModel

@Observable
@MainActor
public final class ReviewSettingsViewModel {
    public var googleURL: String = ""
    public var yelpURL: String = ""
    public var facebookURL: String = ""
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
        isValidURLOrEmpty(facebookURL)
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
            _ = try await api.post("settings/review-platforms", body: settings, as: ReviewPlatformSettings.self)
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

/// Admin: configure platforms (Google Business URL, Yelp URL, Facebook URL).
public struct ReviewSettingsView: View {
    @State private var vm: ReviewSettingsViewModel

    public init(api: APIClient, existing: ReviewPlatformSettings? = nil) {
        _vm = State(initialValue: ReviewSettingsViewModel(api: api, existing: existing))
    }

    public var body: some View {
        Form {
            Section {
                urlField(label: "Google Business URL", text: $vm.googleURL, placeholder: "https://g.page/your-business")
                urlField(label: "Yelp URL", text: $vm.yelpURL, placeholder: "https://www.yelp.com/biz/your-business")
                urlField(label: "Facebook URL", text: $vm.facebookURL, placeholder: "https://www.facebook.com/your-page")
            } header: {
                Text("Review Platforms")
            } footer: {
                Text("Leave blank to skip a platform. URLs must be https.")
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
                        Text("Save Platforms")
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
