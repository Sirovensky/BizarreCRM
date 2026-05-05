import SwiftUI
import Observation
import Core
import DesignSystem
#if canImport(UIKit)
import UIKit
import PhotosUI
#endif

// MARK: - ViewModel

@MainActor
@Observable
final class LogoStepViewModel {
#if canImport(UIKit)
    var selectedItem: PhotosPickerItem? = nil
    var logoImage: UIImage? = nil
#endif
    var uploadedURL: String? = nil
    var isUploading: Bool = false
    var uploadError: String? = nil

    @ObservationIgnored private let repository: (any SetupRepository)?

    init(repository: (any SetupRepository)?) {
        self.repository = repository
    }

#if canImport(UIKit)
    func loadSelectedItem() async {
        guard let item = selectedItem else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            uploadError = "Could not load selected image."
            return
        }
        logoImage = image
        uploadError = nil
        await upload(data: data)
    }

    /// Center-crop to square.
    /// TODO: Replace with an interactive cropper in a future PR.
    func squareCropped(from image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let x = (image.size.width  - side) / 2
        let y = (image.size.height - side) / 2
        let rect = CGRect(x: x, y: y, width: side, height: side)
        let scale = image.scale
        guard let cgImg = image.cgImage?.cropping(to: rect.applying(CGAffineTransform(scaleX: scale, y: scale))) else {
            return image
        }
        return UIImage(cgImage: cgImg, scale: scale, orientation: image.imageOrientation)
    }
#endif

    private func upload(data: Data) async {
        guard let repo = repository else {
            uploadedURL = "placeholder://logo"
            return
        }
        isUploading = true
        uploadError = nil
        defer { isUploading = false }
        do {
            uploadedURL = try await repo.uploadLogo(data: data)
            AppLog.ui.info("Logo uploaded: \(self.uploadedURL ?? "nil", privacy: .public)")
        } catch {
            uploadError = error.localizedDescription
        }
    }
}

// MARK: - View  (§36.2 Step 3 — Logo)

public struct LogoStepView: View {
    let repository: (any SetupRepository)?
    let onNext: (String?) -> Void

    @State private var vm: LogoStepViewModel

    public init(repository: (any SetupRepository)?, onNext: @escaping (String?) -> Void) {
        self.repository = repository
        self.onNext = onNext
        _vm = State(wrappedValue: LogoStepViewModel(repository: repository))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Text("Your Logo")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .padding(.top, BrandSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                logoPreview

                uploadButtons

                if vm.isUploading {
                    ProgressView("Uploading…")
                        .font(.brandBodyMedium())
                        .tint(.bizarreOrange)
                }

                if let err = vm.uploadError {
                    Text(err)
                        .font(.brandLabelSmall())
                        .foregroundStyle(Color.bizarreError)
                        .accessibilityLabel("Upload error: \(err)")
                }

                receiptPreviewSection

                Text("You can update your logo at any time in Settings.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)

                Spacer(minLength: BrandSpacing.lg)
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.bottom, BrandSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        #if canImport(UIKit)
        .onChange(of: vm.selectedItem) { _, _ in
            Task { await vm.loadSelectedItem() }
        }
        #endif
    }

    // MARK: Logo preview

    @ViewBuilder
    private var logoPreview: some View {
        #if canImport(UIKit)
        if let image = vm.logoImage {
            let cropped = vm.squareCropped(from: image)
            Image(uiImage: cropped)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.bizarreOutline, lineWidth: 1)
                )
                .accessibilityLabel("Your company logo preview")
        } else {
            logoPlaceholder
        }
        #else
        logoPlaceholder
        #endif
    }

    private var logoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.bizarreSurface1)
            .frame(width: 140, height: 140)
            .overlay {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.bizarreOutline)
            }
            .accessibilityLabel("Logo placeholder — tap to add your logo")
    }

    // MARK: Upload buttons

    @ViewBuilder
    private var uploadButtons: some View {
        #if canImport(UIKit)
        BrandGlassContainer {
            HStack(spacing: BrandSpacing.md) {
                PhotosPicker(
                    selection: $vm.selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.brandGlass)
                .accessibilityLabel("Take a photo with camera")

                PhotosPicker(
                    selection: $vm.selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.brandLabelLarge())
                }
                .buttonStyle(.brandGlass)
                .accessibilityLabel("Choose photo from library")
            }
        }
        #else
        Text("Photo picker available on iOS only.")
            .font(.brandBodyMedium())
            .foregroundStyle(Color.bizarreOnSurfaceMuted)
        #endif
    }

    // MARK: Receipt preview section

    @ViewBuilder
    private var receiptPreviewSection: some View {
        #if canImport(UIKit)
        if let image = vm.logoImage {
            receiptPreview(logo: vm.squareCropped(from: image))
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: Mock receipt card

    #if canImport(UIKit)
    @ViewBuilder
    private func receiptPreview(logo: UIImage) -> some View {
        VStack(alignment: .center, spacing: BrandSpacing.sm) {
            Text("Receipt Preview")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)

            VStack(spacing: BrandSpacing.sm) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                Divider()

                Text("Repair Receipt")
                    .font(.brandLabelLarge())
                    .foregroundStyle(Color.bizarreOnSurface)

                HStack {
                    Text("iPhone Screen")
                    Spacer()
                    Text("$149.99")
                }
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurface)

                Divider()

                HStack {
                    Text("Total")
                        .font(.brandTitleSmall())
                    Spacer()
                    Text("$149.99")
                        .font(.brandTitleSmall())
                }
                .foregroundStyle(Color.bizarreOnSurface)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 280)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample receipt showing your logo at the top")
    }
    #endif
}
