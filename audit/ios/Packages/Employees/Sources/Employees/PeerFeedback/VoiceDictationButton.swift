import SwiftUI
import Speech
import AVFoundation
import Core
import DesignSystem

// MARK: - VoiceDictationButton
//
// §46.5 — On-device SFSpeechRecognizer dictation button.
// Wraps the microphone permission request + live transcription.
// Appends recognised text to the bound `text` string.
//
// A11y: accessibilityLabel toggles between "Start dictation" / "Stop dictation".
// Reduce Motion: button pulse animation is disabled when ReduceMotion is active.

@available(iOS 17.0, *)
public struct VoiceDictationButton: View {

    @Binding var text: String
    @State private var dictation = DictationSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(text: Binding<String>) {
        _text = text
    }

    public var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(dictation.isRecording ? Color.bizarreError : Color.bizarreOrange)
                .padding(BrandSpacing.xs)
                .background(
                    dictation.isRecording
                        ? Color.bizarreError.opacity(0.12)
                        : Color.bizarreSurface2,
                    in: Circle()
                )
                .overlay {
                    if dictation.isRecording && !reduceMotion {
                        Circle()
                            .strokeBorder(Color.bizarreError.opacity(0.5), lineWidth: 1.5)
                            .scaleEffect(dictation.pulseScale)
                            .opacity(dictation.pulseOpacity)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
        .accessibilityHint("Dictate text using your microphone")
        .onChange(of: dictation.transcript) { _, new in
            guard !new.isEmpty else { return }
            if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
            text += new
            dictation.transcript = ""
        }
    }

    private func toggle() async {
        if dictation.isRecording {
            dictation.stop()
        } else {
            await dictation.start()
        }
    }
}

// MARK: - DictationSession

@MainActor
@Observable
final class DictationSession {
    var isRecording: Bool = false
    var transcript: String = ""
    var pulseScale: CGFloat = 1.0
    var pulseOpacity: Double = 0.6

    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var pulseTask: Task<Void, Never>?

    func start() async {
        // Request permissions on first use.
        let speechStatus = await SFSpeechRecognizer.requestAuthorizationAsync()
        guard speechStatus == .authorized else {
            AppLog.ui.warning("Speech recognition not authorized: \(speechStatus.rawValue)")
            return
        }
        let audioStatus = await AVAudioApplication.requestRecordPermission()
        guard audioStatus else {
            AppLog.ui.warning("Microphone permission denied")
            return
        }

        let rec = SFSpeechRecognizer(locale: Locale.current)
        guard rec?.isAvailable == true else { return }
        self.recognizer = rec

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = false
        req.requiresOnDeviceRecognition = true

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buf, _ in
            req?.append(buf)
        }

        do {
            try engine.start()
        } catch {
            AppLog.ui.error("AVAudioEngine start failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        self.audioEngine = engine
        self.request = req

        self.recognitionTask = rec?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let r = result, r.isFinal {
                Task { @MainActor in
                    self.transcript = r.bestTranscription.formattedString
                    self.stop()
                }
            }
            if let err = error {
                AppLog.ui.warning("Recognition error: \(err.localizedDescription, privacy: .public)")
                Task { @MainActor in self.stop() }
            }
        }

        isRecording = true
        startPulse()
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        request = nil
        recognitionTask = nil
        isRecording = false
        pulseTask?.cancel()
        pulseTask = nil
        pulseScale = 1.0
        pulseOpacity = 0.6
    }

    private func startPulse() {
        pulseTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.8)) {
                    pulseScale = 1.4
                    pulseOpacity = 0
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
                pulseScale = 1.0
                pulseOpacity = 0.6
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
}

// MARK: - SFSpeechRecognizer async helper

private extension SFSpeechRecognizer {
    static func requestAuthorizationAsync() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            requestAuthorization { status in cont.resume(returning: status) }
        }
    }
}
