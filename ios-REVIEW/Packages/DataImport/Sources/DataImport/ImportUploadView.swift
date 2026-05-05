import SwiftUI
import Core
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ImportUploadView

public struct ImportUploadView: View {
    @Bindable var vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xxl) {
                header

                if let filename = vm.selectedFilename {
                    fileCard(filename: filename, size: vm.selectedFileSize)
                } else {
                    pickButton
                }

                if vm.isLoading {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        ProgressView(value: vm.uploadProgress)
                            .tint(.bizarreOrange)
                            .accessibilityLabel("Upload progress \(Int(vm.uploadProgress * 100)) percent")
                        Text("Uploading…")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                }

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .accessibilityLabel("Error: \(err)")
                }
            }
            .padding(.top, DesignTokens.Spacing.xxl)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showingPicker) {
            DocumentPickerView { url in
                handlePicked(url: url)
            }
        }
    }

    @State private var showingPicker = false

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Upload File")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text("Select a CSV or Excel file from your device")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityAddTraits(.isHeader)
    }

    private var pickButton: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 24))
                    .accessibilityHidden(true)
                Text("Choose File")
                    .font(.brandBodyLarge())
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(DesignTokens.Spacing.lg)
        }
        .buttonStyle(.brandGlass)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityLabel("Choose a file to import")
        .accessibilityIdentifier("import.upload.pick")
        .disabled(vm.isLoading)
    }

    private func fileCard(filename: String, size: Int64) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(filename)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(2)
                    Text(formatFileSize(size))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                if !vm.isLoading {
                    Button {
                        showingPicker = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    .accessibilityLabel("Change file")
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(filename), \(formatFileSize(size))")
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func handlePicked(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let filename = url.lastPathComponent
        let size = Int64(data.count)
        vm.selectedFilename = filename
        vm.selectedFileSize = size
        Task { @MainActor in
            await vm.uploadFile(data: data, filename: filename)
        }
    }
}

// MARK: - DocumentPickerView (UIDocumentPickerViewController wrapper)

#if canImport(UIKit)
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                UTType.commaSeparatedText,
                UTType.spreadsheet,
                UTType(filenameExtension: "xlsx") ?? .data
            ]
        )
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
#else
struct DocumentPickerView: View {
    let onPick: (URL) -> Void
    var body: some View { EmptyView() }
}
#endif
