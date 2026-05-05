import SwiftUI
import Observation
import PhotosUI
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import Camera
import UIKit
#endif

// MARK: - ViewModel

/// Manages receipt photo upload for an existing expense via
/// `POST /api/v1/expenses/:id/receipt` (multipart/form-data).
@MainActor
@Observable
public final class ReceiptAttachViewModel {

    public enum UploadState: Sendable {
        case idle
        case uploading(progress: Double)
        case success(ExpenseReceiptUploadResponse)
        case failed(String)
    }

    public private(set) var uploadState: UploadState = .idle
    /// Controls the camera sheet.
    public var showingCamera: Bool = false
    /// Controls the photo library picker.
    public var showingPhotoLibrary: Bool = false
    /// `true` while OCR runs after capture.
    public private(set) var isOCRRunning: Bool = false
    /// OCR-extracted total, if any, surfaced to parent for amount pre-fill.
    public private(set) var ocrTotal: Double?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let expenseId: Int64
    @ObservationIgnored private let authToken: String?

    public init(api: APIClient, expenseId: Int64, authToken: String?) {
        self.api = api
        self.expenseId = expenseId
        self.authToken = authToken
    }

    // MARK: - Upload

#if canImport(UIKit)
    @MainActor
    public func handleCapturedImages(_ images: [UIImage]) async {
        showingCamera = false
        guard let image = images.first else { return }
        await ocrAndUpload(image: image)
    }

    @MainActor
    private func ocrAndUpload(image: UIImage) async {
        isOCRRunning = true
        if let total = await ReceiptEdgeDetector.ocrTotal(image) {
            ocrTotal = total
        }
        isOCRRunning = false
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            uploadState = .failed("Could not compress the receipt image.")
            return
        }
        await upload(imageData: data, mimeType: "image/jpeg", filename: "receipt.jpg")
    }
#endif

    /// Handles photo library item selection (cross-platform; OCR runs only on UIKit).
    @MainActor
    public func handlePhotoLibraryItem(_ item: PhotosPickerItem?) async {
        showingPhotoLibrary = false
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            uploadState = .failed("Could not load the selected photo.")
            return
        }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            uploadState = .failed("Could not decode the selected photo.")
            return
        }
        isOCRRunning = true
        if let total = await ReceiptEdgeDetector.ocrTotal(image) {
            ocrTotal = total
        }
        isOCRRunning = false
        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            uploadState = .failed("Could not compress the receipt image.")
            return
        }
        await upload(imageData: jpegData, mimeType: "image/jpeg", filename: "receipt.jpg")
        #else
        await upload(imageData: data, mimeType: "image/png", filename: "receipt.png")
        #endif
    }

    public func upload(imageData: Data, mimeType: String, filename: String) async {
        uploadState = .uploading(progress: 0)
        do {
            let response = try await api.uploadExpenseReceipt(
                expenseId: expenseId,
                imageData: imageData,
                mimeType: mimeType,
                filename: filename,
                authToken: authToken
            )
            uploadState = .success(response)
        } catch {
            AppLog.ui.error("Receipt upload failed: \(error.localizedDescription, privacy: .public)")
            uploadState = .failed(error.localizedDescription)
        }
    }

    public func resetToIdle() {
        uploadState = .idle
        ocrTotal = nil
    }
}

// MARK: - View

/// Sheet presenting camera + photo library receipt upload options.
/// Callers embed this as a `.sheet(...)` and observe `vm.uploadState` for
/// success/failure callbacks.
public struct ReceiptAttachView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ReceiptAttachViewModel
    @State private var photoLibraryItem: PhotosPickerItem?
    /// Callback fired on successful upload; carries the new receipt path.
    public let onSuccess: (String) -> Void

    public init(api: APIClient, expenseId: Int64, authToken: String?, onSuccess: @escaping (String) -> Void) {
        _vm = State(wrappedValue: ReceiptAttachViewModel(api: api, expenseId: expenseId, authToken: authToken))
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                mainContent
            }
            .navigationTitle("Attach Receipt")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("receipt.attach.cancel")
                }
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $vm.showingCamera) {
            PhotoCaptureView { images in
                Task { await vm.handleCapturedImages(images) }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        .onChange(of: photoLibraryItem) { _, newItem in
            Task { await vm.handlePhotoLibraryItem(newItem) }
        }
        .onChange(of: vm.uploadState.isSuccess) { _, success in
            if success, let path = vm.uploadState.successPath {
                onSuccess(path)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch vm.uploadState {
        case .idle:
            idleContent
        case .uploading:
            uploadingContent
        case .success:
            // onSuccess callback triggers dismiss; show a brief confirmation.
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreSuccess)
                    .accessibilityHidden(true)
                Text("Receipt uploaded")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Upload failed")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Try Again") { vm.resetToIdle() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Try uploading receipt again")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var idleContent: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Add a receipt photo")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Capture or import a photo of the receipt. Amount will be pre-filled if found.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            VStack(spacing: BrandSpacing.md) {
                #if canImport(UIKit)
                Button {
                    vm.showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("receipt.attach.camera")

                PhotosPicker(
                    selection: $photoLibraryItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("receipt.attach.library")
                #endif
            }
            .padding(.horizontal, BrandSpacing.xl)
            if vm.isOCRRunning {
                HStack(spacing: BrandSpacing.sm) {
                    ProgressView()
                    Text("Reading receipt…")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Reading receipt text")
            }
            Spacer()
        }
    }

    private var uploadingContent: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityLabel("Uploading receipt")
            Text("Uploading…")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ReceiptAttachViewModel.UploadState helpers

private extension ReceiptAttachViewModel.UploadState {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var successPath: String? {
        if case .success(let r) = self { return r.filePath }
        return nil
    }
}
