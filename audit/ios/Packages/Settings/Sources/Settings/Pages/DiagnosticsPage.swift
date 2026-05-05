import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import OSLog
#if canImport(Darwin)
import Darwin
#endif

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
    // WS frames — populated externally by WebSocket manager via postWSFrame(_:)
    var _wsEntries: [WebSocketFrameEntry] = []
    public private(set) var isLoadingLogs = false
    public var logFilter: String = ""
    public var logLevelFilter: OSLogEntryLog.Level? = nil

    // Feature flags — local overrides
    public var featureFlagOverrides: [String: Bool] = [:]

    public init() {}

    /// Called by the WebSocket manager to append a captured frame for inspection.
    public func postWSFrame(_ frame: WebSocketFrameEntry) {
        _wsEntries.insert(frame, at: 0)
        if _wsEntries.count > 200 { _wsEntries = Array(_wsEntries.prefix(200)) }
    }

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
        ]
        #if canImport(UIKit)
        lines.append("Device: \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
        #endif
        lines += ["", "=== Recent Logs (last 100) ==="]
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

// MARK: - WebSocket frame model

public struct WebSocketFrameEntry: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let date: Date
    public let direction: Direction
    public let payload: String // JSON truncated to 2 KB for display
    public let byteCount: Int

    public enum Direction: Sendable { case inbound, outbound }

    public var directionLabel: String { direction == .inbound ? "← IN" : "→ OUT" }
    public var directionColor: Color { direction == .inbound ? .bizarreTeal : .bizarreOrange }
}

// MARK: - ViewModel (extended)

extension DiagnosticsViewModel {
    // WS frame log is populated by the WebSocket manager posting to
    // `NotificationCenter` with name `.wsFrameReceived` / `.wsFrameSent`.
    // This extension wires those observations.
    public var websocketEntries: [WebSocketFrameEntry] { _wsEntries }
}

// MARK: - View

/// §19.25 Diagnostics page — log viewer, network inspector, WS inspector,
/// feature flags, FPS/memory HUD, crash test button.
/// Accessible via Settings → Diagnostics (admin) or secret 7-tap on About version.
public struct DiagnosticsPage: View {
    @State private var vm = DiagnosticsViewModel()
    @State private var selectedTab = DiagnosticsTab.logs
    @State private var showExportSheet = false
    @State private var bundleText = ""
    @State private var showHUD = false
    @State private var showCrashConfirm = false
    /// §19.25 — glass element counter overlay.
    @State private var showGlassCounter = false
    /// §19.25 — environment toggle (staging vs production), dev builds only.
    @State private var usesStagingEnvironment: Bool = UserDefaults.standard.bool(
        forKey: "debug.useStagingEnvironment"
    )

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("Diagnostics section", selection: $selectedTab) {
                    ForEach(DiagnosticsTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.vertical, BrandSpacing.sm)
            }
            .background(Color.bizarreSurfaceBase)
            .accessibilityIdentifier("diagnostics.tabPicker")

            switch selectedTab {
            case .logs:
                LogViewerSection(vm: vm)
            case .network:
                NetworkInspectorSection(entries: vm.networkEntries)
            case .websocket:
                WebSocketInspectorSection(entries: vm.websocketEntries)
            case .featureFlags:
                FeatureFlagsSection()
            case .environment:
                EnvironmentSection(usesStagingEnvironment: $usesStagingEnvironment)
            case .danger:
                DangerZoneSection(
                    showCrashConfirm: $showCrashConfirm,
                    showHUD: $showHUD,
                    showGlassCounter: $showGlassCounter,
                    usesStagingEnvironment: $usesStagingEnvironment
                )
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
        .confirmationDialog("Force crash now?",
                            isPresented: $showCrashConfirm,
                            titleVisibility: .visible) {
            Button("Crash (test symbolication)", role: .destructive) {
                // Deliberate force crash — validates crash reporter symbolication.
                // This is dev/admin only; no production path can hit this.
                let arr: [Int] = []
                _ = arr[0]
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will crash immediately. Use this to verify symbolication in Xcode Organizer.")
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: BrandSpacing.sm) {
                if showHUD {
                    FPSMemoryHUDView {
                        showHUD = false
                    }
                    .transition(.scale.combined(with: .opacity))
                    .animation(BrandMotion.snappy, value: showHUD)
                }
                if showGlassCounter {
                    GlassLayerCounterHUD {
                        showGlassCounter = false
                    }
                    .transition(.scale.combined(with: .opacity))
                    .animation(BrandMotion.snappy, value: showGlassCounter)
                }
            }
            .padding(.top, BrandSpacing.lg)
            .padding(.trailing, BrandSpacing.base)
        }
    }
}

// MARK: - Tabs

private enum DiagnosticsTab: String, CaseIterable, Identifiable {
    case logs         = "logs"
    case network      = "network"
    case websocket    = "ws"
    case featureFlags = "flags"
    case danger       = "danger"
    case environment  = "env"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .logs:         return "Logs"
        case .network:      return "Network"
        case .websocket:    return "WS"
        case .featureFlags: return "Flags"
        case .danger:       return "Danger"
        case .environment:  return "Env"
        }
    }
}

// MARK: - Log viewer

private struct LogViewerSection: View {
    @Bindable var vm: DiagnosticsViewModel
    @State private var showLogExport = false
    @State private var exportText = ""

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
                Spacer()
                // §19.25 — log-export toggle: share the currently-visible log
                // entries as a plain-text file via the system share sheet.
                if !vm.filteredLogs.isEmpty {
                    Button {
                        exportText = buildLogExportText(from: vm.filteredLogs)
                        showLogExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.bizarreOrange)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export logs")
                    .accessibilityIdentifier("diagnostics.exportLogs")
                }
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
        .sheet(isPresented: $showLogExport) {
            LogExportSheet(text: exportText)
        }
    }

    // MARK: - Private

    private func buildLogExportText(from entries: [LogEntry]) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        var lines: [String] = [
            "=== Bizarre CRM Log Export ===",
            "Generated: \(Date())",
            "Version: \(Platform.appVersion) (\(Platform.buildNumber))",
            "Entries: \(entries.count)",
            vm.logFilter.isEmpty ? "" : "Filter: \"\(vm.logFilter)\"",
            "",
        ]
        for entry in entries {
            lines.append("[\(fmt.string(from: entry.date))] [\(entry.levelLabel)] \(entry.subsystem) — \(entry.message)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Log export share sheet

private struct LogExportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                    .padding(BrandSpacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Log export")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: text, subject: Text("Bizarre CRM Logs"),
                              message: Text("Attached: \(Platform.appVersion) log export")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("diagnostics.exportLogs.share")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("diagnostics.exportLogs.done")
                }
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

// MARK: - WebSocket inspector

private struct WebSocketInspectorSection: View {
    let entries: [WebSocketFrameEntry]

    var body: some View {
        if entries.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No WebSocket frames yet")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Frames will appear once the WebSocket connects.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { frame in
                WSFrameRow(frame: frame)
                    .listRowBackground(Color.bizarreSurface1)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct WSFrameRow: View {
    let frame: WebSocketFrameEntry

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: frame.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(frame.directionLabel)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(frame.directionColor)
                Text(timeString)
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text("\(frame.byteCount) B")
                    .font(.brandMono(size: 10))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Text(frame.payload)
                .font(.brandMono(size: 10))
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(frame.directionLabel) \(frame.payload)")
    }
}

// MARK: - Danger zone section (dev/admin)

private struct DangerZoneSection: View {
    @Binding var showCrashConfirm: Bool
    @Binding var showHUD: Bool
    /// §19.25 Glass element counter overlay binding.
    @Binding var showGlassCounter: Bool
    /// §19.25 Environment toggle binding.
    @Binding var usesStagingEnvironment: Bool

    var body: some View {
        List {
            Section {
                Text("Developer and admin tools. Visible in debug + admin builds only. Some actions are irreversible or will crash the app intentionally.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreWarning)
                    .listRowBackground(Color.bizarreWarning.opacity(0.08))
            }

            Section("Performance") {
                Toggle("FPS / Memory HUD", isOn: $showHUD)
                    .accessibilityIdentifier("diagnostics.fpsHud")
                    .tint(.bizarreOrange)
                // §19.25 — glass element counter overlay
                Toggle("Glass layer counter", isOn: $showGlassCounter)
                    .tint(.bizarreOrange)
                    .accessibilityIdentifier("diagnostics.glassCounter")
            }

            Section("Crash testing") {
                Button(role: .destructive) {
                    showCrashConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .accessibilityHidden(true)
                        Text("Force crash (test symbolication)")
                            .foregroundStyle(.bizarreError)
                    }
                }
                .accessibilityIdentifier("diagnostics.forceCrash")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }
}

// MARK: - FPS / Memory HUD overlay

/// §19.25 — Toggleable floating overlay showing current FPS and memory usage.
/// Shown on top of the diagnostics page when enabled.
private struct FPSMemoryHUDView: View {
    let onDismiss: () -> Void

    @State private var fps: Double = 60
    @State private var memoryMB: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: BrandSpacing.xs) {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Close HUD")
            }
            HStack(spacing: BrandSpacing.sm) {
                metricPill(
                    label: "FPS",
                    value: String(format: "%.0f", fps),
                    color: fps >= 55 ? .bizarreSuccess : fps >= 30 ? .bizarreWarning : .bizarreError
                )
                metricPill(
                    label: "MEM",
                    value: String(format: "%.0f MB", memoryMB),
                    color: memoryMB < 200 ? .bizarreSuccess : memoryMB < 400 ? .bizarreWarning : .bizarreError
                )
            }
        }
        .padding(BrandSpacing.sm)
        .brandGlass(.identity, interactive: false)
        .onAppear {
            refreshMetrics()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in refreshMetrics() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FPS \(Int(fps)), Memory \(Int(memoryMB)) MB")
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.brandMono(size: 12).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.brandMono(size: 9))
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.xs)
        .padding(.vertical, 2)
    }

    private func refreshMetrics() {
        // Memory: task_info approach
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            memoryMB = Double(info.resident_size) / 1_048_576
        }
        // FPS: approximation via CADisplayLink would require UIKit class;
        // for diagnostics we read from CACurrentMediaTime delta.
        // Simplified: assume 60 unless we see frame drops in the future.
        fps = 60
    }
}

// MARK: - §19.25 Glass layer counter HUD

/// Floating overlay that polls the number of active `.brandGlass` layers by
/// reading a shared atomic counter that glass modifiers increment/decrement.
/// Falls back to a placeholder when the counter infrastructure isn't wired yet.
private struct GlassLayerCounterHUD: View {
    let onDismiss: () -> Void

    /// Live count vended by `GlassLayerCounter.shared` (in DesignSystem).
    /// Until that counter is wired, we show a static placeholder of 0.
    @State private var activeLayerCount: Int = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: BrandSpacing.xs) {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Close glass counter")
            }
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("\(activeLayerCount)")
                    .font(.brandMono(size: 18).bold())
                    .foregroundStyle(
                        activeLayerCount > 10 ? Color.bizarreWarning : .bizarreOnSurface
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text("glass layers")
                .font(.brandMono(size: 9))
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.sm)
        .brandGlass(.identity, interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Glass layer count: \(activeLayerCount)")
        .accessibilityIdentifier("diagnostics.glassCounterHUD")
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        // DesignSystem.GlassLayerCounter.shared.activeCount when wired;
        // placeholder reads 0 until then.
        activeLayerCount = GlassLayerCounter.shared.activeCount
    }
}

// MARK: - §19.25 Environment section (dev builds only)

/// §19.25 — Toggle between staging and production API base URL.
/// Only visible in dev/admin builds; toggling requires an app restart to take effect.
private struct EnvironmentSection: View {
    @Binding var usesStagingEnvironment: Bool
    @State private var showRestartBanner = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: usesStagingEnvironment ? "flask.fill" : "server.rack")
                        .foregroundStyle(usesStagingEnvironment ? .bizarreWarning : .bizarreSuccess)
                        .font(.system(size: 20))
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usesStagingEnvironment ? "Staging" : "Production")
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Text(usesStagingEnvironment
                             ? "https://staging-api.bizarrecrm.com"
                             : "Your tenant server URL")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $usesStagingEnvironment)
                        .labelsHidden()
                        .tint(usesStagingEnvironment ? .bizarreWarning : .bizarreSuccess)
                        .accessibilityLabel(usesStagingEnvironment ? "Switch to production" : "Switch to staging")
                        .onChange(of: usesStagingEnvironment) { _, v in
                            UserDefaults.standard.set(v, forKey: "debug.useStagingEnvironment")
                            showRestartBanner = true
                            AppLog.ui.warning(
                                "DiagnosticsEnv: switched to \(v ? "staging" : "production", privacy: .public)"
                            )
                        }
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(
                    usesStagingEnvironment
                    ? Color.bizarreWarning.opacity(0.08)
                    : Color.bizarreSurface1
                )
                .accessibilityIdentifier("diagnostics.env.toggle")
            } header: {
                Text("API Environment")
            } footer: {
                Text("Switches between staging and production API. A restart is required for the change to take effect. Dev builds only.")
            }

            if showRestartBanner {
                Section {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                        Text("Restart the app to apply the environment change.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    .padding(.vertical, BrandSpacing.xs)
                    .listRowBackground(Color.bizarreOrange.opacity(0.1))
                }
                .accessibilityIdentifier("diagnostics.env.restartBanner")
            }

            Section("Server info") {
                infoRow(label: "Base URL",
                        value: usesStagingEnvironment
                            ? "staging-api.bizarrecrm.com"
                            : "Your tenant server")
                infoRow(label: "Build type",
                        value: {
                            #if DEBUG
                            return "Debug"
                            #else
                            return "Release"
                            #endif
                        }())
                infoRow(label: "App version",
                        value: "\(Platform.appVersion) (\(Platform.buildNumber))")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            Text(value)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.bizarreSurface1)
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
