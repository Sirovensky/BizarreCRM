import SwiftUI

// §32.5 Crash recovery pipeline — Admin settings view
// Phase 11

/// Settings entry for crash reporting opt-in.
///
/// Admin-only: "Enable automatic crash reporting" toggle.
/// State persisted in `UserDefaults` under `CrashReportingDefaults.enabledKey`.
@Observable
public final class CrashReportingSettingsViewModel {

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: CrashReportingDefaults.enabledKey)
        }
    }

    public init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: CrashReportingDefaults.enabledKey)
    }
}

/// Admin settings view for crash reporting.
///
/// Shown in the Settings → Admin section. Respects Dynamic Type and VoiceOver.
public struct CrashReportingSettingsView: View {

    @State private var viewModel = CrashReportingSettingsViewModel()

    public init() {}

    public var body: some View {
        @Bindable var vm = viewModel
        return Form {
            Section {
                Toggle(isOn: $vm.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Crash Reporting")
                            .font(.body)
                        Text("Send anonymised diagnostics to your server when the app crashes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("Automatic crash reporting")
                .accessibilityHint(
                    viewModel.isEnabled
                        ? "Enabled. Tap to disable crash reporting."
                        : "Disabled. Tap to enable crash reporting."
                )
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Reports are sent only to your own server. No data leaves your infrastructure.")
                    .font(.caption)
            }
        }
        .navigationTitle("Crash Reporting")
    }
}

