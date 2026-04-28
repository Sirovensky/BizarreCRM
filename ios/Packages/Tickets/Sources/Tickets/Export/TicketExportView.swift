#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import Networking

// §4.1 — Export CSV.
// Route: GET /api/v1/tickets/export
// Server streams CSV with Content-Disposition: attachment; filename="tickets-export.csv".
//
// iPhone/iPad: presents SFSafariViewController which triggers the browser download flow.
// Mac (Designed for iPad): opens the URL in the default browser.
//
// The view is presented as a sheet from the list toolbar. It respects the
// active filter + search keyword so the export matches what the user sees.

public struct TicketExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isDownloading: Bool = false
    @State private var downloadedFile: URL?
    @State private var errorMessage: String?

    private let api: APIClient
    private let filter: TicketListFilter
    private let keyword: String?
    private let sort: TicketSortOrder

    public init(
        api: APIClient,
        filter: TicketListFilter = .all,
        keyword: String? = nil,
        sort: TicketSortOrder = .newest
    ) {
        self.api = api
        self.filter = filter
        self.keyword = keyword
        self.sort = sort
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Export Tickets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel export")
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.xs) {
                Text("Export as CSV")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Download up to 10,000 tickets matching your current filter.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }

            filterSummary

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                    .accessibilityLabel("Export error: \(err)")
            }

            Button {
                Task { await downloadAndShare() }
            } label: {
                Group {
                    if isDownloading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Download CSV", systemImage: "arrow.down.circle.fill")
                            .font(.brandBodyLarge())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, BrandSpacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(isDownloading)
            .padding(.horizontal, BrandSpacing.lg)
            .accessibilityLabel("Download tickets as CSV")
        }
        .padding(BrandSpacing.lg)
    }

    private var filterSummary: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Filter: \(filter.displayName)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let kw = keyword, !kw.isEmpty {
                    Text("Keyword: \"\(kw)\"")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .padding(.horizontal, BrandSpacing.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(filter.displayName)\(keyword.map { ", keyword: \($0)" } ?? "")")
    }

    // MARK: - Helpers

    private func downloadAndShare() async {
        isDownloading = true
        defer { isDownloading = false }
        errorMessage = nil
        guard let file = await api.downloadTicketsCSV(filter: filter, keyword: keyword, sort: sort) else {
            errorMessage = "Could not download CSV. Make sure you're signed in and online."
            return
        }
        downloadedFile = file
        await MainActor.run { presentShareSheet(for: file) }
    }

    @MainActor
    private func presentShareSheet(for file: URL) {
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let vc = window.rootViewController else { return }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = window
            let bounds = window.bounds
            popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        // Walk presentation chain to top-most VC.
        var top: UIViewController = vc
        while let presented = top.presentedViewController { top = presented }
        top.present(activity, animated: true)
    }
}
#endif
