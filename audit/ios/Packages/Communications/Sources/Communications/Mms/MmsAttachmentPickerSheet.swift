import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Core
import DesignSystem

// MARK: - MmsAttachmentPickerSheet

/// Sheet presenting photo library, camera, and file picker options for MMS attachments.
/// Compresses images to 1 MB max before adding to the attachment list.
public struct MmsAttachmentPickerSheet: View {
    @Binding var attachments: [MmsAttachment]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?

    private let imageSizeLimitBytes: Int64 = 1_000_000 // 1 MB

    public init(attachments: Binding<[MmsAttachment]>) {
        _attachments = attachments
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    if isProcessing {
                        ProgressView("Processing…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        pickerOptions
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BrandSpacing.lg)
                    }
                }
                .padding(.top, BrandSpacing.xl)
            }
            .navigationTitle("Add Attachment")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await processPhotoPickerItem(item) }
        }
#if !os(macOS)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                Task { await processUIImage(image) }
            }
        }
#endif
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            Task { await processFileImport(result) }
        }
    }

    // MARK: - Picker options

    private var pickerOptions: some View {
        VStack(spacing: BrandSpacing.md) {
            PhotosPicker(selection: $selectedPhoto, matching: .any(of: [.images, .videos])) {
                PickerOptionRow(
                    icon: "photo.on.rectangle",
                    title: "Photo Library",
                    subtitle: "Images and videos"
                )
            }
            .buttonStyle(.plain)

#if !os(macOS)
            Button {
                showCamera = true
            } label: {
                PickerOptionRow(
                    icon: "camera",
                    title: "Camera",
                    subtitle: "Take a photo or video"
                )
            }
            .buttonStyle(.plain)
            // §12 — explicit VoiceOver role + hint so assistive-technology
            // users know this opens the camera rather than the system
            // photo picker that precedes it in the list.
            .accessibilityLabel("Camera")
            .accessibilityHint("Opens the camera to take a new photo or video")
            .accessibilityAddTraits(.isButton)
#endif

            Button {
                showFilePicker = true
            } label: {
                PickerOptionRow(
                    icon: "doc",
                    title: "Files",
                    subtitle: "PDF or documents"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Processing

    private func processPhotoPickerItem(_ item: PhotosPickerItem) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            if item.supportedContentTypes.contains(.movie) {
                // Video
                if let url = try await item.loadTransferable(type: URL.self) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    let attachment = MmsAttachment(kind: .video, url: url, sizeBytes: size, mimeType: "video/mp4")
                    attachments.append(attachment)
                    dismiss()
                }
            } else {
                // Image — compress to 1 MB
                if let data = try await item.loadTransferable(type: Data.self) {
                    let compressed = compressImageData(data, limit: imageSizeLimitBytes)
                    let tempURL = writeTempFile(compressed, ext: "jpg")
                    let attachment = MmsAttachment(
                        kind: .image,
                        url: tempURL,
                        sizeBytes: Int64(compressed.count),
                        mimeType: "image/jpeg"
                    )
                    attachments.append(attachment)
                    dismiss()
                }
            }
        } catch {
            errorMessage = "Could not load the selected media: \(error.localizedDescription)"
        }
    }

#if !os(macOS)
    private func processUIImage(_ image: UIImage) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        let data = compressImageData(image.jpegData(compressionQuality: 0.9) ?? Data(), limit: imageSizeLimitBytes)
        let tempURL = writeTempFile(data, ext: "jpg")
        let attachment = MmsAttachment(
            kind: .image,
            url: tempURL,
            sizeBytes: Int64(data.count),
            mimeType: "image/jpeg"
        )
        attachments.append(attachment)
        dismiss()
    }
#endif

    private func processFileImport(_ result: Result<[URL], Error>) async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let attachment = MmsAttachment(
                kind: .file,
                url: url,
                sizeBytes: size,
                mimeType: url.mimeType
            )
            attachments.append(attachment)
            dismiss()
        case .failure(let err):
            errorMessage = "Could not import file: \(err.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func compressImageData(_ data: Data, limit: Int64) -> Data {
#if !os(macOS)
        guard Int64(data.count) > limit, let image = UIImage(data: data) else { return data }
        var quality: CGFloat = 0.8
        var result = data
        while Int64(result.count) > limit, quality > 0.1 {
            result = image.jpegData(compressionQuality: quality) ?? data
            quality -= 0.1
        }
        return result
#else
        return data
#endif
    }

    private func writeTempFile(_ data: Data, ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try? data.write(to: url)
        return url
    }
}

// MARK: - Supporting views

private struct PickerOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(title)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(subtitle)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Camera picker (iOS only)

#if !os(macOS)
import UIKit

private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
#endif

// MARK: - URL MIME helper

private extension URL {
    var mimeType: String {
        if let uti = UTType(filenameExtension: pathExtension) {
            return uti.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
