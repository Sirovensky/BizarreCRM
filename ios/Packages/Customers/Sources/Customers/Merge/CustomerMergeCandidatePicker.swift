#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// §5.5 — Half-sheet for searching and selecting the secondary (merge-in) customer.

struct CustomerMergeCandidatePicker: View {
    @Binding var query: String
    let results: [CustomerSummary]
    let isSearching: Bool
    let onSelect: (CustomerSummary) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching…")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    } else if results.isEmpty && query.count >= 2 {
                        Text("No customers found.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Section {
                    ForEach(results) { customer in
                        Button {
                            onSelect(customer)
                            onDismiss()
                        } label: {
                            candidateRow(customer)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(customer.displayName)")
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search by name, phone or email")
            .navigationTitle("Find customer to merge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func candidateRow(_ c: CustomerSummary) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            ZStack {
                Circle().fill(Color.bizarreOrangeContainer)
                Text(c.initials)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnOrange)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let contact = c.contactLine {
                    Text(contact)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}
#endif
