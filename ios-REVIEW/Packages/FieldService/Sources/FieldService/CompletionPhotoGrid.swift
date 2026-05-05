// §57.2 CompletionPhotoGrid — capture + display grid of before/after photos
// taken when a technician completes a job on-site.
//
// Flow:
//   1. Tech taps "Add Photo" → UIImagePickerController (camera or library).
//   2. Captured images are stored in-memory as JPEG Data items.
//   3. Grid shows thumbnails in a 3-column adaptive layout.
//   4. Each thumbnail has a remove button.
//   5. `photos` binding is the source of truth; caller persists / uploads.
//
// A11y:
//   - Add button: "Add completion photo"
//   - Thumbnail: "Completion photo N of M. Double-tap to remove."
//   - Grid has axLabel "Completion photos, N photos".
//
// Reduce Motion: no cross-fade on add/remove.
// Privacy: Camera + Photos usage descriptions required (already listed §57).

import SwiftUI
import PhotosUI

// MARK: - CompletionPhotoGrid

public struct CompletionPhotoGrid: View {

    @Binding public var photos: [Data]
    public var maxPhotos: Int = 10

    @State private var pickerItem: PhotosPickerItem? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(photos: Binding<[Data]>, maxPhotos: Int = 10) {
        self._photos = photos
        self.maxPhotos = maxPhotos
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion photos, \(photos.count) \(photos.count == 1 ? "photo" : "photos")")
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        photos.append(data)
                    }
                }
                pickerItem = nil
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Completion Photos")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if photos.count < maxPhotos {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Photo", systemImage: "camera.fill")
                        .font(.system(.caption, design: .default, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add completion photo")
            } else {
                Text("\(maxPhotos) max")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No photos yet")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Photo grid

    private var photoGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                PhotoThumbnail(data: data, index: index, total: photos.count) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        photos.remove(at: index)
                    }
                }
            }
        }
    }
}

// MARK: - PhotoThumbnail

private struct PhotoThumbnail: View {
    let data: Data
    let index: Int
    let total: Int
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = imageFromData() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 96, height: 96)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo \(index + 1)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion photo \(index + 1) of \(total)")
        .accessibilityHint("Double-tap remove button to delete")
    }

    private func imageFromData() -> UIImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return nil
        #endif
    }
}
