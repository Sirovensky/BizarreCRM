#if canImport(UIKit)
import SwiftUI
import AVFoundation
import DesignSystem
import Networking

/// §42.5 — AVPlayer-backed voicemail player sheet.
///
/// Features:
/// - Play / pause toggle
/// - Progress scrubber with elapsed / remaining time
/// - Speed selector: 1x, 1.5x, 2x
/// - Transcript text displayed below if present
/// - Respects Reduce Motion: progress animation is instant when enabled
public struct VoicemailPlayerView: View {
    let entry: VoicemailEntry
    let onDismiss: () -> Void

    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isPlaying: Bool = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1
    @State private var elapsed: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var periodicObserver: Any?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speeds: [(label: String, rate: Float)] = [
        ("1x", 1.0), ("1.5x", 1.5), ("2x", 2.0)
    ]

    public init(entry: VoicemailEntry, onDismiss: @escaping () -> Void) {
        self.entry = entry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.xxl) {
                    // Header
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "voicemail")
                            .font(.system(size: 52))
                            .foregroundStyle(.bizarrePrimary)
                            .accessibilityHidden(true)
                        Text(entry.customerName ?? entry.phoneNumber)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if entry.customerName != nil {
                            Text(entry.phoneNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.lg)
                    .accessibilityElement(children: .combine)

                    // Progress scrubber
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        Slider(value: $progress, in: 0...1) { editing in
                            if !editing, let p = player {
                                let target = CMTime(seconds: progress * duration, preferredTimescale: 600)
                                p.seek(to: target)
                            }
                        }
                        .tint(.bizarrePrimary)
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
                    .padding(.horizontal, DesignTokens.Spacing.xxxl)

                    // Play / pause
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.bizarrePrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    // Speed selector
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
                                    ? Color.bizarrePrimary.opacity(0.15)
                                    : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(playbackRate == speed.rate ? .bizarrePrimary : .secondary)
                            .accessibilityLabel("Playback speed \(speed.label)")
                            .accessibilityAddTraits(playbackRate == speed.rate ? .isSelected : [])
                        }
                    }

                    // Transcript
                    if let transcript = entry.transcriptText, !transcript.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            Text("Transcript")
                                .font(.headline)
                            Text(transcript)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(DesignTokens.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Transcript: \(transcript)")
                    }

                    Spacer(minLength: DesignTokens.Spacing.huge)
                }
            }
            .navigationTitle("Voicemail")
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

    // MARK: - Player setup

    private func setupPlayer() {
        guard let urlString = entry.audioUrl, let url = URL(string: urlString) else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        playerItem = item

        // Observe duration
        Task { @MainActor in
            let dur = try? await item.asset.load(.duration)
            if let d = dur, d.isValid, !d.isIndefinite {
                duration = d.seconds
            }
        }

        // Periodic time observer — 100 ms tick
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

        // End-of-file observer
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
    }

    private func togglePlayback() {
        guard let p = player else { return }
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
