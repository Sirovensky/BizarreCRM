#if canImport(UIKit)
import SwiftUI
import Core

// §42.5 Voicemail transcription UI.
//
// Shown below the player controls in `VoicemailPlayerView`.
// If the server already provided a transcript (`entry.transcriptText != nil`),
// it is displayed directly. Otherwise an "Transcribe" button triggers
// `VoicemailTranscriptionService` on-device.

// MARK: - VoicemailTranscriptionView

public struct VoicemailTranscriptionView: View {

    // MARK: State

    @State private var state: LocalState = .idle
    private let serverTranscript: String?
    private let audioURL: URL?
    private let service = VoicemailTranscriptionService()

    // MARK: Local state

    private enum LocalState: Equatable {
        case idle
        case transcribing(progress: Double)
        case done(text: String)
        case failed(message: String)
    }

    // MARK: Init

    public init(serverTranscript: String?, audioURL: URL?) {
        self.serverTranscript = serverTranscript
        self.audioURL = audioURL
    }

    // MARK: Body

    public var body: some View {
        Group {
            if let server = serverTranscript {
                // Server provided transcript — display directly.
                transcriptCard(text: server, isOnDevice: false)
            } else {
                switch state {
                case .idle:
                    idleButton
                case .transcribing(let progress):
                    transcribingView(progress: progress)
                case .done(let text):
                    transcriptCard(text: text, isOnDevice: true)
                case .failed(let msg):
                    failedView(message: msg)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state)
    }

    // MARK: - Subviews

    private var idleButton: some View {
        Button {
            Task { await runTranscription() }
        } label: {
            Label("Transcribe Voicemail", systemImage: "waveform.and.mic")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
        .disabled(audioURL == nil)
        .accessibilityLabel("Transcribe voicemail on device")
        .accessibilityHint(audioURL == nil ? "No audio file available to transcribe." : "Tap to run on-device speech recognition on this voicemail.")
    }

    private func transcribingView(progress: Double) -> some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .accessibilityLabel("Transcribing, \(Int(progress * 100)) percent complete")
            Text("Transcribing on device…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func transcriptCard(text: String, isOnDevice: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isOnDevice ? "lock.shield" : "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(isOnDevice ? "On-device transcript" : "Transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Transcript: \(text)")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Try again") {
                Task { await runTranscription() }
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transcription failed: \(message). Tap try again.")
    }

    // MARK: - Logic

    private func runTranscription() async {
        guard let url = audioURL else {
            state = .failed("No audio file available.")
            return
        }
        state = .transcribing(progress: 0)
        do {
            let text = try await service.transcribe(audioURL: url) { progress in
                Task { @MainActor in
                    state = .transcribing(progress: progress)
                }
            }
            state = .done(text: text)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
#endif
