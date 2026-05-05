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
            PhotoFullScreenView(photo: photo, siblings: photos)
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

// MARK: - Full screen preview (pinch-zoom + swipe navigation + share)

/// §4.2 — Full-screen photo gallery with pinch-zoom (0.5×–6×), swipe navigation,
/// share sheet, and delete-via-swipe.
struct PhotoFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let photo: TicketDetail.TicketPhoto
    /// Optional sibling photos for swipe navigation.
    let siblings: [TicketDetail.TicketPhoto]

    init(photo: TicketDetail.TicketPhoto, siblings: [TicketDetail.TicketPhoto] = []) {
        self.photo = photo
        self.siblings = siblings
    }

    @State private var currentIndex: Int = 0
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var cachedImages: [Int: UIImage] = [:]
    @State private var showingShareSheet = false
    @State private var shareImage: UIImage?

    private var items: [TicketDetail.TicketPhoto] {
        siblings.isEmpty ? [photo] : siblings
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                        ZoomablePhotoView(photo: p, onImageLoaded: { img in
                            cachedImages[idx] = img
                        })
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .onChange(of: currentIndex) { _, _ in
                scale = 1
                offset = .zero
            }
            .navigationTitle(currentPhoto?.type?.capitalized ?? "Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                        .accessibilityLabel("Close photo viewer")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if let img = cachedImages[currentIndex] {
                            shareImage = img
                        }
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Share this photo")
                }
                if items.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Text("\(currentIndex + 1) of \(items.count)")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.white)
                            .accessibilityLabel("Photo \(currentIndex + 1) of \(items.count)")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let img = shareImage {
                    ShareSheet(items: [img])
                } else if let urlStr = currentPhoto?.url, let url = URL(string: urlStr) {
                    ShareSheet(items: [url])
                }
            }
        }
        .onAppear {
            if let idx = items.firstIndex(where: { $0.id == photo.id }) {
                currentIndex = idx
            }
        }
        .accessibilityLabel("Full screen photo gallery. \(items.count) photos.")
    }

    private var currentPhoto: TicketDetail.TicketPhoto? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }
}

// MARK: - Zoomable photo (MagnificationGesture + DragGesture)

private struct ZoomablePhotoView: View {
    let photo: TicketDetail.TicketPhoto
    let onImageLoaded: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 0.5
    private let maxScale: CGFloat = 6.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                AsyncImage(url: URL(string: photo.url ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let newScale = lastScale * value
                                            scale = min(max(newScale, minScale), maxScale)
                                        }
                                        .onEnded { _ in
                                            if scale < 1 {
                                                withAnimation(.spring(duration: 0.3)) {
                                                    scale = 1
                                                    offset = .zero
                                                }
                                            }
                                            lastScale = scale
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            guard scale > 1 else { return }
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(duration: 0.3)) {
                                    if scale > 1 {
                                        scale = 1
                                        offset = .zero
                                        lastOffset = .zero
                                        lastScale = 1
                                    } else {
                                        scale = 2.5
                                        lastScale = 2.5
                                    }
                                }
                            }
                            .onAppear {
                                // Cache image for sharing
                                Task {
                                    if let url = URL(string: photo.url ?? ""),
                                       let data = try? Data(contentsOf: url),
                                       let uiImage = UIImage(data: data) {
                                        onImageLoaded(uiImage)
                                    }
                                }
                            }
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

// MARK: - UIActivityViewController wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
