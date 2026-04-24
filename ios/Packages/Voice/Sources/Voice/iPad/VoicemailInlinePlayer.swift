#if canImport(UIKit)
import SwiftUI
import AVFoundation
import DesignSystem
import Networking

/// §22 — Compact voicemail player embedded directly inside the iPad detail
/// column. Unlike `VoicemailPlayerView` (which is a full-screen sheet), this
/// view sits inline as a card so the user never leaves the three-column layout.
///
/// Design contract:
/// - Uses Liquid Glass chrome (`.brandGlass`) on the control strip.
/// - Play/pause responds to the Space bar keyboard shortcut when focused.
/// - Scrubber updates every 100 ms via a periodic observer.
/// - Respects `.accessibilityReduceMotion` — progress jumps instead of animating.
/// - Height is compact (≤ 180 pt) so it nests cleanly above a transcript card.
public struct VoicemailInlinePlayer: View {

    // MARK: - Input

    let entry: VoicemailEntry

    // MARK: - Player state

    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var isPlaying: Bool = false
    @State private var progress: Double = 0
    @State private var duration: Double = 1
    @State private var elapsed: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var periodicObserver: Any?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let speeds: [(label: String, rate: Float)] = [
        ("1×", 1.0), ("1.5×", 1.5), ("2×", 2.0)
    ]

    // MARK: - Init

    public init(entry: VoicemailEntry) {
        self.entry = entry
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            scrubberRow
            controlsRow
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voicemail player for \(entry.customerName ?? entry.phoneNumber)")
        .onAppear { setupPlayer() }
        .onDisappear { tearDown() }
        // Space bar — play / pause when this player is on screen
        .keyboardShortcut(" ", modifiers: [])
    }

    // MARK: - Scrubber

    private var scrubberRow: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Slider(value: $progress, in: 0...1) { editing in
                if !editing, let p = player {
                    let target = CMTime(
                        seconds: progress * duration,
                        preferredTimescale: 600
                    )
                    p.seek(to: target)
                }
            }
            .tint(.blue)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(Int(elapsed))s of \(Int(duration))s")

            HStack {
                Text(formatTime(elapsed))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text("-\(formatTime(max(0, duration - elapsed)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            // Play / pause button — glass-backed circle
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause voicemail" : "Play voicemail")
            .hoverEffect(.highlight)

            Spacer()

            // Speed selector pills backed by glass
            BrandGlassContainer(spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(Self.speeds, id: \.rate) { speed in
                        speedButton(speed)
                    }
                }
            }
        }
    }

    private func speedButton(_ speed: (label: String, rate: Float)) -> some View {
        let isActive = playbackRate == speed.rate
        return Button(speed.label) {
            playbackRate = speed.rate
            if isPlaying { player?.rate = speed.rate }
        }
        .font(.caption)
        .fontWeight(isActive ? .bold : .regular)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .brandGlass(
            isActive ? .identity : .clear,
            in: Capsule(),
            tint: isActive ? .blue : nil,
            interactive: true
        )
        .foregroundStyle(isActive ? .blue : .secondary)
        .accessibilityLabel("Playback speed \(speed.label)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .hoverEffect(.highlight)
    }

    // MARK: - Playback

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

    // MARK: - Player setup

    private func setupPlayer() {
        guard let urlString = entry.audioUrl,
              let url = URL(string: urlString) else { return }

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        playerItem = item

        // Async duration load
        Task { @MainActor in
            if let dur = try? await item.asset.load(.duration),
               dur.isValid, !dur.isIndefinite {
                duration = dur.seconds
            }
        }

        // 100 ms tick
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        periodicObserver = p.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak item] time in
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

        // End-of-file reset
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

    private func tearDown() {
        player?.pause()
        if let obs = periodicObserver {
            player?.removeTimeObserver(obs)
            periodicObserver = nil
        }
        player = nil
        isPlaying = false
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif
