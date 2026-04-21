#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §4 — Side-by-side "before intake" vs "after repair" photo comparison.
public struct TicketPhotoBeforeAfterView: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [TicketDetail.TicketPhoto]

    private var beforePhotos: [TicketDetail.TicketPhoto] {
        photos.filter { $0.type == "before" }
    }
    private var afterPhotos: [TicketDetail.TicketPhoto] {
        photos.filter { $0.type == "after" }
    }

    public init(photos: [TicketDetail.TicketPhoto]) {
        self.photos = photos
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Before / After")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if beforePhotos.isEmpty && afterPhotos.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: BrandSpacing.base) {
                    let count = max(beforePhotos.count, afterPhotos.count)
                    ForEach(0..<count, id: \.self) { i in
                        BeforeAfterRow(
                            before: i < beforePhotos.count ? beforePhotos[i] : nil,
                            after: i < afterPhotos.count ? afterPhotos[i] : nil
                        )
                    }
                }
                .padding(BrandSpacing.base)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No before/after photos tagged")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tag photos as Before or After when uploading.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(BrandSpacing.base)
    }
}

// MARK: - Side-by-side row

private struct BeforeAfterRow: View {
    let before: TicketDetail.TicketPhoto?
    let after: TicketDetail.TicketPhoto?

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            photoPane(photo: before, label: "Before")
            photoPane(photo: after, label: "After")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Before and after comparison\(before == nil ? ", no before photo" : "")\(after == nil ? ", no after photo" : "")")
    }

    private func photoPane(photo: TicketDetail.TicketPhoto?, label: String) -> some View {
        VStack(spacing: BrandSpacing.xs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.bizarreSurface1)
                    .frame(height: 180)
                if let photo {
                    AsyncImage(url: URL(string: photo.url ?? "")) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(height: 180)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        default:
                            Image(systemName: "photo")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                } else {
                    VStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "photo")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text("No \(label.lowercased()) photo")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
