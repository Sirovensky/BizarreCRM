/// PickupListSheet.swift
/// Agent B — Customer Gate (Frame 1)
///
/// Detent sheet (.medium / .large) that opens when the user taps "View all →"
/// in the ready-for-pickup strip. Lists all ready-for-pickup tickets with
/// inline search, tap-to-open.

#if canImport(UIKit)
import SwiftUI
import DesignSystem

// TODO: migrate to posTheme once Agent A lands
public struct PickupListSheet: View {
    @Binding var isPresented: Bool
    let allPickups: [ReadyPickup]
    let onSelect: (Int64) -> Void

    @State private var searchText: String = ""

    public init(
        isPresented: Binding<Bool>,
        allPickups: [ReadyPickup],
        onSelect: @escaping (Int64) -> Void
    ) {
        self._isPresented = isPresented
        self.allPickups = allPickups
        self.onSelect = onSelect
    }

    private var filtered: [ReadyPickup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allPickups }
        let lower = trimmed.lowercased()
        return allPickups.filter { pickup in
            pickup.customerName.lowercased().contains(lower) ||
            pickup.orderId.lowercased().contains(lower) ||
            (pickup.deviceSummary?.lowercased().contains(lower) ?? false)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    emptyState
                } else {
                    List(filtered) { pickup in
                        PickupRow(pickup: pickup) {
                            isPresented = false
                            onSelect(pickup.id)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Ready for Pickup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.bizarreOrange)
                        .accessibilityLabel("Close pickup list")
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by name, ticket #, device"
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            Text(searchText.isEmpty ? "No tickets ready for pickup" : "No matches")
                .font(.headline)
                .foregroundStyle(Color.bizarreOnSurface)
            if !searchText.isEmpty {
                Text("Try a different name or ticket number.")
                    .font(.subheadline)
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    PickupListSheet(
        isPresented: .constant(true),
        allPickups: [
            ReadyPickup(id: 1, orderId: "4829", customerName: "Sarah M.", deviceSummary: "iPhone 14 screen", totalCents: 27400),
            ReadyPickup(id: 2, orderId: "4831", customerName: "Marco D.", deviceSummary: "Samsung S23 battery", totalCents: 14200),
        ],
        onSelect: { _ in }
    )
}
#endif
#endif
