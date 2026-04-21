#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §4 — Gallery of photos attached to a ticket.
/// Tap a photo to open full-screen preview.
/// Before/After tagged photos link to `TicketPhotoBeforeAfterView`.
public struct TicketDevicePhotoListView: View {
    let photos: [TicketDetail.TicketPhoto]
    let ticketId: Int64
    let uploadService: TicketPhotoUploadService?
    let onUpload: (() -> Void)?

    @State private var selectedPhoto: TicketDetail.TicketPhoto?
    @State private var showingUploadPicker = false
    @State private var showingBeforeAfter = false

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: BrandSpacing.sm)
    ]

    public init(
        photos: [TicketDetail.TicketPhoto],
        ticketId: Int64,
        uploadService: TicketPhotoUploadService? = nil,
        onUpload: (() -> Void)? = nil
    ) {
        self.photos = photos
        self.ticketId = ticketId
        self.uploadService = uploadService
        self.onUpload = onUpload
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoFullScreenView(photo: photo)
        }
        .sheet(isPresented: $showingBeforeAfter) {
            TicketPhotoBeforeAfterView(photos: photos)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Photos")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if hasBeforeAfter {
                Button {
                    showingBeforeAfter = true
                } label: {
                    Label("Before/After", systemImage: "rectangle.split.2x1")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreTeal)
                }
                .accessibilityLabel("View before and after comparison")
            }
            Button {
                onUpload?()
            } label: {
                Label("Add", systemImage: "plus.circle")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Add photo to ticket")
        }
    }

    private var hasBeforeAfter: Bool {
        let types = Set(photos.compactMap { $0.type })
        return types.contains("before") && types.contains("after")
    }

    // MARK: - Grid

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
            ForEach(photos) { photo in
                PhotoThumbnail(photo: photo) {
                    selectedPhoto = photo
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "photo.stack")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No photos yet")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.lg)
    }
}

// MARK: - Thumbnail

private struct PhotoThumbnail: View {
    let photo: TicketDetail.TicketPhoto
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: photo.url ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 100, height: 100)
                .clipped()
                .background(Color.bizarreSurface1)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if let type = photo.type, !type.isEmpty {
                    Text(type.uppercased())
                        .font(.brandLabelSmall())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo\(photo.type.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to view full-screen")
    }
}

// MARK: - Full screen preview

struct PhotoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: TicketDetail.TicketPhoto

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: photo.url ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(.white)
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }
            .navigationTitle(photo.type?.capitalized ?? "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .accessibilityLabel("Full screen photo\(photo.type.map { ", \($0)" } ?? "")")
    }
}
#endif
