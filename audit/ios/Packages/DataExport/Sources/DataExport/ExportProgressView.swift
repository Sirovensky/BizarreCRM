import SwiftUI
import DesignSystem
import Core

// MARK: - ExportProgressView

/// Shows live progress for a running export job.
/// iPhone: full-screen card. iPad: panel in NavigationSplitView detail.
public struct ExportProgressView: View {

    @State private var viewModel: ExportProgressViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: ExportProgressViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                NavigationStack {
                    content
                        .navigationTitle("Export Progress")
                        .exportInlineTitleMode()
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("Export Progress").bold()
                            }
                        }
                }
            } else {
                content
                    .navigationTitle("Export Progress")
            }
        }
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    // MARK: - Shared content

    private var content: some View {
        VStack(spacing: 32) {
            statusIcon
            statusLabel
            progressSection
            if viewModel.job.status == .completed {
                completedActions
            }
            if let msg = viewModel.errorMessage ?? viewModel.job.errorMessage {
                errorSection(msg)
            }
            Spacer()
        }
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        let status = viewModel.job.status
        if status == .completed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        } else if status == .failed {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        } else if status == .queued {
            Image(systemName: "clock")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            // preparing / exporting / encrypting
            if reduceMotion {
                Image(systemName: "arrow.2.circlepath")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.accentColor)
                    .scaleEffect(1.5)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        }
    }

    private var statusLabel: some View {
        Text(viewModel.job.status.displayLabel)
            .font(.title2.bold())
            .accessibilityLabel("Status: \(viewModel.job.status.displayLabel)")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.job.progressPct, total: 1.0)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .animation(reduceMotion ? nil : .easeInOut, value: viewModel.job.progressPct)
                .accessibilityLabel("Export progress")
                .accessibilityValue("\(Int(viewModel.job.progressPct * 100)) percent")
                .accessibilityAddTraits(.updatesFrequently)

            Text("\(Int(viewModel.job.progressPct * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var completedActions: some View {
        if let urlString = viewModel.job.downloadUrl, let url = URL(string: urlString) {
            ExportShareSheet(downloadURL: url)
        }
    }

    private func errorSection(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding()
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Error: \(message)")
    }
}

// MARK: - ExportProgressChip (inline progress indicator)

/// Compact progress chip shown in toolbar or sheet header.
public struct ExportProgressChip: View {
    public let job: ExportJob

    public init(job: ExportJob) { self.job = job }

    public var body: some View {
        HStack(spacing: 6) {
            if !job.status.isTerminal {
                ProgressView(value: job.progressPct, total: 1.0)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .tint(.white)
                    .accessibilityHidden(true)
            } else if job.status == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .accessibilityHidden(true)
            }
            Text(job.status.displayLabel)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .brandGlass(.identity, tint: job.status == .failed ? .red : Color.accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export: \(job.status.displayLabel)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
