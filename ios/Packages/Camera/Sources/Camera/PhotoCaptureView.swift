#if canImport(UIKit)
import SwiftUI
import PhotosUI
import Core
import DesignSystem
import UIKit

/// Photo-picker surface. Thin `PhotosPicker` wrapper that emits up to
/// 10 `UIImage`s via `onCaptured`. Selection limit mirrors the ticket
/// attachment cap on the server — higher would reject at upload time.
///
/// Rationale for `PhotosPicker` instead of a custom `UIImagePicker`:
/// it runs out-of-process, doesn't require `NSPhotoLibraryUsageDescription`,
/// and is the Apple-blessed entry point since iOS 16. Live camera capture
/// still flows through §17.2's `DataScannerViewController` wrapper when
/// we need barcode-capable camera sessions.
public struct PhotoCaptureView: View {
    let onCaptured: ([UIImage]) -> Void

    @State private var selection: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var isLoading: Bool = false
    @State private var loadErrorMessage: String?

    /// Max images per batch. Matches the server-side ticket attachment
    /// cap — bumping this requires a server change too.
    private static let selectionLimit = 10

    public init(onCaptured: @escaping ([UIImage]) -> Void) {
        self.onCaptured = onCaptured
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: BrandSpacing.lg) {
                    header

                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: Self.selectionLimit,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Pick up to \(Self.selectionLimit) photos", systemImage: "photo.on.rectangle.angled")
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnOrange)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.bizarreOrange, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("photoCapture.pickButton")
                    .accessibilityLabel("Pick up to \(Self.selectionLimit) photos")
                    .padding(.horizontal, BrandSpacing.base)

                    if isLoading {
                        ProgressView().padding(.vertical, BrandSpacing.sm)
                    }

                    if let loadErrorMessage {
                        Text(loadErrorMessage)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                            .padding(.horizontal, BrandSpacing.base)
                    }

                    grid
                }
                .padding(.bottom, BrandSpacing.lg)
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") {
                        BrandHaptics.success()
                        onCaptured(images)
                    }
                    .disabled(images.isEmpty)
                    .accessibilityIdentifier("photoCapture.attachButton")
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            Task { await loadSelections(newValue) }
        }
    }

    private var header: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Attach Photos")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Before/after photos attached to tickets. Up to \(Self.selectionLimit) per batch.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .padding(.top, BrandSpacing.xl)
    }

    /// Inline 3-column grid with tap-to-remove. Remove gesture is the
    /// same as the picker cell so users don't need to re-enter the
    /// picker to drop a bad shot.
    @ViewBuilder
    private var grid: some View {
        if !images.isEmpty {
            let columns = [GridItem(.adaptive(minimum: 96), spacing: BrandSpacing.sm)]
            LazyVGrid(columns: columns, spacing: BrandSpacing.sm) {
                ForEach(Array(images.enumerated()), id: \.offset) { pair in
                    PhotoThumbCell(image: pair.element) {
                        BrandHaptics.tap()
                        removeImage(at: pair.offset)
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
        }
    }

    /// Resolves every `PhotosPickerItem` concurrently into a `UIImage`.
    /// Items that fail to decode are silently dropped (the user still
    /// sees whatever loaded). Large selections cap at `selectionLimit`
    /// at the picker layer so we don't race away from the UI here.
    private func loadSelections(_ items: [PhotosPickerItem]) async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        var loaded: [UIImage] = []
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            } catch {
                AppLog.ui.error("PhotoCaptureView load failed: \(error.localizedDescription, privacy: .public)")
                loadErrorMessage = "Some photos couldn't be loaded."
            }
        }
        images = loaded
    }

    private func removeImage(at index: Int) {
        guard images.indices.contains(index) else { return }
        var next = images
        next.remove(at: index)
        images = next
        // Mirror selection drop so the next picker open doesn't
        // re-hydrate the just-removed item.
        if selection.indices.contains(index) {
            var nextSel = selection
            nextSel.remove(at: index)
            selection = nextSel
        }
    }
}

/// Single thumbnail cell. Tappable to remove; the `xmark.circle.fill`
/// overlay signals destructive intent. Square 1:1 so grid rows stay
/// even regardless of source aspect.
private struct PhotoThumbCell: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
                    )
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, Color.black.opacity(0.55))
                    .font(.system(size: 20))
                    .padding(4)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove photo")
        .accessibilityIdentifier("photoCapture.remove")
    }
}

#Preview {
    PhotoCaptureView { _ in }
        .preferredColorScheme(.dark)
}
#endif
