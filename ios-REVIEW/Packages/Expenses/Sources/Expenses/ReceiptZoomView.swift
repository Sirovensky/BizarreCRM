// §11.2 ReceiptZoomView — full-screen receipt photo viewer with pinch-to-zoom.
//
// Spec: "Receipt photo preview (full-screen zoom, pinch)" — §11.2.

#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// Full-screen receipt viewer sheet.
/// - Resolves the server-relative path against `APIClient.currentBaseURL()`.
/// - Supports pinch-to-zoom and double-tap-to-fit via `MagnificationGesture`.
/// - Reduce Motion: disables the spring animation on the magnification snap-back.
@MainActor
public struct ReceiptZoomView: View {
    let api: APIClient
    let path: String
    let onDismiss: () -> Void

    @State private var resolvedURL: URL?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(api: APIClient, path: String, onDismiss: @escaping () -> Void) {
        self.api = api
        self.path = path
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            contentLayer
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await resolve() }
        .accessibilityLabel("Full-screen receipt photo")
    }

    // MARK: - Content

    @ViewBuilder
    private var contentLayer: some View {
        if let url = resolvedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading receipt")
                case .success(let image):
                    zoomableImage(image)
                case .failure:
                    VStack(spacing: BrandSpacing.md) {
                        Image(systemName: "photo.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityHidden(true)
                        Text("Couldn't load receipt photo")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Receipt photo failed to load")
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Resolving receipt URL")
        }
    }

    private func zoomableImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    // Pinch to zoom
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(lastScale * value, 6.0))
                        }
                        .onEnded { value in
                            lastScale = scale
                            if scale < 1.05 {
                                // Snap back to fit
                                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                }
                                lastScale = 1.0
                                lastOffset = .zero
                            }
                        },
                    // Pan when zoomed
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.05 else { return }
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
            // Double-tap to reset zoom
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = scale > 1.5 ? 1.0 : 2.5
                    if scale == 1.0 { offset = .zero; lastOffset = .zero }
                }
                lastScale = scale > 1.5 ? 1.0 : 2.5
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Receipt photo. Pinch to zoom, double-tap to toggle zoom.")
    }

    // MARK: - Close button

    private var closeButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
        }
        .padding(BrandSpacing.lg)
        .accessibilityLabel("Close receipt viewer")
        .keyboardShortcut(.escape, modifiers: [])
    }

    // MARK: - URL resolution

    private func resolve() async {
        guard let base = await api.currentBaseURL() else { return }
        if path.hasPrefix("http") {
            resolvedURL = URL(string: path)
        } else {
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            resolvedURL = base.appendingPathComponent(trimmed)
        }
    }
}
#endif
