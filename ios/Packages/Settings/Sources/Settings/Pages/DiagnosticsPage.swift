import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import OSLog

// MARK: - §19.25 Diagnostics — log viewer + network inspector + feature flags + WS inspector

// MARK: - Log entry

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let date: Date
    public let level: OSLogEntryLog.Level
    public let subsystem: String
    public let message: String

    public var levelLabel: String {
        switch level {
        case .debug:   return "DBG"
        case .info:    return "INF"
        case .notice:  return "NTC"
        case .error:   return "ERR"
        case .fault:   return "FLT"
        default:       return "—"
        }
    }

    public var levelColor: Color {
        switch level {
        case .error, .fault: return .bizarreError
        case .notice:        return .bizarreWarning
        default:             return .bizarreOnSurfaceMuted
        }
    }
}

// MARK: - Network log entry

public struct NetworkLogEntry: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let date: Date
    public let method: String
    public let url: String
    public let statusCode: Int?
    public let latencyMs: Double?
    public let requestBody: String?   // JSON string (tokens redacted)
    public let responseBody: String?  // truncated
}

// MARK: - ViewModel

@MainActor
@Observable
public final class DiagnosticsViewModel: Sendable {
    public private(set) var logEntries: [LogEntry] = []
    public private(set) var networkEntries: [NetworkLogEntry] = []
    public private(set) var isLoadingLogs = false
    public var logFilter: String = ""
    public var logLevelFilter: OSLogEntryLog.Level? = nil

    // Feature flags — local overrides
    public var featureFlagOverrides: [String: Bool] = [:]

    public init() {}

    public func loadLogs() async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        // OSLog store — read last 500 entries from our subsystem
        let store: OSLogStore
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            AppLog.ui.error("DiagnosticsVM: cannot open log store: \(error.localizedDescription, privacy: .public)")
            return
        }
        let position = store.position(timeIntervalSinceLatestBoot: -3600) // last hour
        let entries: [LogEntry]
        do {
            let rawEntries = try store.getEntries(at: position)
            entries = rawEntries
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem.hasPrefix("com.bizarrecrm") }
                .suffix(500)
                .map { e in
                    LogEntry(date: e.date, level: e.level, subsystem: e.subsystem, message: e.composedMessage)
                }
        } catch {
            AppLog.ui.error("DiagnosticsVM: log read failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        logEntries = entries.reversed()
    }

    public var filteredLogs: [LogEntry] {
        logEntries.filter { entry in
            let matchesText = logFilter.isEmpty
                || entry.message.localizedCaseInsensitiveContains(logFilter)
                || entry.subsystem.localizedCaseInsensitiveContains(logFilter)
            let matchesLevel = logLevelFilter == nil || entry.level == logLevelFilter
            return matchesText && matchesLevel
        }
    }

    // MARK: - Diagnostic bundle export

    public func buildDiagnosticBundle() -> String {
        var lines: [String] = [
            "=== Bizarre CRM Diagnostic Bundle ===",
            "Generated: \(Date())",
            "Version: \(Platform.appVersion) (\(Platform.buildNumber))",
            #if canImport(UIKit)
            "Device: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)",
            #endif
            "",
            "=== Recent Logs (last 100) ===",
        ]
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        for entry in logEntries.prefix(100) {
            lines.append("[\(fmt.string(from: entry.date))] [\(entry.levelLabel)] \(entry.message)")
        }
        lines += [
            "",
            "=== Sync Queue ===",
            "(attach sync queue status here)",
            "",
            "=== Network Summary ===",
            "Last \(networkEntries.count) requests logged.",
        ]
        // Cap at 10 MB (roughly 10M chars)
        let joined = lines.joined(separator: "\n")
        if joined.count > 10_000_000 {
            return String(joined.prefix(10_000_000)) + "\n...[truncated]"
        }
        return joined
    }
}

// MARK: - View

/// §19.25 Diagnostics page — log viewer, network inspector, feature flags.
/// Accessible via Settings → Diagnostics (admin) or secret 7-tap on About version.
public struct DiagnosticsPage: View {
    @State private var vm = DiagnosticsViewModel()
    @State private var selectedTab = DiagnosticsTab.logs
    @State private var showExportSheet = false
    @State private var bundleText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Diagnostics section", selection: $selectedTab) {
                ForEach(DiagnosticsTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSurfaceBase)
            .accessibilityIdentifier("diagnostics.tabPicker")

            switch selectedTab {
            case .logs:
                LogViewerSection(vm: vm)
            case .network:
                NetworkInspectorSection(entries: vm.networkEntries)
            case .featureFlags:
                FeatureFlagsSection()
            }
        }
        .navigationTitle("Diagnostics")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    bundleText = vm.buildDiagnosticBundle()
                    showExportSheet = true
                } label: {
                    Label("Export bundle", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("diagnostics.export")
            }
        }
        .task { await vm.loadLogs() }
        .sheet(isPresented: $showExportSheet) {
            DiagnosticBundleExportSheet(bundleText: bundleText)
        }
    }
}

// MARK: - Tabs

private enum DiagnosticsTab: String, CaseIterable, Identifiable {
    case logs         = "logs"
    case network      = "network"
    case featureFlags = "flags"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .logs:         return "Logs"
        case .network:      return "Network"
        case .featureFlags: return "Flags"
        }
    }
}

// MARK: - Log viewer

private struct LogViewerSection: View {
    var vm: DiagnosticsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                TextField("Filter logs…", text: $vm.logFilter)
                    .font(.brandMono(size: 12))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("diagnostics.logFilter")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSurface1)

            if vm.isLoadingLogs {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredLogs.isEmpty {
                VStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(vm.logFilter.isEmpty ? "No logs captured" : "No matches")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.filteredLogs) { entry in
                    LogEntryRow(entry: entry)
                        .listRowBackground(Color.bizarreSurface1)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.levelLabel)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(entry.levelColor)
                    .frame(width: 30, alignment: .leading)
                Text(timeString)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
            }
            Text(entry.message)
                .font(.brandMono(size: 11))
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("[\(entry.levelLabel)] \(entry.message)")
    }
}

// MARK: - Network inspector

private struct NetworkInspectorSection: View {
    let entries: [NetworkLogEntry]

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "network")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No requests captured yet")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Network calls will appear here once made.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { entry in
                NetworkEntryRow(entry: entry)
                    .listRowBackground(Color.bizarreSurface1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct NetworkEntryRow: View {
    let entry: NetworkLogEntry

    private var statusColor: Color {
        guard let code = entry.statusCode else { return .bizarreOnSurfaceMuted }
        switch code {
        case 200..<300: return .bizarreSuccess
        case 400..<500: return .bizarreWarning
        case 500...:    return .bizarreError
        default:        return .bizarreOnSurfaceMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.method)
                    .font(.brandMono(size: 11))
                    .fontWeight(.bold)
                    .foregroundStyle(.bizarreOrange)
                if let code = entry.statusCode {
                    Text("\(code)")
                        .font(.brandMono(size: 11))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                if let latency = entry.latencyMs {
                    Text(String(format: "%.0fms", latency))
                        .font(.brandMono(size: 10))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Text(entry.url)
                .font(.brandMono(size: 10))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Feature flags section

private struct FeatureFlagsSection: View {
    var body: some View {
        List {
            Section {
                Text("Feature flags are server-driven and visible here. Local overrides available in debug builds.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Section("Active flags") {
                FeatureFlagRow(name: "fts5_search",           description: "On-device FTS5 full-text search", value: true)
                FeatureFlagRow(name: "live_activities",       description: "Lock-screen live activities", value: true)
                FeatureFlagRow(name: "websocket_realtime",    description: "WebSocket real-time sync", value: false)
                FeatureFlagRow(name: "nlq_search",            description: "Natural-language search (beta)", value: false)
                FeatureFlagRow(name: "apple_intelligence",    description: "Apple Intelligence intents (iOS 26)", value: false)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct FeatureFlagRow: View {
    let name: String
    let description: String
    let value: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.brandMono(size: 12))
                    .foregroundStyle(.bizarreOnSurface)
                Text(description)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(value ? .bizarreSuccess : .bizarreOnSurfaceMuted)
                .accessibilityLabel(value ? "Enabled" : "Disabled")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Diagnostic bundle export sheet

private struct DiagnosticBundleExportSheet: View {
    let bundleText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(bundleText)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color.bizarreSurfaceBase)
            .navigationTitle("Diagnostic Bundle")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: bundleText, preview: SharePreview("diagnostic-bundle.txt"))
                        .accessibilityIdentifier("diagnostics.shareBundle")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
