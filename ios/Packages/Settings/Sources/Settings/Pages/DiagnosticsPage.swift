import SwiftUI
import Core
import DesignSystem

// §19 — Diagnostics page: exposes log export and sync controls to operators.

// MARK: - LogExportSheet

/// A sheet that renders the in-memory log entries and offers a ShareLink
/// so the operator can send them to support via Mail, AirDrop, etc.
public struct LogExportSheet: View {
    public let entries: [LogEntry]

    public init(entries: [LogEntry]) {
        self.entries = entries
    }

    private var logText: String {
        entries.map { "[\($0.level)] \($0.timestamp) \($0.message)" }
               .joined(separator: "\n")
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ShareLink(
                        item: logText,
                        subject: Text("BizarreCRM Diagnostic Log"),
                        message: Text("Attached diagnostic log exported from the app.")
                    ) {
                        Label("Export log", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("diagnostics.exportLog")
                }

                Section("Entries (\(entries.count))") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text(entry.message)
                                .font(.brandMono(size: 12))
                                .foregroundStyle(.bizarreOnSurface)
                                .lineLimit(3)
                            Text("[\(entry.level)] \(entry.timestamp)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .padding(.vertical, BrandSpacing.xxs)
                    }
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Log Export")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - LogEntry

/// A single structured log entry surfaced in the export sheet.
public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let level: String
    public let timestamp: String
    public let message: String

    public init(id: UUID = UUID(), level: String, timestamp: String, message: String) {
        self.id = id
        self.level = level
        self.timestamp = timestamp
        self.message = message
    }
}

// MARK: - DiagnosticsPage

/// §19 — Top-level diagnostics page that hosts sync controls and log export.
public struct DiagnosticsPage: View {
    @State private var showLogExport = false
    @State private var logEntries: [LogEntry] = []

    public init() {}

    public var body: some View {
        List {
            Section("Sync") {
                Button("Clear Cache") {
                    NotificationCenter.default.post(name: .clearCacheRequested, object: nil)
                }
                .accessibilityIdentifier("diagnostics.clearCache")

                Button("Force Full Sync") {
                    NotificationCenter.default.post(name: .forceFullSyncRequested, object: nil)
                }
                .accessibilityIdentifier("diagnostics.forceFullSync")
            }

            Section("Logs") {
                Button("Export Logs…") {
                    showLogExport = true
                }
                .accessibilityIdentifier("diagnostics.showLogExport")
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .sheet(isPresented: $showLogExport) {
            LogExportSheet(entries: logEntries)
        }
    }
}
