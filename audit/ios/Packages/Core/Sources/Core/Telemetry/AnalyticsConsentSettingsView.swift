#if canImport(UIKit)
import SwiftUI

// §71 Privacy-first analytics — Settings → Privacy consent view

// MARK: — AnalyticsConsentSettingsView

/// Settings → Privacy → "Share usage analytics"
///
/// - Default is off (opt-out).
/// - "View what's shared" links to `AnalyticsSchemaView`.
/// - "Delete my analytics" triggers GDPR right-to-erasure via API.
public struct AnalyticsConsentSettingsView: View {

    @State private var consentManager = AnalyticsConsentManager()
    @State private var showingSchema = false
    @State private var showingDeleteConfirm = false
    @State private var isDeletingData = false
    @State private var deleteError: String? = nil

    public init() {}

    public var body: some View {
        List {
            toggleSection
            infoSection
            gdprSection
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSchema) {
            NavigationStack {
                AnalyticsSchemaView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSchema = false }
                        }
                    }
            }
        }
        .confirmationDialog(
            "Delete Analytics Data",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete My Data", role: .destructive) {
                Task { await deleteAnalyticsData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends a deletion request to your business's server. Data already aggregated may not be recoverable.")
        }
        .alert("Deletion Failed", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    // MARK: — Sections

    private var toggleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { consentManager.isOptedIn },
                set: { newValue in
                    if newValue { consentManager.optIn() } else { consentManager.optOut() }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share usage analytics")
                        .font(.body)
                    Text("Help us improve by sharing anonymized usage patterns. No personal data sent. You can opt out any time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Share usage analytics")
            .accessibilityHint(
                consentManager.isOptedIn
                    ? "Currently on. Toggle to opt out."
                    : "Currently off. Toggle to opt in."
            )
        }
    }

    private var infoSection: some View {
        Section {
            Button {
                showingSchema = true
            } label: {
                Label("View what's shared", systemImage: "list.bullet.rectangle")
                    .accessibilityLabel("View what data is shared")
            }
            .accessibilityHint("Opens a list of every analytics event and its properties")
        }
    }

    private var gdprSection: some View {
        Section(footer: Text("You have the right to request deletion of analytics data under GDPR and CCPA.")) {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                if isDeletingData {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Sending deletion request…")
                    }
                } else {
                    Label("Delete my analytics", systemImage: "trash")
                        .accessibilityLabel("Delete my analytics data")
                        .accessibilityHint("Sends a data erasure request to your business server")
                }
            }
            .disabled(isDeletingData)
        }
    }

    // MARK: — Actions

    @MainActor
    private func deleteAnalyticsData() async {
        isDeletingData = true
        deleteError = nil
        defer { isDeletingData = false }

        // POST /analytics/delete-my-data via the shared APIClient
        // The actual network call is made through Analytics.requestErasure() which
        // the App module wires at startup. Here we call it via notification to avoid
        // importing Networking inside Core.
        NotificationCenter.default.post(
            name: .analyticsDeleteMyDataRequested,
            object: nil
        )
    }
}

// MARK: — Notification name

public extension Notification.Name {
    /// Posted when the user taps "Delete my analytics". The host app observes
    /// this and calls `POST /analytics/delete-my-data`.
    static let analyticsDeleteMyDataRequested = Notification.Name("com.bizarrecrm.analytics.deleteMyDataRequested")
}

// MARK: — Environment key
// (Removed — use `@Environment(AnalyticsConsentManager.self)` via @Observable.)
#endif
