#if canImport(UIKit)
import SwiftUI
import UIKit
import Vision
import Core

#if canImport(VisionKit)
import VisionKit
#endif

/// `UIViewRepresentable` that wraps `UIImageView` with `ImageAnalysisInteraction`
/// (iOS 16+) for Live Text — press-and-hold reveals recognized text.
///
/// The optional `onTextRecognized` callback is fired once with the full plain-text
/// corpus from Vision when the image changes. Callers use this for IMEI / serial
/// number extraction.
@available(iOS 16.0, *)
public struct LiveTextView: UIViewRepresentable {

    @Binding private var image: UIImage?
    private let onTextRecognized: ((String) -> Void)?

    public init(
        image: Binding<UIImage?>,
        onTextRecognized: ((String) -> Void)? = nil
    ) {
        self._image = image
        self.onTextRecognized = onTextRecognized
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onTextRecognized: onTextRecognized)
    }

    public func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        #if canImport(VisionKit)
        iv.addInteraction(context.coordinator.interaction)
        #endif

        context.coordinator.imageView = iv
        return iv
    }

    public func updateUIView(_ uiView: UIImageView, context: Context) {
        guard uiView.image !== image else { return }
        uiView.image = image
        if let img = image {
            Task {
                await context.coordinator.analyzeImage(img)
                await context.coordinator.updateLiveText(on: uiView)
            }
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        let onTextRecognized: ((String) -> Void)?
        weak var imageView: UIImageView?

        #if canImport(VisionKit)
        let interaction: ImageAnalysisInteraction
        #endif

        init(onTextRecognized: ((String) -> Void)?) {
            self.onTextRecognized = onTextRecognized
            #if canImport(VisionKit)
            self.interaction = ImageAnalysisInteraction()
            #endif
            super.init()
        }

        func analyzeImage(_ image: UIImage) async {
            guard let cgImage = image.cgImage else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results ?? []
                let corpus = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                if !corpus.isEmpty {
                    await MainActor.run {
                        self.onTextRecognized?(corpus)
                    }
                }
            } catch {
                AppLog.ui.error("LiveTextView OCR failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        @MainActor
        func updateLiveText(on imageView: UIImageView) async {
            #if canImport(VisionKit)
            guard let uiImage = imageView.image else { return }
            if #available(iOS 16.0, *), ImageAnalyzer.isSupported {
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                do {
                    let analysis = try await analyzer.analyze(uiImage, configuration: configuration)
                    interaction.analysis = analysis
                    interaction.preferredInteractionTypes = .textSelection
                } catch {
                    AppLog.ui.error("LiveTextView ImageAnalysis failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            #endif
        }
    }
}

// MARK: - Fallback for iOS < 16

/// Placeholder view shown on iOS 15 or below where Live Text is unavailable.
public struct LiveTextUnavailableView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Live Text requires iOS 16 or later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
#endif
