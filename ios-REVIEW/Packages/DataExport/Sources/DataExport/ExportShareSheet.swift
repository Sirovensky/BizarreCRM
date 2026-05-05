import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ExportShareSheet

/// Presents a ShareLink for the export download URL + an iCloud Drive save option.
public struct ExportShareSheet: View {

    public let downloadURL: URL

    @State private var showDocumentPicker: Bool = false

    public init(downloadURL: URL) {
        self.downloadURL = downloadURL
    }

    public var body: some View {
        VStack(spacing: 16) {
            ShareLink(
                item: downloadURL,
                subject: Text("BizarreCRM Data Export"),
                message: Text("Your encrypted data export is ready.")
            ) {
                Label("Share Export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlassProminent)
            .tint(Color.accentColor)
            .accessibilityLabel("Share export file")
            .accessibilityHint("Opens the system share sheet with the encrypted export")

            Button {
                showDocumentPicker = true
            } label: {
                Label("Save to iCloud Drive", systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Save to iCloud Drive")
            .accessibilityHint("Opens Files app to choose a save location")
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showDocumentPicker) {
            iCloudDocumentPickerView(sourceURL: downloadURL)
                .ignoresSafeArea()
        }
        #endif
    }
}

// MARK: - iCloudDocumentPickerView

#if canImport(UIKit)
/// Wraps `UIDocumentPickerViewController` in export mode for iCloud Drive saving.
private struct iCloudDocumentPickerView: UIViewControllerRepresentable {
    let sourceURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIDocumentPickerDelegate, @unchecked Sendable {
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // File saved — no further action needed; system confirms in Files UI.
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
#endif
