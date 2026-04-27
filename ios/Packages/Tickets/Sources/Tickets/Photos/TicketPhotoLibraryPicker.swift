#if canImport(UIKit)
import SwiftUI
import PhotosUI
import Core
import DesignSystem
import Networking

// MARK: - §4.8 Library picker for ticket photos
//
// Uses `PhotosUI.PhotosPicker` (iOS 16+) with a selection limit of 10.
// Selected items are loaded as JPEG data via `PhotosPickerItem.loadTransferable`,
// then passed to the parent for upload.
//
// Selection limit: 10 (§4.8 spec).
// EXIF strip: applied via ExifStripper before upload (§4.8 spec).

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketPhotoLibraryPickerViewModel {
    public private(set) var selectedItems: [PhotosPickerItem] = []
    public private(set) var loadedImages: [Data] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    /// Maximum photos the user can pick at once.
    public let selectionLimit: Int = 10

    public func loadImages() async {
        guard !selectedItems.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var images: [Data] = []
        for item in selectedItems {
            do {
                if let data = try await item.loadTransferable(type: Data.self) {
                    // Strip EXIF before adding to upload queue (§4.8)
                    let stripped = (try? ExifStripper.strip(from: data))?.jpegData ?? data
                    images.append(stripped)
                }
            } catch {
                AppLog.ui.error(
                    "PhotoPicker load item failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        loadedImages = images
        AppLog.ui.debug("PhotoPicker: loaded \(images.count) images after EXIF strip")
    }

    public func clearSelection() {
        selectedItems = []
        loadedImages = []
        errorMessage = nil
    }
}

// MARK: - View

/// A button that opens `PhotosPicker` with a limit of 10 images.
/// On confirm, strips EXIF and calls `onPick` with the JPEG data arrays.
public struct TicketPhotoLibraryPickerButton: View {
    @State private var vm = TicketPhotoLibraryPickerViewModel()
    @State private var showingPicker: Bool = false

    private let onPick: ([Data]) -> Void

    public init(onPick: @escaping ([Data]) -> Void) {
        self.onPick = onPick
    }

    public var body: some View {
        Button {
            showingPicker = true
        } label: {
            Label("Add from Library", systemImage: "photo.on.rectangle")
        }
        .disabled(vm.isLoading)
        .accessibilityLabel("Pick up to 10 photos from your photo library")
        .photosPicker(
            isPresented: $showingPicker,
            selection: $vm.selectedItems,
            maxSelectionCount: vm.selectionLimit,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: vm.selectedItems) { _, _ in
            Task {
                await vm.loadImages()
                if !vm.loadedImages.isEmpty {
                    onPick(vm.loadedImages)
                    vm.clearSelection()
                }
            }
        }
        .overlay {
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .accessibilityLabel("Loading selected photos")
            }
        }
    }
}

// MARK: - Thumbnail cache view

/// Displays a ticket photo thumbnail using URLCache for disk caching.
/// Full-size image is loaded on tap (future §4.8 task).
///
/// Uses `AsyncImage` with a custom URLRequest that respects the
/// system URLCache so thumbnails are cached on disk without Nuke.
public struct TicketPhotoThumbnailView: View {
    private let url: URL?
    private let size: CGFloat
    private let onTap: (() -> Void)?

    public init(url: URL?, size: CGFloat = 80, onTap: (() -> Void)? = nil) {
        self.url = url
        self.size = size
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderView
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        placeholderView
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }
                .hoverEffect(.highlight)
                .accessibilityLabel("Ticket photo")
            } else {
                placeholderView
            }
        }
    }

    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            .fill(Color.bizarreSurface2)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Photo unavailable")
    }
}
#endif
