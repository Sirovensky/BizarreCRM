#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §40 — Store-credit balance + transaction history for a customer.
///
/// `GET /api/v1/refunds/credits/:customerId`
///
/// iPhone: scrollable list in a `.large` sheet.
/// iPad: sidebar-style detail view with header balance card and sortable
/// transaction table. Uses `Table` for iPad to leverage the wider column.
///
/// Data is loaded once on appear; pull-to-refresh triggers a reload.
struct StoreCreditList: View {
    @Environment(\.dismiss) private var dismiss
    let customerId: Int64
    let api: APIClient

    // MARK: - State

    enum LoadState {
        case idle
        case loading
        case loaded(StoreCreditDetail)
        case failure(String)
    }

    @State private var loadState: LoadState = .idle

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if Platform.isCompact {
                    phoneLayout
                } else {
                    padLayout
                }
            }
            .navigationTitle("Store Credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled({ if case .loading = loadState { return true }; return false }())
                    .accessibilityLabel("Refresh")
                    .accessibilityIdentifier("storeCredit.refresh")
                }
            }
        }
        .presentationDetents(Platform.isCompact ? [.large] : [.large])
        .presentationDragIndicator(.visible)
        .frame(idealWidth: Platform.isCompact ? nil : 560)
        .task { await load() }
    }

    // MARK: - Phone layout

    private var phoneLayout: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                loadingView
            case .failure(let msg):
                errorView(msg)
            case .loaded(let detail):
                phoneList(detail: detail)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .refreshable { await load() }
    }

    private func phoneList(detail: StoreCreditDetail) -> some View {
        List {
            Section {
                balanceHeader(balanceCents: detail.balanceCents)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
            }
            if detail.transactions.isEmpty {
                Section {
                    Text("No transactions yet.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            } else {
                Section("Transactions") {
                    ForEach(detail.transactions) { tx in
                        transactionRow(tx)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        Group {
            switch loadState {
            case .idle, .loading:
                loadingView
            case .failure(let msg):
                errorView(msg)
            case .loaded(let detail):
                padDetail(detail: detail)
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .refreshable { await load() }
    }

    private func padDetail(detail: StoreCreditDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            balanceHeader(balanceCents: detail.balanceCents)
                .padding(BrandSpacing.base)

            if detail.transactions.isEmpty {
                Text("No transactions yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .padding(BrandSpacing.base)
            } else {
                Table(detail.transactions) {
                    TableColumn("Date") { tx in
                        Text(formattedDate(tx.createdAt))
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                    }
                    TableColumn("Type") { tx in
                        Text(tx.type.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                    TableColumn("Amount") { tx in
                        Text(CartMath.formatCents(tx.amountCents))
                            .font(.brandTitleSmall())
                            .monospacedDigit()
                            .foregroundStyle(.bizarreOrange)
                    }
                    TableColumn("Notes") { tx in
                        Text(tx.notes ?? "—")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .hoverEffect(.highlight)
            }
        }
    }

    // MARK: - Common sub-views

    private func balanceHeader(balanceCents: Int) -> some View {
        HStack(spacing: BrandSpacing.base) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bizarreOrange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Available Balance")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(CartMath.formatCents(balanceCents))
                    .font(.brandTitleLarge())
                    .monospacedDigit()
                    .foregroundStyle(balanceCents > 0 ? .bizarreOrange : .bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.base)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available store credit: \(CartMath.formatCents(balanceCents))")
    }

    private func transactionRow(_ tx: StoreCreditTransaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(tx.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let notes = tx.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Text(formattedDate(tx.createdAt))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
            Text(CartMath.formatCents(tx.amountCents))
                .font(.brandTitleSmall())
                .monospacedDigit()
                .foregroundStyle(.bizarreOrange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tx.type) \(CartMath.formatCents(tx.amountCents)) on \(formattedDate(tx.createdAt))")
    }

    private var loadingView: some View {
        VStack(spacing: BrandSpacing.md) {
            ProgressView("Loading…")
                .padding(.top, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreError)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
            Button("Retry") { Task { await load() } }
                .buttonStyle(.bordered)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("storeCredit.error")
    }

    // MARK: - Data loading

    private func load() async {
        loadState = .loading
        do {
            let detail = try await api.getStoreCreditDetail(customerId: customerId)
            loadState = .loaded(detail)
        } catch let APITransportError.httpStatus(code, message) {
            let msg = message?.isEmpty == false ? message! : "Load failed"
            loadState = .failure("Failed to load store credit (\(code)): \(msg)")
        } catch {
            loadState = .failure("Failed to load store credit: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                let display = DateFormatter()
                display.dateStyle = .medium
                display.timeStyle = .short
                return display.string(from: date)
            }
        }
        return raw
    }
}
#endif
