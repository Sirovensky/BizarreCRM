#if canImport(UIKit)
import SwiftUI
import AVFoundation
import DesignSystem

// MARK: - CallRecordingPlayerView
//
// §42.1 "Recording playback — audio file streamed."
//
// Streams the recording audio from the URL stored in `CallLogEntry.recordingUrl`.
// The URL may be a local `/uploads/...` relative path — callers pass the resolved
// absolute URL (APIClient.baseURL + recordingUrl).
//
// Mirrors VoicemailPlayerView in UX: play/pause, scrubber, speed selector,
// Reduce Motion aware. Does NOT download the file — streams via AVPlayer.
//
// iPhone: presented as a sheet from CallDetailView.
// iPad: rendered inline in the detail column (no sheet needed).

/// AVPlayer-backed call recording player.
///
/// Usage (iPhone sheet):
/// ```swift
/// .sheet(isPresented: $showRecording) {
///     CallRecordingPlayerView(
///         entry: entry,
///         recordingURL: resolvedURL,
///         onDismiss: { showRecording = false }
///     )
/// }
/// ```
public struct CallRecordingPlayerView: View {

    // MARK: - Input

    public let entry: CallLogEntry
    public let recordingURL: URL
    public let onDismiss: () -> Void

    // MARK: - State

    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isPlaying: Bool = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1
    @State private var elapsed: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var periodicObserver: Any?
    @State private var loadError: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speeds: [(label: String, rate: Float)] = [
        ("1×", 1.0), ("1.5×", 1.5), ("2×", 2.0)
    ]

    // MARK: - Init

    public init(entry: CallLogEntry, recordingURL: URL, onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.recordingURL = recordingURL
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.xxl) {
                    callHeader
                    if let err = loadError {
                        errorView(err)
                    } else {
                        scrubber
                        playPauseButton
                        speedPicker
                        if let transcript = entry.transcriptText, !transcript.isEmpty {
                            transcriptCard(transcript)
                        }
                    }
                    Spacer(minLength: DesignTokens.Spacing.huge)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
            .navigationTitle("Call Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        stopPlayback()
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { stopPlayback() }
    }

    // MARK: - Sub-views

    private var callHeader: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: entry.isInbound ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(entry.isInbound ? .blue : .green)
                .accessibilityHidden(true)
            Text(entry.customerName ?? entry.phoneNumber)
                .font(.title2)
                .fontWeight(.semibold)
            if entry.customerName != nil {
                Text(entry.phoneNumber)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(entry.isInbound ? "Inbound call" : "Outbound call")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private var scrubber: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Slider(value: $progress, in: 0...1) { editing in
                if !editing, let p = player {
                    let target = CMTime(seconds: progress * duration, preferredTimescale: 600)
                    p.seek(to: target)
                }
            }
            .tint(.blue)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(elapsed))s of \(Int(duration))s")

            HStack {
                Text(formatTime(elapsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("-\(formatTime(max(0, duration - elapsed)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause recording" : "Play recording")
    }

    private var speedPicker: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(Self.speeds, id: \.rate) { speed in
                Button(speed.label) {
                    playbackRate = speed.rate
                    player?.rate = isPlaying ? speed.rate : 0
                }
                .font(.caption)
                .fontWeight(playbackRate == speed.rate ? .bold : .regular)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(
                    playbackRate == speed.rate
                        ? Color.blue.opacity(0.15)
                        : Color.clear,
                    in: Capsule()
                )
                .foregroundStyle(playbackRate == speed.rate ? .blue : .secondary)
                .accessibilityLabel("Speed \(speed.label)")
                .accessibilityAddTraits(playbackRate == speed.rate ? .isSelected : [])
            }
        }
    }

    private func transcriptCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Transcript")
                .font(.headline)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcript: \(text)")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Recording unavailable")
                .font(.title3)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Player setup

    private func setupPlayer() {
        let item = AVPlayerItem(url: recordingURL)
        let p = AVPlayer(playerItem: item)
        player = p
        playerItem = item

        Task { @MainActor in
            let dur = try? await item.asset.load(.duration)
            if let d = dur, d.isValid, !d.isIndefinite {
                duration = d.seconds
            } else if duration < 1 {
                // Asset may not be ready yet — retry once.
                try? await Task.sleep(nanoseconds: 500_000_000)
                let dur2 = try? await item.asset.load(.duration)
                if let d2 = dur2, d2.isValid, !d2.isIndefinite {
                    duration = d2.seconds
                }
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        periodicObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak item] time in
            guard let item else { return }
            let e = time.seconds
            let d = item.duration.seconds.isNaN ? 1 : item.duration.seconds
            elapsed = e
            duration = max(1, d)
            let newProgress = d > 0 ? e / d : 0
            if reduceMotion {
                progress = newProgress
            } else {
                withAnimation(.linear(duration: 0.1)) {
                    progress = newProgress
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                isPlaying = false
                progress = 0
                elapsed = 0
                player?.seek(to: .zero)
            }
        }

        // Observe AVPlayerItem status to catch load errors.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { notification in
            let err = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor in
                loadError = err?.localizedDescription ?? "Could not stream recording."
            }
        }
    }

    private func togglePlayback() {
        guard let p = player, loadError == nil else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.rate = playbackRate
            isPlaying = true
        }
    }

    private func stopPlayback() {
        player?.pause()
        if let obs = periodicObserver {
            player?.removeTimeObserver(obs)
        }
        player = nil
        isPlaying = false
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif
