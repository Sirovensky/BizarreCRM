#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.11 Invoice Template Picker Sheet — at create, user picks template to pre-fill

@MainActor
@Observable
final class InvoiceTemplatePickerViewModel {
    enum State: Sendable {
        case idle
        case loading
        case loaded([InvoiceTemplate])
        case failed(String)
    }

    var state: State = .idle
    var searchText: String = ""

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    var filtered: [InvoiceTemplate] {
        guard case .loaded(let templates) = state else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            ($0.notes ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    func load() async {
        state = .loading
        do {
            let templates = try await api.listInvoiceTemplates()
            state = .loaded(templates)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

public struct InvoiceTemplatePickerSheet: View {
    @State private var vm: InvoiceTemplatePickerViewModel
    @Environment(\.dismiss) private var dismiss
    private let onSelected: (InvoiceTemplate) -> Void

    public init(api: APIClient, onSelected: @escaping (InvoiceTemplate) -> Void) {
        _vm = State(wrappedValue: InvoiceTemplatePickerViewModel(api: api))
        self.onSelected = onSelected
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch vm.state {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let msg):
                    errorView(msg)
                case .loaded:
                    if vm.filtered.isEmpty {
                        emptyView
                    } else {
                        listView
                    }
                }
            }
            .navigationTitle("Choose Template")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: "Search templates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.medium, .large])
    }

    private var listView: some View {
        List(vm.filtered) { template in
            Button {
                onSelected(template)
                dismiss()
            } label: {
                TemplateRow(template: template)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(template.name). \(template.lineItems.count) line items. Total \(formatMoney(template.totalCents)).")
            .accessibilityHint("Double-tap to pre-fill invoice with this template")
        }
        .listStyle(.insetGrouped)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No templates found")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .font(.system(size: 36))
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct TemplateRow: View {
    let template: InvoiceTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(template.name)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(formatMoney(template.totalCents))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
            Text("\(template.lineItems.count) item\(template.lineItems.count == 1 ? "" : "s")")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            if let notes = template.notes, !notes.isEmpty {
                Text(notes)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}

private func formatMoney(_ cents: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$\(cents)"
}
#endif
