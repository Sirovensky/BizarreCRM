#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5.2 Photo mementos — recent repair photos gallery (horizontal scroll)

/// Displays a horizontal scroll gallery of recent repair photos attached to a customer's tickets.
/// Photos come from `GET /customers/:id/assets?kind=photo`.
public struct CustomerPhotoMementosSection: View {
    let customerId: Int64
    let api: APIClient

    @State private var photos: [CustomerPhoto] = []
    @State private var isLoading = true
    @State private var selectedPhoto: CustomerPhoto?

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        self.api = api
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .accessibilityLabel("Loading repair photos")
            } else if photos.isEmpty {
                EmptyView()
            } else {
                photoGallery
            }
        }
        .task { await load() }
    }

    // MARK: - Gallery

    private var photoGallery: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("REPAIR PHOTOS")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(photos.count)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: BrandSpacing.sm) {
                    ForEach(photos) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            photoThumbnail(photo)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Repair photo: \(photo.altText)")
                    }
                }
                .padding(.horizontal, BrandSpacing.xxs)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoLightboxView(photo: photo)
        }
    }

    private func photoThumbnail(_ photo: CustomerPhoto) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSurface2)
                .frame(width: 80, height: 80)
            AsyncImage(url: URL(string: photo.thumbnailURL ?? photo.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                case .empty:
                    ProgressView().frame(width: 80, height: 80)
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 24))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .frame(width: 80, height: 80)
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .frame(width: 80, height: 80)
        .hoverEffect(.highlight)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            photos = try await api.customerRepairPhotos(customerId: customerId)
        } catch {
            photos = []
        }
    }
}

// MARK: - Lightbox

private struct PhotoLightboxView: View {
    let photo: CustomerPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .gesture(MagnificationGesture()
                                .onChanged { v in scale = max(1, min(6, v)) }
                                .onEnded { _ in withAnimation(.spring()) { scale = 1 } })
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) { scale = scale > 1 ? 1 : 3 }
                            }
                    case .empty:
                        ProgressView().tint(.white)
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.white).font(.system(size: 48))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(photo.altText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.system(size: 22))
                    }
                    .accessibilityLabel("Close photo")
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

// MARK: - Model

public struct CustomerPhoto: Identifiable, Decodable, Sendable {
    public let id: Int64
    public let url: String
    public let thumbnailURL: String?
    public let altText: String
    public let ticketId: Int64?
    public let capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case thumbnailURL = "thumbnail_url"
        case altText      = "alt_text"
        case ticketId     = "ticket_id"
        case capturedAt   = "captured_at"
    }
}

// MARK: - Endpoint

extension APIClient {
    /// `GET /customers/:id/assets?kind=photo` — fetch repair photos for a customer.
    public func customerRepairPhotos(customerId: Int64) async throws -> [CustomerPhoto] {
        let q = [URLQueryItem(name: "kind", value: "photo")]
        return try await get("/customers/\(customerId)/assets", query: q, as: [CustomerPhoto].self)
    }
}

#endif
