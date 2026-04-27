import SwiftUI
import Networking
import DesignSystem
import Core

// MARK: - §12.10 Transcription display

/// Sheet that shows the server-provided transcription text for a call.
/// Displayed when `entry.transcriptText` is non-nil (populated by `GET /voice/calls/:id`).
/// If nil the server has not produced a transcript yet; we show a graceful "Not available" state.
public struct CallTranscriptSheet: View {

    let entry: CallLogEntry

    @Environment(\.dismiss) private var dismiss

    public init(entry: CallLogEntry) {
        self.entry = entry
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                scrollContent
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss transcript")
                }
                if let text = entry.transcriptText, !text.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share transcript")
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Content

    @ViewBuilder
    private var scrollContent: some View {
        if let transcript = entry.transcriptText, !transcript.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    // Call metadata header
                    callHeader
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.top, BrandSpacing.md)

                    Divider().padding(.horizontal, BrandSpacing.md)

                    // Transcript body — selectable for copy (iPad + Mac)
                    Text(transcript)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .textSelection(.enabled)
                        .padding(.horizontal, BrandSpacing.md)
                        .padding(.bottom, BrandSpacing.xl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            unavailableState
        }
    }

    private var callHeader: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Label(
                entry.customerName ?? entry.phoneNumber,
                systemImage: entry.isInbound ? "phone.arrow.down.left" : "phone.arrow.up.right"
            )
            .font(.brandTitleMedium())
            .foregroundStyle(.bizarreOnSurface)
            .labelStyle(.titleAndIcon)

            if let dur = entry.durationSeconds {
                Text("Duration: \(dur / 60)m \(dur % 60)s")
                    .font(.brandLabelMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
            if let ts = entry.startedAt?.prefix(16) {
                Text(String(ts).replacingOccurrences(of: "T", with: " "))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }

    private var unavailableState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Transcript Available")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Auto-transcription is not enabled or the server has not processed this call yet.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
