import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
import DesignSystem

// MARK: - §19.1 AvatarPickerSheet

/// PHPicker-based avatar picker.
/// If an upload endpoint becomes available the `onUpload` closure receives the
/// picked image data. Until then a "coming soon" toast is shown and no data
/// is transmitted.
///
/// Upload endpoint status: no `/settings/profile/avatar` endpoint exists on
/// the server.  The picker shows a "coming soon" banner instead of uploading.
public struct AvatarPickerSheet: View {

    public let currentAvatarUrl: String?
    public let onUpload: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showComingSoon: Bool = false

    #if canImport(PhotosUI)
    @State private var selectedItem: PhotosPickerItem?
    @State private var pickedImage: Image?
    #endif

    public init(
        currentAvatarUrl: String?,
        onUpload: @escaping (Data) -> Void
    ) {
        self.currentAvatarUrl = currentAvatarUrl
        self.onUpload = onUpload
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                // Current avatar preview
                currentAvatarPreview
                    .frame(width: 120, height: 120)
                    .padding(.top, DesignTokens.Spacing.xxl)

                Text("Profile Photo")
                    .font(.title2.bold())
                    .foregroundStyle(.bizarreOnSurface)

                // Coming-soon banner
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "clock.badge")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.bizarreWarning)
                    Text("Avatar upload coming soon.")
                        .font(.subheadline)
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .padding(DesignTokens.Spacing.md)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .padding(.horizontal, DesignTokens.Spacing.lg)

                #if canImport(PhotosUI)
                // PHPicker button — picks but does not upload
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.md)
                        .brandGlass(.regular, interactive: true)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .onChange(of: selectedItem) { _, newItem in
                    Task { await handlePickedItem(newItem) }
                }
                #endif

                Spacer()
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Change Photo")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("avatarPicker.cancel")
                }
            }
            // Show "coming soon" toast when user actually picks a photo
            .overlay(alignment: .bottom) {
                if showComingSoon {
                    comingSoonToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, DesignTokens.Spacing.xxl)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showComingSoon)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var currentAvatarPreview: some View {
        if let rawUrl = currentAvatarUrl, let imageURL = URL(string: rawUrl) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    placeholderCircle
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.bizarreOutline, lineWidth: 1.5))
        } else {
            placeholderCircle
        }
    }

    private var placeholderCircle: some View {
        Circle()
            .fill(Color.bizarrePrimary.opacity(0.12))
            .overlay {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(28)
                    .foregroundStyle(.bizarreOrange)
            }
    }

    private var comingSoonToast: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "clock")
                .foregroundStyle(.bizarreWarning)
            Text("Avatar upload coming soon")
                .font(.footnote.bold())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .brandGlass(.regular, in: Capsule())
        .accessibilityLabel("Avatar upload coming soon")
    }

    // MARK: - Actions

    #if canImport(PhotosUI)
    @MainActor
    private func handlePickedItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        // No upload endpoint exists — show the coming-soon toast and discard data.
        showComingSoon = true
        // Auto-dismiss toast after 2.5 s
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        showComingSoon = false
        // If/when an upload endpoint ships, call onUpload(data) here instead.
        _ = item  // silence unused-variable warning
    }
    #endif
}
