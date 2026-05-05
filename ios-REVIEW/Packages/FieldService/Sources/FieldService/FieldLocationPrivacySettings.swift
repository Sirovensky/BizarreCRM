// §57.3 FieldLocationPrivacySettings
//
// "Settings → Privacy → Location shows what's tracked + toggle + history
// export + delete history." — ActionPlan §57.
//
// All location data flows only to the tenant server (never to third-parties,
// per §32 sovereignty rule). This view surfaces that policy to the user.

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ViewModel

@MainActor
@Observable
public final class FieldLocationPrivacyViewModel {
    /// Whether background location tracking is enabled by the user.
    /// Persisted in UserDefaults under `field.location.trackingEnabled`.
    public var trackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: kTrackingKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: kTrackingKey)
            AppLog.ui.info("Field location tracking \(newValue ? "enabled" : "disabled", privacy: .public)")
        }
    }

    public private(set) var historyEntries: [FieldLocationHistoryEntry] = []
    public private(set) var isLoadingHistory: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didDeleteHistory: Bool = false
    public private(set) var isExporting: Bool = false
    public private(set) var exportURL: URL?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let kTrackingKey = "field.location.trackingEnabled"

    public init(api: APIClient) {
        self.api = api
        // Default tracking to true for field-service users who opted into the feature.
        if UserDefaults.standard.object(forKey: "field.location.trackingEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "field.location.trackingEnabled")
        }
    }

    // MARK: - Load history

    public func loadHistory() async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        errorMessage = nil
        defer { isLoadingHistory = false }
        do {
            historyEntries = try await api.listFieldLocationHistory()
        } catch {
            AppLog.ui.error("Location history load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete history

    public func deleteHistory() async {
        do {
            try await api.deleteFieldLocationHistory()
            historyEntries = []
            didDeleteHistory = true
            AppLog.ui.info("Field location history deleted")
        } catch {
            AppLog.ui.error("Location history delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export history as CSV

    public func exportHistoryCSV() async {
        guard !historyEntries.isEmpty else { return }
        isExporting = true
        defer { isExporting = false }
        let csv = FieldLocationPrivacyViewModel.buildCSV(entries: historyEntries)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("location_history_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: tmp, atomically: true, encoding: .utf8)
            exportURL = tmp
        } catch {
            AppLog.ui.error("Location history CSV export failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - CSV builder (pure)

    static func buildCSV(entries: [FieldLocationHistoryEntry]) -> String {
        var lines = ["timestamp,latitude,longitude,accuracy_m,job_id"]
        for e in entries {
            let jobId = e.jobId.map { "\($0)" } ?? ""
            lines.append("\(e.timestamp),\(e.latitude),\(e.longitude),\(e.accuracyMeters),\(jobId)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Model

public struct FieldLocationHistoryEntry: Codable, Sendable, Identifiable {
    public let id: Int64
    public let timestamp: String
    public let latitude: Double
    public let longitude: Double
    public let accuracyMeters: Double
    public let jobId: Int64?

    public init(id: Int64, timestamp: String, latitude: Double, longitude: Double, accuracyMeters: Double, jobId: Int64? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.jobId = jobId
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, latitude, longitude
        case accuracyMeters = "accuracy_m"
        case jobId = "job_id"
    }
}

// MARK: - API stub extensions (wired to server tenant route)

extension APIClient {
    /// `GET /api/v1/field-service/location-history` — returns tracked points.
    func listFieldLocationHistory() async throws -> [FieldLocationHistoryEntry] {
        try await get("/api/v1/field-service/location-history", as: [FieldLocationHistoryEntry].self)
    }

    /// `DELETE /api/v1/field-service/location-history` — purge all history for current user.
    func deleteFieldLocationHistory() async throws {
        try await delete("/api/v1/field-service/location-history")
    }
}

// MARK: - View

public struct FieldLocationPrivacySettingsView: View {
    @State private var vm: FieldLocationPrivacyViewModel
    @State private var showDeleteConfirm: Bool = false
    @State private var showExportSheet: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: FieldLocationPrivacyViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if Platform.isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
        }
        .navigationTitle("Location Privacy")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.loadHistory() }
        .confirmationDialog(
            "Delete location history?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { Task { await vm.deleteHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all recorded location points from the server. This cannot be undone.")
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = vm.exportURL {
                ShareSheet(url: url)
            }
        }
        .onChange(of: vm.exportURL) { _, url in
            if url != nil { showExportSheet = true }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { _ in }
        )) {
            Button("OK") { }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - iPhone layout

    private var compactLayout: some View {
        List {
            policySection
            toggleSection
            historySection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - iPad layout

    private var regularLayout: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                policyCard
                toggleCard
                historyCard
                actionsCard
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Policy section

    private var policySection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                Label("What we track", systemImage: "location.circle")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
                Text("When field-service mode is active, your GPS position is recorded during jobs and sent only to your shop's server. Location data is never shared with third parties.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xs)
        } header: {
            Text("Privacy Policy")
        }
        .accessibilityElement(children: .combine)
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Label("What we track", systemImage: "location.circle")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityAddTraits(.isHeader)
            Text("When field-service mode is active, your GPS position is recorded during jobs and sent only to your shop's server. Location data is never shared with third parties.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - Toggle section

    private var toggleSection: some View {
        Section("Tracking") {
            Toggle(isOn: Binding(
                get: { vm.trackingEnabled },
                set: { vm.trackingEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Background location tracking")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Records position during active jobs")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Background location tracking: \(vm.trackingEnabled ? "on" : "off")")
        }
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Tracking").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted).tracking(0.8)
            Toggle(isOn: Binding(
                get: { vm.trackingEnabled },
                set: { vm.trackingEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Background location tracking")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Records position during active jobs")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Background location tracking: \(vm.trackingEnabled ? "on" : "off")")
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    // MARK: - History section

    private var historySection: some View {
        Section("Recorded Points (\(vm.historyEntries.count))") {
            if vm.isLoadingHistory {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Loading location history")
            } else if vm.historyEntries.isEmpty {
                Text("No location history recorded.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("No location history recorded")
            } else {
                ForEach(vm.historyEntries.prefix(10)) { entry in
                    historyRow(entry)
                }
                if vm.historyEntries.count > 10 {
                    Text("…and \(vm.historyEntries.count - 10) more")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("and \(vm.historyEntries.count - 10) more entries")
                }
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Recorded Points (\(vm.historyEntries.count))")
                .font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted).tracking(0.8)
                .accessibilityAddTraits(.isHeader)
            if vm.isLoadingHistory {
                ProgressView().frame(maxWidth: .infinity).accessibilityLabel("Loading location history")
            } else if vm.historyEntries.isEmpty {
                Text("No location history recorded.")
                    .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(vm.historyEntries.prefix(10)) { entry in historyRow(entry) }
                if vm.historyEntries.count > 10 {
                    Text("…and \(vm.historyEntries.count - 10) more")
                        .font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
    }

    private func historyRow(_ entry: FieldLocationHistoryEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.timestamp)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(String(format: "%.4f, %.4f (±%.0fm)", entry.latitude, entry.longitude, entry.accuracyMeters))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
            if let jobId = entry.jobId {
                Text("Job #\(jobId)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.timestamp), \(String(format: "%.4f longitude %.4f", entry.latitude, entry.longitude)), accuracy \(Int(entry.accuracyMeters)) metres\(entry.jobId.map { ", job \($0)" } ?? "")")
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        Section {
            Button {
                Task { await vm.exportHistoryCSV() }
            } label: {
                Label(vm.isExporting ? "Exporting…" : "Export History (CSV)", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.bizarreOrange)
            }
            .disabled(vm.historyEntries.isEmpty || vm.isExporting)
            .accessibilityLabel("Export location history as CSV")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Location History", systemImage: "trash")
            }
            .disabled(vm.historyEntries.isEmpty)
            .accessibilityLabel("Delete all location history")
        }
    }

    private var actionsCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            Button {
                Task { await vm.exportHistoryCSV() }
            } label: {
                Label(vm.isExporting ? "Exporting…" : "Export History (CSV)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(vm.historyEntries.isEmpty || vm.isExporting)
            .accessibilityLabel("Export location history as CSV")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Location History", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreError)
            .disabled(vm.historyEntries.isEmpty)
            .accessibilityLabel("Delete all location history")
        }
    }
}

// MARK: - ShareSheet helper (UIActivityViewController bridge)

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
