import SwiftUI
import Core
import DesignSystem

// MARK: - ImportProgressView

public struct ImportProgressView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    private var job: ImportJob? { vm.job }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xxl) {
                header

                progressRing

                statsGrid

                // §48.3 Pause / resume / cancel
                if job?.status.isRunning == true || job?.status.isPaused == true {
                    pauseResumeControls
                }

                if let j = job, j.errorCount > 0 {
                    viewErrorsButton
                    // §48.2 Error report download
                    errorExportControls
                }

                if job?.status == .failed {
                    failedBanner
                    errorExportControls
                }

                if job?.canRollback == true {
                    rollbackBanner
                }
            }
            .padding(.top, DesignTokens.Spacing.xxl)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(headerTitle)
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text(headerSubtitle)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var headerTitle: String {
        let entity = vm.selectedEntity.displayName
        switch job?.status {
        case .completed: return "\(entity) Import Complete"
        case .failed:    return "\(entity) Import Failed"
        default:         return "Importing \(entity)…"
        }
    }

    private var headerSubtitle: String {
        if let cp = vm.checkpoint {
            let chunk = cp.nextChunkIndex
            let total = cp.totalChunks
            let etaPart = vm.etaString.isEmpty ? "" : " · \(vm.etaString) remaining"
            return "Chunk \(chunk) / \(total)\(etaPart)"
        }
        if !vm.etaString.isEmpty {
            return "Estimated time remaining: \(vm.etaString)"
        }
        return "Processing your data"
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.bizarreSurface1, lineWidth: 12)
            Circle()
                .trim(from: 0, to: vm.progressFraction)
                .stroke(
                    job?.status == .completed ? Color.bizarreSuccess : Color.bizarreOrange,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: vm.progressFraction)
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text("\(Int(vm.progressFraction * 100))%")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
                if let total = job?.totalRows {
                    Text("\(job?.processedRows ?? 0) / \(total)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
        }
        .frame(width: 160, height: 160)
        .accessibilityLabel("Import progress \(Int(vm.progressFraction * 100)) percent, \(job?.processedRows ?? 0) of \(job?.totalRows ?? 0) rows processed")
        .accessibilityValue("\(Int(vm.progressFraction * 100)) percent complete")
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: DesignTokens.Spacing.lg, verticalSpacing: DesignTokens.Spacing.lg) {
            GridRow {
                statCard(
                    label: "Processed",
                    value: "\(job?.processedRows ?? 0)",
                    icon: "checkmark.circle",
                    color: .bizarreSuccess
                )
                statCard(
                    label: "Errors",
                    value: "\(job?.errorCount ?? 0)",
                    icon: "exclamationmark.triangle",
                    color: job?.errorCount ?? 0 > 0 ? .bizarreError : .bizarreOnSurfaceMuted
                )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .monospacedDigit()
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var viewErrorsButton: some View {
        Button("View Errors (\(job?.errorCount ?? 0))") {
            Task { await vm.viewErrors() }
        }
        .buttonStyle(.brandGlass)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityIdentifier("import.progress.viewErrors")
    }

    private var failedBanner: some View {
        Label("Import failed — review errors above", systemImage: "xmark.circle.fill")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreError)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .accessibilityLabel("Import failed. Tap View Errors to see what went wrong.")
    }

    private var rollbackBanner: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Label("Undo available within 24 hours", systemImage: "arrow.uturn.backward.circle")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityLabel("Rollback is available. You can undo this import within 24 hours.")
    }

    // MARK: - §48.3 Pause / resume / cancel controls

    @ViewBuilder
    private var pauseResumeControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if job?.status.isRunning == true {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Button {
                        Task { await vm.pauseImport() }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            if vm.isPausing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "pause.circle")
                            }
                            Text(vm.isPausing ? "Pausing…" : "Pause")
                        }
                    }
                    .buttonStyle(.brandGlass)
                    .disabled(vm.isPausing)
                    .accessibilityIdentifier("import.progress.pause")
                    .accessibilityLabel("Pause import")

                    Button(role: .destructive) {
                        Task { await vm.cancelImport() }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            if vm.isCancelling {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "xmark.circle")
                            }
                            Text(vm.isCancelling ? "Cancelling…" : "Cancel")
                        }
                    }
                    .buttonStyle(.brandGlass)
                    .disabled(vm.isCancelling)
                    .accessibilityIdentifier("import.progress.cancel")
                    .accessibilityLabel("Cancel import")
                }
            } else if job?.status.isPaused == true {
                Button {
                    Task { await vm.resumeImport() }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        if vm.isResuming {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.circle")
                        }
                        Text(vm.isResuming ? "Resuming…" : "Resume")
                    }
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .disabled(vm.isResuming)
                .accessibilityIdentifier("import.progress.resume")
                .accessibilityLabel("Resume import")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

    // MARK: - §48.2 Error report download

    @ViewBuilder
    private var errorExportControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if let url = vm.errorExportURL {
                ShareLink(
                    item: url,
                    subject: Text("Import Error Report"),
                    message: Text("Row errors from your import")
                ) {
                    Label("Share Error Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .font(.brandBodyMedium().weight(.semibold))
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityIdentifier("import.errors.shareReport")
            }

            Button {
                Task { await vm.exportErrors() }
            } label: {
                HStack {
                    if vm.isExportingErrors {
                        ProgressView().controlSize(.small)
                        Text("Preparing…").font(.brandBodyMedium())
                    } else {
                        Label("Download Error Report", systemImage: "arrow.down.doc")
                            .font(.brandBodyMedium().weight(.semibold))
                    }
                }
            }
            .buttonStyle(.brandGlass)
            .disabled(vm.isExportingErrors || vm.jobId == nil)
            .accessibilityIdentifier("import.errors.download")
            .accessibilityLabel(vm.isExportingErrors ? "Preparing error report" : "Download error report as CSV")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }
}
