#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - VoiceMemoView

/// Full-screen voice memo recorder UI.
///
/// iPhone: presented as a sheet or full-screen cover.
/// iPad: presented as a `.presentationDetents([.medium])` sheet.
///
/// The caller receives the recorded file via `onSaved` callback; `onCancel`
/// fires when the user dismisses without saving.
///
/// Permission denied state renders a Liquid Glass frosted card with a
/// "Enable in Settings" CTA — mirrors `CameraCaptureView`'s pattern.
public struct VoiceMemoView: View {

    // MARK: - Init

    private let onSaved: (URL) -> Void
    private let onCancel: () -> Void
    private let maxDuration: TimeInterval

    public init(
        maxDuration: TimeInterval = 120,
        onSaved: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.maxDuration = maxDuration
        self.onSaved = onSaved
        self.onCancel = onCancel
        self._vm = State(wrappedValue: VoiceMemoViewModel(
            recorder: DefaultVoiceMemoRecorderAdapter(),
            maxDuration: maxDuration
        ))
    }

    // MARK: - State

    @State private var vm: VoiceMemoViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await cancelAction() }
                    }
                    .accessibilityIdentifier("voiceMemo.cancel")
                }
            }
        }
        .onChange(of: vm.recordingState) { _, newState in
            if case .saved(let url) = newState {
                onSaved(url)
                dismiss()
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.recordingState {
        case .failed(let message) where message.localizedCaseInsensitiveContains("access"):
            permissionDeniedCard(message: message)
        default:
            recordingContent
        }
    }

    private var recordingContent: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer()

            waveformIcon

            elapsedLabel

            Spacer()

            controlRow

            Spacer()
        }
        .padding(.horizontal, BrandSpacing.xl)
    }

    // MARK: - Waveform icon

    private var waveformIcon: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.bizarreError.opacity(0.12) : Color.bizarreOrange.opacity(0.12))
                .frame(width: 120, height: 120)

            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(isRecording ? Color.bizarreError : Color.bizarreOrange)
                .symbolEffect(.pulse, isActive: isRecording)
        }
        .accessibilityLabel(isRecording ? "Recording in progress" : "Microphone")
    }

    // MARK: - Elapsed label

    private var elapsedLabel: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text(formattedElapsed)
                .font(.system(size: 48, weight: .thin, design: .monospaced))
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("Elapsed time: \(vm.elapsedSeconds) seconds")

            Text(statusText)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var formattedElapsed: String {
        let s = vm.elapsedSeconds
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    private var statusText: String {
        switch vm.recordingState {
        case .idle:       return "Tap to record"
        case .requesting: return "Requesting permission…"
        case .recording:  return "Recording…"
        case .stopping:   return "Saving…"
        case .saved:      return "Saved"
        case .failed(let msg): return msg
        }
    }

    private var isRecording: Bool {
        if case .recording = vm.recordingState { return true }
        return false
    }

    // MARK: - Control row

    private var controlRow: some View {
        HStack(spacing: BrandSpacing.xxxl) {
            // Cancel / Discard button
            if isRecording {
                Button {
                    Task {
                        vm.discard()
                        onCancel()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.bizarreOnSurface)
                        .frame(width: 52, height: 52)
                        .background(Color.bizarreOutline.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard recording")
                .accessibilityIdentifier("voiceMemo.discard")
            }

            // Primary record / stop button
            Button {
                Task { await primaryAction() }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isRecording ? Color.bizarreError : Color.bizarreOrange, lineWidth: 3)
                        .frame(width: 80, height: 80)

                    if isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.bizarreError)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(Color.bizarreOrange)
                            .frame(width: 66, height: 66)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
            .accessibilityIdentifier("voiceMemo.primaryAction")
        }
    }

    private var isBusy: Bool {
        switch vm.recordingState {
        case .requesting, .stopping: return true
        default: return false
        }
    }

    // MARK: - Permission denied card

    private func permissionDeniedCard(message: String) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text("Microphone access needed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.base)

            Button {
                openSettings()
            } label: {
                Label("Enable in Settings", systemImage: "gearshape.fill")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnOrange)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)
                    .background(Color.bizarreOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("voiceMemo.openSettings")

            Button("Cancel") { onCancel(); dismiss() }
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityIdentifier("voiceMemo.cancelFromPermission")
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: 420)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.bizarreError.opacity(0.4), lineWidth: 0.5)
        )
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
        .padding(BrandSpacing.lg)
    }

    // MARK: - Helpers

    private func primaryAction() async {
        if isRecording {
            await vm.stopRecording()
        } else {
            await vm.startRecording()
        }
    }

    private func cancelAction() async {
        if isRecording {
            await vm.stopRecording()
            vm.discard()
        }
        onCancel()
        dismiss()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - DefaultVoiceMemoRecorderAdapter

/// Bridges the concrete `VoiceMemoRecorder` actor into the `RecorderProtocol`.
private final class DefaultVoiceMemoRecorderAdapter: VoiceMemoViewModel.RecorderProtocol, @unchecked Sendable {
    private let recorder = VoiceMemoRecorder()

    func authorize() async throws -> Bool {
        try await recorder.authorize()
    }

    func startRecording(maxDuration: TimeInterval) async throws -> URL {
        try await recorder.startRecording(maxDuration: maxDuration)
    }

    func stopRecording() async throws -> URL {
        try await recorder.stopRecording()
    }
}

#endif
