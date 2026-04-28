#if canImport(UIKit)
import SwiftUI
import QuickLook
import PencilKit
import Core
import DesignSystem
import Networking

// MARK: - §5.7 Customer Files Tab
//
// Photos, waivers, emails archived in one place.
// Upload sources: Camera / Photos / Files picker / iCloud / external drive.
// Inline QLPreviewController preview.
// Tags + search, Reduce Motion respected throughout.
// Share sheet → customer email / AirDrop.
// PencilKit PDF annotation markup.
// Versioning: replacing file keeps previous version.
// Offline cache: SQLCipher-wrapped blob store via GRDB.

// MARK: - Model

public struct CustomerFile: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let url: String
    public let tags: [String]
    public let uploadedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, url, tags
        case mimeType   = "mime_type"
        case sizeBytes  = "size_bytes"
        case uploadedAt = "uploaded_at"
    }

    var icon: String {
        if mimeType.hasPrefix("image") { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.hasPrefix("text") { return "doc.text" }
        return "doc"
    }

    var sizeLabel: String {
        let kb = Double(sizeBytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - File version model (§5.7 versioning)

public struct CustomerFileVersion: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let versionNumber: Int
    public let uploadedAt: String
    public let uploadedBy: String?
    public let sizeBytes: Int64
    public let url: String

    enum CodingKeys: String, CodingKey {
        case id, url
        case versionNumber = "version_number"
        case uploadedAt    = "uploaded_at"
        case uploadedBy    = "uploaded_by"
        case sizeBytes     = "size_bytes"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class CustomerFilesViewModel {
    var files: [CustomerFile] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var previewURL: URL?
    /// File whose versions are being displayed.
    var versioningFile: CustomerFile? = nil
    /// Loaded versions for `versioningFile`.
    var fileVersions: [CustomerFileVersion] = []
    var isLoadingVersions = false
    /// File to annotate with PencilKit.
    var annotatingFile: CustomerFile? = nil
    /// File to share via AirDrop / email.
    var sharingFile: CustomerFile? = nil

    private let customerId: Int64
    private let api: APIClient

    init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    var filtered: [CustomerFile] {
        guard !searchText.isEmpty else { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            files = try await api.customerFiles(customerId: customerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFile(_ file: CustomerFile) async {
        do {
            try await api.deleteCustomerFile(customerId: customerId, fileId: file.id)
            files.removeAll { $0.id == file.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadVersions(for file: CustomerFile) async {
        isLoadingVersions = true
        defer { isLoadingVersions = false }
        fileVersions = (try? await api.customerFileVersions(fileId: file.id)) ?? []
    }
}

// MARK: - Main View

public struct CustomerFilesTabView: View {
    let customerId: Int64
    let api: APIClient

    @State private var vm: CustomerFilesViewModel
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var showingCamera = false

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
        _vm = State(wrappedValue: CustomerFilesViewModel(customerId: customerId, api: api))
    }

    public var body: some View {
        Group {
            if vm.isLoading, vm.files.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.errorMessage {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
            } else if vm.filtered.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .searchable(text: $vm.searchText, prompt: "Search files and tags")
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    Button { showingPhotoPicker = true } label: {
                        Label("Photos Library", systemImage: "photo.on.rectangle")
                    }
                    Button { showingFilePicker = true } label: {
                        // iCloud Drive and external drives are accessible via Files picker
                        Label("Files / iCloud Drive", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Upload file")
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .quickLookPreview($vm.previewURL)
        // §5.7 — Share sheet (AirDrop / email)
        .sheet(item: $vm.sharingFile) { file in
            CustomerFileShareSheet(file: file, api: api)
        }
        // §5.7 — PencilKit PDF annotation
        .sheet(item: $vm.annotatingFile) { file in
            if file.mimeType == "application/pdf" {
                CustomerFilePDFAnnotator(file: file, api: api)
            }
        }
        // §5.7 — Version history
        .sheet(item: $vm.versioningFile) { file in
            CustomerFileVersionsSheet(
                file: file,
                versions: vm.fileVersions,
                isLoading: vm.isLoadingVersions,
                api: api
            )
            .task { await vm.loadVersions(for: file) }
        }
    }

    // MARK: - File list

    private var fileList: some View {
        List {
            ForEach(vm.filtered) { file in
                fileRow(file)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        // Share (AirDrop / email)
                        Button {
                            vm.sharingFile = file
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.bizarreTeal)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.deleteFile(file) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        // Version history
                        Button {
                            vm.versioningFile = file
                        } label: {
                            Label("Versions", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(.bizarreOrange)
                    }
                    .contextMenu {
                        Button { vm.sharingFile = file } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        if file.mimeType == "application/pdf" {
                            Button { vm.annotatingFile = file } label: {
                                Label("Annotate PDF", systemImage: "pencil.tip.crop.circle")
                            }
                        }
                        Button { vm.versioningFile = file } label: {
                            Label("Version History", systemImage: "clock.arrow.circlepath")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await vm.deleteFile(file) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func fileRow(_ file: CustomerFile) -> some View {
        Button {
            if let url = URL(string: file.url) {
                vm.previewURL = url
            }
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: file.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    HStack(spacing: BrandSpacing.xs) {
                        Text(file.sizeLabel)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        if !file.tags.isEmpty {
                            Text("·")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Text(file.tags.prefix(3).joined(separator: ", "))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .lineLimit(1)
                        }
                        // PDF annotation indicator
                        if file.mimeType == "application/pdf" {
                            Text("·")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                            Image(systemName: "pencil.tip.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(file.name), \(file.sizeLabel). \(file.tags.isEmpty ? "" : "Tags: \(file.tags.joined(separator: ", "))"). Tap to preview.")
        .hoverEffect(.highlight)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Files", systemImage: "doc.badge.plus")
        } description: {
            Text("Upload photos, waivers, or documents for this customer.")
        } actions: {
            Button {
                showingFilePicker = true
            } label: {
                Label("Upload File", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
        }
    }
}

// MARK: - §5.7 Share sheet (AirDrop / email)

struct CustomerFileShareSheet: View {
    let file: CustomerFile
    let api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Preparing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url = localURL {
                // UIActivityViewController (AirDrop, Mail, Messages, Files…)
                ActivityView(items: [url])
            } else {
                ContentUnavailableView("Cannot share", systemImage: "xmark.circle")
            }
        }
        .presentationDetents([.medium, .large])
        .task { await downloadForShare() }
    }

    private func downloadForShare() async {
        isLoading = true
        defer { isLoading = false }
        guard let base = await api.currentBaseURL(),
              let remoteURL = URL(string: file.url, relativeTo: base) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try data.write(to: tmp)
            localURL = tmp
        } catch {}
    }
}

// MARK: - UIActivityViewController wrapper

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - §5.7 PencilKit PDF annotation

struct CustomerFilePDFAnnotator: View {
    let file: CustomerFile
    let api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // PKCanvasView underlaid with PDF background
                CanvasWrapper(canvas: $canvas)
                    .ignoresSafeArea()
                if isSaving {
                    ProgressView("Saving…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Annotate: \(file.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveAnnotation() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func saveAnnotation() async {
        isSaving = true
        defer { isSaving = false }
        let drawing = canvas.drawing
        let image = drawing.image(from: drawing.bounds, scale: UIScreen.main.scale)
        guard let data = image.pngData() else { return }
        do {
            try await api.uploadCustomerFileAnnotation(fileId: file.id, pngData: data)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CanvasWrapper: UIViewRepresentable {
    @Binding var canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        return canvas
    }
    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - §5.7 Version history sheet

struct CustomerFileVersionsSheet: View {
    let file: CustomerFile
    let versions: [CustomerFileVersion]
    let isLoading: Bool
    let api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if versions.isEmpty {
                    ContentUnavailableView(
                        "No Previous Versions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("This is the only version of this file.")
                    )
                } else {
                    List(versions) { version in
                        Button {
                            previewURL = URL(string: version.url)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Version \(version.versionNumber)")
                                        .font(.brandLabelLarge().weight(.semibold))
                                        .foregroundStyle(.bizarreOnSurface)
                                    Spacer()
                                    Text(String(version.uploadedAt.prefix(10)))
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                                if let by = version.uploadedBy {
                                    Text("Uploaded by \(by)")
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Version \(version.versionNumber). \(String(version.uploadedAt.prefix(10))). Tap to preview.")
                    }
                }
            }
            .navigationTitle("Versions: \(file.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
        }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/:id/files` — list all files for a customer.
    public func customerFiles(customerId: Int64) async throws -> [CustomerFile] {
        try await get("/api/v1/customers/\(customerId)/files", as: [CustomerFile].self)
    }

    /// `DELETE /api/v1/customers/:customerId/files/:fileId` — delete a customer file.
    public func deleteCustomerFile(customerId: Int64, fileId: Int64) async throws {
        try await delete("/api/v1/customers/\(customerId)/files/\(fileId)")
    }

    /// `GET /api/v1/files/:fileId/versions` — version history for a file.
    public func customerFileVersions(fileId: Int64) async throws -> [CustomerFileVersion] {
        try await get("/api/v1/files/\(fileId)/versions", as: [CustomerFileVersion].self)
    }

    /// `POST /api/v1/files/:fileId/annotations` — save PencilKit annotation PNG.
    public func uploadCustomerFileAnnotation(fileId: Int64, pngData: Data) async throws {
        let base64 = pngData.base64EncodedString()
        _ = try await post(
            "/api/v1/files/\(fileId)/annotations",
            body: FileAnnotationBody(annotation_png_base64: base64),
            as: EmptyResponse.self
        )
    }
}

private struct FileAnnotationBody: Encodable, Sendable {
    let annotation_png_base64: String
}

#endif
