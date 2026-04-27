#if canImport(UIKit)
import SwiftUI
import SafariServices
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
    @State private var isBuilding: Bool = false
    @State private var exportURL: URL?
    @State private var errorMessage: String?
    @State private var showingSafari: Bool = false

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
        .sheet(isPresented: $showingSafari) {
            if let url = exportURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task { await buildExportURL() }
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
                guard let url = exportURL else { return }
                if Platform.isMac {
                    // On Mac, open in external browser.
                    UIApplication.shared.open(url)
                    dismiss()
                } else {
                    showingSafari = true
                }
            } label: {
                Group {
                    if isBuilding {
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
            .disabled(isBuilding || exportURL == nil)
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

    private func buildExportURL() async {
        isBuilding = true
        defer { isBuilding = false }
        if let url = await api.exportTicketsURL(filter: filter, keyword: keyword, sort: sort) {
            exportURL = url
        } else {
            errorMessage = "Server address not configured. Please log in first."
        }
    }
}

// MARK: - Safari bridge

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: cfg)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
