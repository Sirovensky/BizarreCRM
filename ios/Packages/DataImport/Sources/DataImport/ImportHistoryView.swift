import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ImportHistoryViewModel

@MainActor
@Observable
public final class ImportHistoryViewModel {
    public private(set) var jobs: [ImportJob] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repository: ImportRepository

    public init(repository: ImportRepository) {
        self.repository = repository
    }

    public func load() async {
        if jobs.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            jobs = try await repository.listJobs()
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("Import history load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - ImportHistoryView

public struct ImportHistoryView: View {
    @State private var vm: ImportHistoryViewModel

    public init(repository: ImportRepository) {
        _vm = State(wrappedValue: ImportHistoryViewModel(repository: repository))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var compactLayout: some View {
        NavigationStack {
            content
                .navigationTitle("Import History")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await vm.load() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh import history")
                    }
                }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            content
                .navigationTitle("Import History")
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            VStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 52))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Select an import")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            if vm.isLoading {
                ProgressView()
            } else if let err = vm.errorMessage {
                errorView(err)
            } else if vm.jobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load history")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(DesignTokens.Spacing.lg)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No imports yet")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Your import history will appear here")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var jobList: some View {
        List(vm.jobs) { job in
            JobRow(job: job)
                .listRowBackground(Color.bizarreSurface1)
            #if canImport(UIKit)
                .hoverEffect(.highlight)
            #endif
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }
}

// MARK: - JobRow

private struct JobRow: View {
    let job: ImportJob

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(job.source.displayName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    statusBadge
                }
                Text(Self.dateFormatter.string(from: job.createdAt))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let total = job.totalRows {
                    Text("\(job.processedRows) / \(total) rows · \(job.errorCount) errors")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var statusBadge: some View {
        Text(job.status.rawValue.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(statusColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(statusColor.opacity(0.15), in: Capsule())
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return .bizarreSuccess
        case .failed:    return .bizarreError
        case .running:   return .bizarreOrange
        default:         return .bizarreOnSurfaceMuted
        }
    }

    private var a11yLabel: String {
        var parts = [job.source.displayName, job.status.rawValue]
        if let total = job.totalRows {
            parts.append("\(job.processedRows) of \(total) rows")
        }
        parts.append(Self.dateFormatter.string(from: job.createdAt))
        return parts.joined(separator: ". ")
    }
}
