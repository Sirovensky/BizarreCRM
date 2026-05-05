import SwiftUI
import DesignSystem

// MARK: - ExportContextMenuActions

/// Callback bundle injected from the parent list view.
/// Keeps the context-menu modifier free of ViewModel knowledge.
public struct ExportContextMenuActions: Sendable {
    public let onDownload: @Sendable () -> Void
    public let onCancel: @Sendable () -> Void
    public let onPauseResume: (@Sendable (Bool) -> Void)?  // nil = not a scheduled export
    public let onViewDetails: @Sendable () -> Void

    public init(
        onDownload: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void,
        onPauseResume: (@Sendable (Bool) -> Void)? = nil,
        onViewDetails: @escaping @Sendable () -> Void
    ) {
        self.onDownload = onDownload
        self.onCancel = onCancel
        self.onPauseResume = onPauseResume
        self.onViewDetails = onViewDetails
    }
}

// MARK: - ExportContextMenu modifier

public extension View {
    /// Attaches an export-item context menu to any list row.
    ///
    /// - Parameters:
    ///   - job: The `TenantExportJob` driving the item; determines which
    ///     actions are visible (e.g. Download only when completed).
    ///   - isScheduled: Pass `true` when the row represents a scheduled
    ///     export — unlocks the Pause/Resume action.
    ///   - isPaused: Current pause state; only relevant when `isScheduled`.
    ///   - actions: Callback bundle from the parent.
    func exportContextMenu(
        job: TenantExportJob,
        isScheduled: Bool = false,
        isPaused: Bool = false,
        actions: ExportContextMenuActions
    ) -> some View {
        modifier(ExportContextMenuModifier(
            job: job,
            isScheduled: isScheduled,
            isPaused: isPaused,
            actions: actions
        ))
    }
}

// MARK: - ExportContextMenuModifier

struct ExportContextMenuModifier: ViewModifier {
    let job: TenantExportJob
    let isScheduled: Bool
    let isPaused: Bool
    let actions: ExportContextMenuActions

    func body(content: Content) -> some View {
        content
            .contextMenu {
                // View Details — always available
                Button {
                    actions.onViewDetails()
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                .accessibilityLabel("View export details")

                // Download — only when completed and URL is available
                if job.status == .completed, job.downloadUrl != nil {
                    Button {
                        actions.onDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .accessibilityLabel("Download export file")
                }

                // Pause/Resume — scheduled exports only
                if isScheduled, let onPauseResume = actions.onPauseResume {
                    Divider()

                    Button {
                        onPauseResume(isPaused)
                    } label: {
                        if isPaused {
                            Label("Resume Schedule", systemImage: "play.circle")
                        } else {
                            Label("Pause Schedule", systemImage: "pause.circle")
                        }
                    }
                    .accessibilityLabel(isPaused ? "Resume schedule" : "Pause schedule")
                }

                Divider()

                // Cancel — destructive, always visible for non-terminal jobs
                if !job.status.isTerminal {
                    Button(role: .destructive) {
                        actions.onCancel()
                    } label: {
                        Label("Cancel Export", systemImage: "xmark.circle")
                    }
                    .accessibilityLabel("Cancel this export")
                }
            }
    }
}

// MARK: - ExportContextMenuPreviewRow

/// Optional preview content shown above the context menu on long-press (iOS 16+).
/// Shows the job status and a compact entity badge.
public struct ExportContextMenuPreview: View {
    public let job: TenantExportJob
    public let entityName: String

    public init(job: TenantExportJob, entityName: String) {
        self.job = job
        self.entityName = entityName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(job.status.displayLabel)
                    .font(.headline)
                Spacer()
                BrandGlassBadge(entityName, variant: .regular)
            }

            if let size = job.byteSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: job.status.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(statusColor)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 240, idealWidth: 320)
    }

    private var statusIcon: String {
        switch job.status {
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        case .queued:     return "clock"
        default:          return "arrow.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed: return .green
        case .failed:    return .red
        default:         return .accentColor
        }
    }
}
