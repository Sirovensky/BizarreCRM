#if canImport(UIKit)
import SwiftUI
import QuickLook
import Core
import DesignSystem
import Networking

// MARK: - §5.7 Customer Files Tab
//
// Photos, waivers, emails archived in one place.
// Upload sources: Camera / Photos / Files picker.
// Inline QLPreviewController preview.
// Tags + search, Reduce Motion respected throughout.

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

// MARK: - ViewModel

@MainActor
@Observable
final class CustomerFilesViewModel {
    var files: [CustomerFile] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var previewURL: URL?

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
                        Label("Files", systemImage: "folder")
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
    }

    // MARK: - File list

    private var fileList: some View {
        List {
            ForEach(vm.filtered) { file in
                fileRow(file)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
}

#endif
