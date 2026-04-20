import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class GlobalSearchViewModel {
    public private(set) var results: GlobalSearchResults?
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var query: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient) { self.api = api }

    public func onChange(_ new: String) {
        query = new
        searchTask?.cancel()
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = nil
            errorMessage = nil
            isLoading = false
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetch()
        }
    }

    public func submit() async {
        searchTask?.cancel()
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            results = try await api.globalSearch(query)
        } catch {
            AppLog.ui.error("Search failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            results = nil
        }
    }
}

public struct GlobalSearchView: View {
    @State private var vm: GlobalSearchViewModel
    @State private var queryText: String = ""

    public init(api: APIClient) { _vm = State(wrappedValue: GlobalSearchViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Search")
            .searchable(text: $queryText, prompt: "Find tickets, customers, items…")
            .onChange(of: queryText) { _, new in vm.onChange(new) }
            .onSubmit(of: .search) { Task { await vm.submit() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        if queryText.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Search across tickets, customers, inventory, and invoices.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreError)
                Text("Search failed").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let results = vm.results {
            if results.isEmpty {
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "magnifyingglass.circle")
                        .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text("No results for \"\(queryText)\"")
                        .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !results.customers.isEmpty {
                        Section("Customers") {
                            ForEach(results.customers) { row in
                                ResultRow(row: row, icon: "person.fill")
                                    .listRowBackground(Color.bizarreSurface1)
                            }
                        }
                    }
                    if !results.tickets.isEmpty {
                        Section("Tickets") {
                            ForEach(results.tickets) { row in
                                ResultRow(row: row, icon: "wrench.and.screwdriver.fill")
                                    .listRowBackground(Color.bizarreSurface1)
                            }
                        }
                    }
                    if !results.inventory.isEmpty {
                        Section("Inventory") {
                            ForEach(results.inventory) { row in
                                ResultRow(row: row, icon: "shippingbox.fill")
                                    .listRowBackground(Color.bizarreSurface1)
                            }
                        }
                    }
                    if !results.invoices.isEmpty {
                        Section("Invoices") {
                            ForEach(results.invoices) { row in
                                ResultRow(row: row, icon: "doc.text.fill")
                                    .listRowBackground(Color.bizarreSurface1)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private struct ResultRow: View {
        let row: GlobalSearchResults.Row
        let icon: String
        @State private var copied: Bool = false

        var body: some View {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.display ?? "—")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let sub = row.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.bizarreSuccess)
                        .transition(.opacity)
                        .accessibilityLabel("Copied")
                }
            }
            .padding(.vertical, BrandSpacing.xxs)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    copyID()
                } label: {
                    Label("Copy ID #\(row.id)", systemImage: "number.square")
                }
                if let display = row.display, !display.isEmpty {
                    Button {
                        copy(display)
                    } label: {
                        Label("Copy name", systemImage: "doc.on.doc")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: row))
            .accessibilityHint("Double-tap and hold to open the actions menu.")
        }

        private func copyID() { copy(String(row.id)) }

        private func copy(_ value: String) {
            #if canImport(UIKit)
            UIPasteboard.general.string = value
            #endif
            withAnimation(BrandMotion.snappy) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(BrandMotion.snappy) { copied = false }
            }
        }

        static func a11y(for row: GlobalSearchResults.Row) -> String {
            let display = row.display ?? "Untitled"
            let sub = row.subtitle ?? ""
            return sub.isEmpty ? display : "\(display). \(sub)"
        }
    }
}
