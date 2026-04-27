import SwiftUI
import AVFoundation
import Observation
import Networking
import DesignSystem
import Core

// MARK: - §12.10 Recording Playback

/// Player view-model for `GET /voice/calls/:id/recording` → `AVAudioPlayer`.
/// Sovereign — downloads via the tenant's own APIClient (no external CDN).
@MainActor
@Observable
final class CallRecordingPlayerViewModel {

    // MARK: State

    var isLoading: Bool = false
    var isPlaying: Bool = false
    var duration: Double = 0
    var currentTime: Double = 0
    var errorMessage: String? = nil
    /// Set to true when the server has no recording (recordingUrl is nil).
    var unavailable: Bool = false

    // MARK: Private

    private var player: AVAudioPlayer? = nil
    private var timer: Task<Void, Never>? = nil
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    func load(callId: Int64) async {
        isLoading = true
        errorMessage = nil
        unavailable = false

        do {
            guard let url = try await api.fetchCallRecordingURL(callId: callId) else {
                unavailable = true
                isLoading = false
                return
            }
            // Resolve absolute URL against base URL if path-only (e.g. "/uploads/recordings/...").
            let absoluteURL: URL
            if url.scheme != nil {
                absoluteURL = url
            } else if let base = await api.currentBaseURL() {
                absoluteURL = base.appendingPathComponent(url.absoluteString)
            } else {
                absoluteURL = url
            }
            let (data, _) = try await URLSession.shared.data(from: absoluteURL)
            let audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            duration = audioPlayer.duration
        } catch let err as APITransportError {
            if case .httpStatus(404, _) = err {
                unavailable = true
            } else {
                errorMessage = "Could not load recording: \(err.localizedDescription)"
            }
        } catch {
            errorMessage = "Could not load recording: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Playback controls

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            timer?.cancel()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    guard let self, let player = self.player else { return }
                    self.currentTime = player.currentTime
                    if !player.isPlaying {
                        self.isPlaying = false
                        self.timer?.cancel()
                    }
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        player?.stop()
    }
}

// MARK: - View

/// Sheet presented from CallsTabView when a call has a recording.
public struct CallRecordingPlayerSheet: View {
    let entry: CallLogEntry
    @State private var vm: CallRecordingPlayerViewModel

    public init(entry: CallLogEntry, api: APIClient) {
        self.entry = entry
        _vm = State(wrappedValue: CallRecordingPlayerViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load(callId: entry.id) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    dismissButton
                }
            }
        }
        .presentationDetents([.medium])
    }

    @Environment(\.dismiss) private var dismiss

    private var dismissButton: some View {
        Button("Done") { dismiss() }
            .accessibilityLabel("Dismiss recording player")
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView("Loading recording…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.unavailable {
            unavailableState
        } else if let err = vm.errorMessage {
            errorState(err)
        } else {
            playerControls
        }
    }

    private var unavailableState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Recording Available")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("This call was not recorded, or the recording has expired.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Playback Error")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Retry") { Task { await vm.load(callId: entry.id) } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playerControls: some View {
        VStack(spacing: BrandSpacing.xl) {
            Spacer()

            // Waveform icon placeholder (brand visual)
            Image(systemName: "waveform")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            // Call metadata
            VStack(spacing: BrandSpacing.xs) {
                Text(entry.customerName ?? entry.phoneNumber)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(entry.isInbound ? "Inbound call" : "Outbound call")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let dur = entry.durationSeconds {
                    Text(Self.formatDuration(dur))
                        .font(.brandLabelMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }

            // Progress slider
            VStack(spacing: BrandSpacing.xs) {
                Slider(
                    value: Binding(
                        get: { vm.currentTime },
                        set: { vm.seek(to: $0) }
                    ),
                    in: 0...max(vm.duration, 1)
                )
                .tint(.bizarreOrange)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(Self.formatSeconds(vm.currentTime))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                    Spacer()
                    Text(Self.formatSeconds(vm.duration))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, BrandSpacing.lg)

            // Play / pause button
            Button {
                vm.togglePlayPause()
            } label: {
                Image(systemName: vm.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel(vm.isPlaying ? "Pause recording" : "Play recording")

            Spacer()
        }
        .padding(BrandSpacing.lg)
    }

    // MARK: - Helpers

    static func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    static func formatSeconds(_ secs: Double) -> String {
        let total = Int(secs)
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
