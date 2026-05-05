import SwiftUI

// §32.5 Crash recovery pipeline — Developer debug console
// Phase 11
//
// Entire view is compiled only in DEBUG builds.

#if DEBUG

/// Developer-only console showing recent breadcrumbs and the last crash diagnostic.
///
/// Gated by `#if DEBUG`. Not compiled into production builds.
/// Access via Settings → Developer → Crash Console.
public struct CrashConsoleView: View {

    @State private var breadcrumbs: [Breadcrumb] = []
    @State private var isExporting = false
    @State private var exportText = ""

    private let store: BreadcrumbStore

    public init(store: BreadcrumbStore = .shared) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            List {
                // MARK: — Breadcrumbs section
                Section("Recent Breadcrumbs (\(breadcrumbs.count))") {
                    if breadcrumbs.isEmpty {
                        Text("No breadcrumbs recorded yet.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(breadcrumbs.reversed(), id: \.timestamp) { crumb in
                            BreadcrumbRow(crumb: crumb)
                        }
                    }
                }

                // MARK: — Crash flag section
                Section("Session State") {
                    LabeledContent("Prior crash detected") {
                        Text(CrashRecovery.shared.willRestartAfterCrash ? "YES" : "NO")
                            .foregroundStyle(
                                CrashRecovery.shared.willRestartAfterCrash ? .red : .green
                            )
                            .bold()
                    }
                    .accessibilityLabel("Prior crash detected: \(CrashRecovery.shared.willRestartAfterCrash ? "Yes" : "No")")
                }

                // MARK: — Actions section
                Section("Actions") {
                    Button("Export Diagnostics as Text") {
                        exportText = buildExportText()
                        isExporting = true
                    }
                    .accessibilityLabel("Export diagnostics as text file")

                    Button("Clear Breadcrumbs", role: .destructive) {
                        Task {
                            await store.clear()
                            breadcrumbs = []
                        }
                    }
                    .accessibilityLabel("Clear all breadcrumbs")
                }
            }
            .navigationTitle("Crash Console")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh breadcrumbs")
                }
            }
            .task { await reload() }
            .sheet(isPresented: $isExporting) {
                ExportSheet(text: exportText)
            }
        }
    }

    // MARK: — Private

    private func reload() async {
        breadcrumbs = await store.recent()
    }

    private func buildExportText() -> String {
        var lines: [String] = [
            "BizarreCRM Crash Console Export",
            "Generated: \(Date())",
            "Prior crash flag: \(CrashRecovery.shared.willRestartAfterCrash)",
            "",
            "=== Breadcrumbs ===",
        ]
        for crumb in breadcrumbs {
            lines.append("[\(crumb.timestamp)] [\(crumb.level.rawValue.uppercased())] [\(crumb.category)] \(crumb.message)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: — Sub-views

private struct BreadcrumbRow: View {
    let crumb: Breadcrumb

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(crumb.category)
                    .font(.caption.bold())
                    .foregroundStyle(levelColor(crumb.level))
                Spacer()
                Text(Self.formatter.string(from: crumb.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(crumb.message)
                .font(.caption)
                .lineLimit(3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(crumb.category): \(crumb.message) at \(Self.formatter.string(from: crumb.timestamp))")
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug:    return .secondary
        case .info:     return .primary
        case .notice:   return .blue
        case .warning:  return .orange
        case .error:    return .red
        case .critical: return .purple
        }
    }
}

private struct ExportSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .padding()
                    .textSelection(.enabled)
                    .accessibilityLabel("Exported diagnostics text")
            }
            .navigationTitle("Diagnostics Export")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share diagnostics export")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close export sheet")
                }
            }
        }
    }
}

#endif // DEBUG
