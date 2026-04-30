import SwiftUI
import Core
import DesignSystem
import Networking

// §28.13 GDPR Compliance — data-export request UI
//
// Surface: Settings → Privacy → "Request my data"
// Sends POST /exports/personal-data-request; server emails the user a
// download link when the archive is ready (may take minutes).
// Rate-limited to once per 24 h on the server; we surface that as a
// "last requested" timestamp.

// MARK: - ViewModel

@Observable
@MainActor
public final class DataExportRequestViewModel {

    // MARK: State

    public private(set) var isRequesting: Bool = false
    public private(set) var lastRequestedAt: Date? = nil
    public private(set) var errorMessage: String? = nil
    public private(set) var successMessage: String? = nil

    // MARK: Dependencies

    private let api: APIClient?
    private let defaults: UserDefaults

    private static let lastRequestedKey = "gdpr.dataExportRequest.lastRequestedAt"

    public init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        if let ts = defaults.object(forKey: Self.lastRequestedKey) as? Date {
            self.lastRequestedAt = ts
        }
    }

    // MARK: Computed

    /// Returns `true` if the last request was within the past 24 h.
    public var isCoolingDown: Bool {
        guard let last = lastRequestedAt else { return false }
        return Date().timeIntervalSince(last) < 24 * 60 * 60
    }

    /// Human-readable cooldown description shown in the footer.
    public var cooldownDescription: String {
        guard let last = lastRequestedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last requested \(formatter.localizedString(for: last, relativeTo: Date()))."
    }

    // MARK: Actions

    public func requestExport() async {
        guard !isCoolingDown else {
            errorMessage = "You can request your data once every 24 hours."
            return
        }
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }

        do {
            try await api?.requestPersonalDataExport()
            let now = Date()
            lastRequestedAt = now
            defaults.set(now, forKey: Self.lastRequestedKey)
            successMessage = "Export requested. You'll receive an email when your archive is ready."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}

// MARK: - API extension

private struct _ExportEmptyBody: Encodable {}
private struct _ExportEmptyResponse: Decodable {}

private extension APIClient {
    func requestPersonalDataExport() async throws {
        _ = try await post(
            "/exports/personal-data-request",
            body: _ExportEmptyBody(),
            as: _ExportEmptyResponse.self
        )
    }
}

// MARK: - View

/// Settings → Privacy → "Request my data"
///
/// Triggers a GDPR/CCPA personal data export. The server emails the user a
/// download link when the archive is ready.
public struct DataExportRequestView: View {

    @State private var vm: DataExportRequestViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: DataExportRequestViewModel(api: api))
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Request a copy of your data", systemImage: "person.crop.circle.badge.arrow.down")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Text("We'll prepare an archive of all personal data we hold for your account and email you a secure download link when it's ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                if vm.isCoolingDown {
                    Text(vm.cooldownDescription)
                } else {
                    Text("Requests may take up to 24 hours to process. You will receive an email at your account address when the archive is ready.")
                }
            }

            Section {
                Button {
                    Task { await vm.requestExport() }
                } label: {
                    if vm.isRequesting {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Requesting…")
                        }
                    } else {
                        Label(
                            vm.isCoolingDown ? "Export already requested" : "Request my data",
                            systemImage: "arrow.down.circle"
                        )
                    }
                }
                .disabled(vm.isRequesting || vm.isCoolingDown)
                .accessibilityLabel(
                    vm.isCoolingDown
                        ? "Export already requested. \(vm.cooldownDescription)"
                        : "Request a personal data export"
                )
                .accessibilityHint(
                    vm.isCoolingDown
                        ? "Available again in 24 hours"
                        : "Sends a request to your business's server. You will receive an email when the archive is ready."
                )
                .accessibilityIdentifier("privacy.requestDataExport")
            } header: {
                Text("GDPR / CCPA")
            } footer: {
                Text("Under GDPR Article 20 and CCPA §1798.100, you have the right to a portable copy of your personal data.")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Request My Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.clearMessages() } }
        )) {
            Button("OK") { vm.clearMessages() }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .alert("Request Sent", isPresented: Binding(
            get: { vm.successMessage != nil },
            set: { if !$0 { vm.clearMessages() } }
        )) {
            Button("OK") { vm.clearMessages() }
        } message: {
            Text(vm.successMessage ?? "")
        }
    }
}
