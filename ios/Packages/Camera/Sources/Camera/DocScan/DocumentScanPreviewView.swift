#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem

// MARK: - DocumentScanPreviewView

/// Post-scan review sheet. Displays a scrollable grid of page thumbnails.
/// The user can delete individual pages, reorder them via drag-and-drop, and
/// tap "Attach" to upload the assembled PDF.
///
/// iPhone: full-height sheet.
/// iPad: centered sheet at 520 pt fixed width (matches the POS sheet family).
///
/// Accessibility:
/// - Each page thumbnail has label "Page N of total, tap to remove" per spec.
/// - Drag handles are labeled for VoiceOver users.
/// - Attach button is disabled when no pages remain or upload is in progress.
///
/// Reduce Motion: the reorder animation is replaced with an instant snap when
/// `accessibilityReduceMotion` is active.
public struct DocumentScanPreviewView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - ViewModel

    @Bindable var viewModel: DocumentScanViewModel

    // MARK: - Local state

    @State private var isEditMode: EditMode = .active
    @State private var showScanMore: Bool = false

    // MARK: - Init

    public init(viewModel: DocumentScanViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            contentBody
                .navigationTitle("Scanned Document")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .environment(\.editMode, $isEditMode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // iPad: fixed 520pt width sheet
        .frame(idealWidth: 520)
        // §17: "Bulk append multiple scans to single file"
        .sheet(isPresented: $showScanMore) {
            DocumentScannerView { additionalPages in
                viewModel.appendPages(additionalPages)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        Group {
            if viewModel.pages.isEmpty {
                emptyState
            } else {
                pageList
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if case .uploading = viewModel.uploadState {
                uploadingBanner
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No pages scanned")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Scan a document to preview and attach pages here.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No pages scanned. Scan a document to preview and attach pages.")
    }

    private var pageList: some View {
        List {
            // §17 auto-classification chip
            if let tag = viewModel.suggestedTag {
                classificationBanner(tag: tag)
            }

            ForEach(Array(viewModel.pages.enumerated()), id: \.offset) { index, image in
                pageRow(image: image, index: index, total: viewModel.pages.count)
                    .listRowInsets(EdgeInsets(
                        top: BrandSpacing.sm,
                        leading: BrandSpacing.base,
                        bottom: BrandSpacing.sm,
                        trailing: BrandSpacing.base
                    ))
                    .listRowBackground(Color.bizarreSurfaceBase)
            }
            .onDelete { offsets in
                offsets.forEach { viewModel.deletePage(at: $0) }
            }
            .onMove { source, destination in
                withAnimation(reduceMotion ? nil : .default) {
                    viewModel.movePages(fromOffsets: source, toOffset: destination)
                }
            }

            // §17: "Bulk append multiple scans to single file" — Scan More button
            Section {
                Button {
                    showScanMore = true
                } label: {
                    Label("Scan More Pages", systemImage: "plus.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .listRowBackground(Color.bizarreSurfaceBase)
                .accessibilityLabel("Scan more pages and append to this document")
                .accessibilityIdentifier("docScan.scanMore")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Auto-classification banner

    @ViewBuilder
    private func classificationBanner(tag: DocumentTag) -> some View {
        Section {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: tag.systemImageName)
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested tag")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                    Text(tag.rawValue)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreSuccess)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.bizarreSuccess.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Auto-classified as \(tag.rawValue). Classification is based on document text.")
    }

    private func pageRow(image: UIImage, index: Int, total: Int) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.bizarreOnSurfaceMuted.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Page \(index + 1)")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("of \(total)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    viewModel.deletePage(at: index)
                }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.bizarreError)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove page \(index + 1)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(index + 1) of \(total), tap to remove")
    }

    // MARK: - Uploading banner

    private var uploadingBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            ProgressView()
                .tint(.bizarreOrange)
            Text("Uploading document…")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, BrandSpacing.base)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("docScan.cancel")
        }

        ToolbarItem(placement: .navigationBarLeading) {
            // §17: "Bulk append" — additional scan button in toolbar
            if !viewModel.pages.isEmpty {
                Button {
                    showScanMore = true
                } label: {
                    Image(systemName: "plus.viewfinder")
                }
                .accessibilityLabel("Scan more pages")
                .accessibilityIdentifier("docScan.scanMoreToolbar")
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            attachButton
        }
    }

    @ViewBuilder
    private var attachButton: some View {
        switch viewModel.uploadState {
        case .uploading:
            ProgressView()
                .tint(.bizarreOrange)
        case .success:
            Button("Done") { dismiss() }
                .accessibilityIdentifier("docScan.done")
        case .failure(let msg):
            Button {
                Task { await viewModel.attach() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .tint(.bizarreError)
            .accessibilityHint(msg)
            .accessibilityIdentifier("docScan.retry")
        case .idle:
            Button {
                Task { await viewModel.attach() }
            } label: {
                Text("Attach")
                    .font(.brandBodyMedium())
            }
            .disabled(viewModel.pages.isEmpty)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("docScan.attach")
        }
    }
}
#endif
