#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §39.3 — X-report: mid-shift peek at current totals without closing the
/// shift. Mirrors `ZReportView` visually but reads from
/// `GET /cash-register/x-report` and labels itself "X-Report".
///
/// Server status: POS-XREPORT-001 pending → 501 displayed as "Coming soon"
/// banner while the endpoint is stub. The view handles this gracefully.
@MainActor
public struct XReportView: View {

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var comingSoon: Bool = false

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading X-report…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("xReport.loading")
                } else if comingSoon {
                    comingSoonView
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    comingSoonView  // default until endpoint ships
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("X-Report (mid-shift)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    // MARK: - Views

    private var comingSoonView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 52))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text("X-Report — Coming Soon")
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text("Mid-shift totals will appear here once the server endpoint (POS-XREPORT-001) is deployed.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.base)
            }

            // Manual summary from local register state
            Text("Current local session is tracked in the register's cash session store. Use the Z-report after closing the shift for full totals.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.base)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("xReport.comingSoon")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Could not load X-report")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.base)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("xReport.error")
    }

    // MARK: - Data

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        comingSoon = false
        defer { isLoading = false }

        do {
            _ = try await api.getXReport()
            // TODO: Render ZReportDTO tiles when endpoint ships
        } catch let APITransportError.httpStatus(code, _) where code == 501 {
            comingSoon = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#endif
