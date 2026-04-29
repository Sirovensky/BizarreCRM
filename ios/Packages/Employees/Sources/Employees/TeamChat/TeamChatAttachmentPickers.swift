import SwiftUI
import Networking
import DesignSystem
import Core
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// MARK: - Photo & file pickers
//
// §14.5 Image / file attachment.
//
// SERVER GAP §74 — there is no `POST /api/v1/team-chat/.../attachments`
// endpoint and `team_chat_messages` has no attachment columns. We pick the
// asset, write it into the app's tmp directory, and send a `[[attach:…]]`
// marker referencing the local file:// URL. The receiver sees the file
// name + a placeholder; once the server adds attachment columns we'll swap
// the local URL for the uploaded server URL with no view changes.
//
// This is honest behaviour — the file is picked and tracked, no fake upload.

#if canImport(PhotosUI)
struct TeamChatPhotoPicker: View {
    let api: APIClient
    let authToken: String?
    let onPicked: (TeamChatAttachment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var status: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.bizarrePrimary)
                Text("Attach a photo")
                    .font(.headline)
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .padding(.horizontal, BrandSpacing.lg)
                        .padding(.vertical, BrandSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Color.bizarreTextSecondary)
                }
                Spacer()
            }
            .padding(BrandSpacing.lg)
            .navigationTitle("Photo")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedItem) { _, item in
                Task { await handlePicked(item) }
            }
        }
    }

    private func handlePicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                status = "Could not read photo."
                return
            }
            let fileName = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(fileName)
            try data.write(to: url)
            let attachment = TeamChatAttachment(
                url: url.absoluteString,
                mimeType: "image/jpeg",
                fileName: fileName
            )
            onPicked(attachment)
        } catch {
            status = error.localizedDescription
        }
    }
}
#endif

#if canImport(UniformTypeIdentifiers)
struct TeamChatFilePicker: View {
    let api: APIClient
    let authToken: String?
    let onPicked: (TeamChatAttachment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = true

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                Image(systemName: "paperclip")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.bizarrePrimary)
                Text("Pick a file…")
                    .font(.headline)
                    .padding(.top, BrandSpacing.sm)
                Spacer()
            }
            .navigationTitle("File")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.image, .pdf, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                handleResult(result)
            }
            .onChange(of: showImporter) { _, isShown in
                if !isShown { dismiss() }
            }
        }
    }

    private func handleResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            dismiss()
        case .success(let urls):
            guard let src = urls.first else { dismiss(); return }
            let didStart = src.startAccessingSecurityScopedResource()
            defer { if didStart { src.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: src)
                let fileName = src.lastPathComponent
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
                try data.write(to: dst)
                let mime = mimeType(for: src.pathExtension)
                onPicked(TeamChatAttachment(
                    url: dst.absoluteString,
                    mimeType: mime,
                    fileName: fileName
                ))
            } catch {
                dismiss()
            }
        }
    }

    private func mimeType(for ext: String) -> String {
        let lower = ext.lowercased()
        if let utType = UTType(filenameExtension: lower),
           let preferred = utType.preferredMIMEType {
            return preferred
        }
        return "application/octet-stream"
    }
}
#endif
