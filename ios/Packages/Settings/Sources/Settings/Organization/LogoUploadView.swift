import SwiftUI
import PhotosUI
import Observation
import Core
import DesignSystem

// MARK: - §19.5 Logo upload — renders on receipts / invoices / emails.

// MARK: - ViewModel

@MainActor
@Observable
public final class LogoUploadViewModel {

    public var logoURL: URL?
    public var selectedItem: PhotosPickerItem?
    public var isUploading: Bool = false
    public var errorMessage: String?
    public var successMessage: String?

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    public func loadExisting() async {
        guard let api else { return }
        do {
            let wire = try await api.settingsGetLogoURL()
            logoURL = wire.url.flatMap { URL(string: $0) }
        } catch {
            // No logo set yet — that's fine
        }
    }

    public func handleSelection() async {
        guard let item = selectedItem, let api else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read selected image."
                return
            }
            let wire = try await api.settingsUploadLogo(data, mimeType: "image/jpeg")
            logoURL = wire.url.flatMap { URL(string: $0) }
            successMessage = "Logo updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteLogo() async {
        guard let api else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        do {
            try await api.settingsDeleteLogo()
            logoURL = nil
            successMessage = "Logo removed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct LogoUploadView: View {

    @State private var vm: LogoUploadViewModel

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: LogoUploadViewModel(api: api))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            // Current logo preview
            logoPreview

            // Action buttons
            HStack(spacing: BrandSpacing.sm) {
                PhotosPicker(
                    selection: $vm.selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Upload logo", systemImage: "photo.badge.plus")
                        .font(.brandBodyMedium())
                }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("logo.upload")

                if vm.logoURL != nil {
                    Button(role: .destructive) {
                        Task { await vm.deleteLogo() }
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.brandBodyMedium())
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreError)
                    .accessibilityIdentifier("logo.remove")
                }
            }

            if vm.isUploading {
                ProgressView("Uploading…")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.secondary)
            }

            if let err = vm.errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
            if let ok = vm.successMessage {
                Text(ok)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreSuccess)
            }
        }
        .task { await vm.loadExisting() }
        .onChange(of: vm.selectedItem) { _, _ in
            Task { await vm.handleSelection() }
        }
    }

    @ViewBuilder
    private var logoPreview: some View {
        if let url = vm.logoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
                        .accessibilityLabel("Current logo")
                case .failure:
                    brokenLogoPlaceholder
                case .empty:
                    ProgressView()
                        .frame(height: 80)
                @unknown default:
                    brokenLogoPlaceholder
                }
            }
        } else {
            noLogoPlaceholder
        }
    }

    private var noLogoPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: BrandSpacing.xs) {
                Image(systemName: "photo.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No logo yet")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding()
            .frame(height: 80)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md))
            Spacer()
        }
    }

    private var brokenLogoPlaceholder: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.bizarreWarning)
            .frame(height: 80)
            .accessibilityLabel("Logo failed to load")
    }
}

#if DEBUG
#Preview {
    VStack {
        LogoUploadView(api: MockAPIClient())
    }
    .padding()
}
#endif
