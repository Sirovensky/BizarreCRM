import SwiftUI
import DesignSystem

// MARK: - ExportDetailInspector

/// iPad detail/inspector panel for a single export job.
/// Shows: entity list + format badge + animated progress ring + share/download buttons.
///
/// Layout: placed in the trailing column (`NavigationSplitView` detail) or
/// as a trailing inspector sheet on iPad.
public struct ExportDetailInspector: View {

    public let job: TenantExportJob
    public let entity: ExportEntity
    public let format: ExportFormat
    public let onDownload: () -> Void
    public let onShare: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        job: TenantExportJob,
        entity: ExportEntity,
        format: ExportFormat,
        onDownload: @escaping () -> Void,
        onShare: @escaping (URL) -> Void
    ) {
        self.job = job
        self.entity = entity
        self.format = format
        self.onDownload = onDownload
        self.onShare = onShare
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                progressRingSection
                entityFormatSection
                metadataSection
                actionSection
            }
            .padding(DesignTokens.Spacing.xxl)
        }
        .navigationTitle("Export Details")
        .exportInlineTitleMode()
        .exportToolbarBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export detail inspector")
    }

    // MARK: - Progress ring

    private var progressRingSection: some View {
        HStack {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: job.status.progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.smooth), value: job.status.progress)

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text("\(Int(job.status.progress * 100))%")
                        .font(.title2.bold().monospacedDigit())
                        .accessibilityHidden(true)
                    Text(job.status.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityLabel("Progress: \(Int(job.status.progress * 100)) percent, \(job.status.displayLabel)")
            .accessibilityAddTraits(.updatesFrequently)
            Spacer()
        }
    }

    // MARK: - Entity + Format

    private var entityFormatSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Export Contents")

            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: entity.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: DesignTokens.Spacing.xl)
                Text(entity.displayName)
                    .font(.body)
                Spacer()
                BrandGlassBadge(format.displayName, variant: .regular)
            }
            .padding(DesignTokens.Spacing.md)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Details")

            VStack(spacing: 0) {
                if let startedAt = job.startedAt {
                    metadataRow(label: "Started", value: formatISO(startedAt))
                    Divider().padding(.leading, DesignTokens.Spacing.lg)
                }
                if let completedAt = job.completedAt {
                    metadataRow(label: "Completed", value: formatISO(completedAt))
                    Divider().padding(.leading, DesignTokens.Spacing.lg)
                }
                if let byteSize = job.byteSize {
                    metadataRow(
                        label: "File size",
                        value: ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
                    )
                    Divider().padding(.leading, DesignTokens.Spacing.lg)
                }
                metadataRow(label: "Job ID", value: "#\(job.id)")
                    .textSelection(.enabled)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionSection: some View {
        if job.status == .completed, let urlString = job.downloadUrl, let url = URL(string: urlString) {
            BrandGlassContainer(spacing: DesignTokens.Spacing.sm) {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Button {
                        onDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(Color.accentColor)
                    .keyboardShortcut("d", modifiers: [.command])
                    .accessibilityLabel("Download export file")

                    Button {
                        onShare(url)
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlass)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .accessibilityLabel("Share export file")
                }
            }
        } else if let errorMessage = job.errorMessage {
            errorBanner(errorMessage)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .accessibilityLabel("Error: \(message)")
    }

    private var ringColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed:    return .red
        default:         return Color.accentColor
        }
    }

    private func formatISO(_ isoString: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = f.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        f.formatOptions = [.withInternetDateTime]
        if let date = f.date(from: isoString) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return isoString
    }
}

// MARK: - ExportDetailInspector.Scheduled

/// Variant for a scheduled export row — shows schedule metadata instead of job progress.
public struct ScheduledExportDetailInspector: View {

    public let schedule: ExportSchedule
    public let recentRuns: [ScheduleRun]
    public let onPause: () -> Void
    public let onResume: () -> Void
    public let onCancel: () -> Void

    public init(
        schedule: ExportSchedule,
        recentRuns: [ScheduleRun],
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.schedule = schedule
        self.recentRuns = recentRuns
        self.onPause = onPause
        self.onResume = onResume
        self.onCancel = onCancel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                scheduleHeaderSection
                if !recentRuns.isEmpty {
                    recentRunsSection
                }
                scheduleActionSection
            }
            .padding(DesignTokens.Spacing.xxl)
        }
        .navigationTitle(schedule.name)
        .exportInlineTitleMode()
        .exportToolbarBackground()
    }

    private var scheduleHeaderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: schedule.status.systemImage)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                Text(schedule.status.displayName)
                    .font(.title3.bold())
                    .foregroundStyle(statusColor)
                Spacer()
                BrandGlassBadge(schedule.intervalKind.displayName, variant: .regular)
            }

            HStack {
                Image(systemName: schedule.exportType.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: DesignTokens.Spacing.xl)
                Text(schedule.exportType.displayName)
                    .font(.body)
                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

            if let nextRun = schedule.nextRunAt {
                Label("Next run: \(nextRun)", systemImage: "calendar")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("RECENT RUNS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(recentRuns.prefix(5)) { run in
                    recentRunRow(run)
                    if run.id != recentRuns.prefix(5).last?.id {
                        Divider().padding(.leading, DesignTokens.Spacing.lg)
                    }
                }
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
    }

    private func recentRunRow(_ run: ScheduleRun) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: run.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(run.succeeded ? Color.green : Color.red)
                .frame(width: DesignTokens.Spacing.xl)

            Text(run.runAt)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            if let file = run.exportFile {
                Text(file)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Run on \(run.runAt): \(run.succeeded ? "succeeded" : "failed")")
    }

    @ViewBuilder
    private var scheduleActionSection: some View {
        BrandGlassContainer(spacing: DesignTokens.Spacing.sm) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                if schedule.status == .paused {
                    Button {
                        onResume()
                    } label: {
                        Label("Resume Schedule", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlassProminent)
                    .tint(Color.accentColor)
                    .accessibilityLabel("Resume schedule")
                } else if schedule.status == .active {
                    Button {
                        onPause()
                    } label: {
                        Label("Pause Schedule", systemImage: "pause.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlass)
                    .accessibilityLabel("Pause schedule")
                }

                if schedule.status != .canceled {
                    Button(role: .destructive) {
                        onCancel()
                    } label: {
                        Label("Cancel Schedule", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.brandGlassClear)
                    .accessibilityLabel("Cancel and delete this schedule")
                }
            }
        }
    }

    private var statusColor: Color {
        switch schedule.status {
        case .active:   return .green
        case .paused:   return .orange
        case .canceled: return .secondary
        }
    }
}
