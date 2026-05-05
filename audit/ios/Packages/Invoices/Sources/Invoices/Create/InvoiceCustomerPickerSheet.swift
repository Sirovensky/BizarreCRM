#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - InvoiceCustomerPickerSheet
//
// §7.3 Customer picker for invoice create form.
// Searches GET /api/v1/customers?search=<query>.
// Self-contained search + selection — caller receives (id, displayName) on pick.

public struct InvoiceCustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [CustomerPickerRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let api: APIClient
    public let onPick: (Int64, String) -> Void

    public init(api: APIClient, onPick: @escaping (Int64, String) -> Void) {
        self.api = api
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        TextField("Search customers…", text: $query)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .autocorrectionDisabled()
                            .onChange(of: query) { _, newVal in
                                scheduleSearch(query: newVal)
                            }
                            .accessibilityLabel("Search customers by name or phone")
                        if !query.isEmpty {
                            Button {
                                query = ""
                                results = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(BrandSpacing.md)
                    .background(Color.bizarreSurface1,
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.vertical, BrandSpacing.sm)

                    if isLoading {
                        ProgressView()
                            .padding(.top, BrandSpacing.xl)
                            .accessibilityLabel("Searching customers")
                        Spacer()
                    } else if let err = errorMessage {
                        ContentUnavailableView(
                            "Search failed",
                            systemImage: "exclamationmark.triangle",
                            description: Text(err)
                        )
                    } else if results.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        List(results) { row in
                            Button {
                                onPick(row.id, row.displayName)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                                    Text(row.displayName)
                                        .font(.brandBodyMedium())
                                        .foregroundStyle(.bizarreOnSurface)
                                    if let phone = row.phone, !phone.isEmpty {
                                        Text(phone)
                                            .font(.brandLabelSmall())
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                }
                            }
                            .accessibilityLabel("\(row.displayName)\(row.phone.map { ", \($0)" } ?? "")")
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Pick Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.bizarreOrange)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Debounced search

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        errorMessage = nil
        guard query.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await runSearch(query: query)
        }
    }

    @MainActor
    private func runSearch(query: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await api.get(
                "/api/v1/customers",
                query: [URLQueryItem(name: "search", value: query),
                        URLQueryItem(name: "limit", value: "30")],
                as: CustomerPickerListResponse.self
            )
            results = items.customers
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Response models

public struct CustomerPickerRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let displayName: String
    public let phone: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case phone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = (try? c.decode(Int64.self,  forKey: .id))          ?? 0
        displayName = (try? c.decode(String.self, forKey: .displayName)) ?? ""
        phone       = try? c.decode(String.self, forKey: .phone)
    }
}

private struct CustomerPickerListResponse: Decodable, Sendable {
    let customers: [CustomerPickerRow]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customers = (try? c.decode([CustomerPickerRow].self, forKey: .customers)) ?? []
    }

    enum CodingKeys: String, CodingKey { case customers }
}
#endif
