#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - CustomerFilterSheet

/// §5.1 Filter sheet — LTV tier / health band / balance / open tickets / city / state / tag.
public struct CustomerFilterSheet: View {
    @Binding public var filter: CustomerListFilter
    public var onApply: () -> Void

    @State private var draft: CustomerListFilter
    @Environment(\.dismiss) private var dismiss

    public init(filter: Binding<CustomerListFilter>, onApply: @escaping () -> Void) {
        self._filter = filter
        self.onApply = onApply
        self._draft = State(wrappedValue: filter.wrappedValue)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    // MARK: LTV Tier
                    Section("LTV Tier") {
                        Picker("LTV Tier", selection: $draft.ltvTier) {
                            Text("Any").tag(String?.none)
                            Text("VIP").tag(String?.some("vip"))
                            Text("Regular").tag(String?.some("regular"))
                            Text("At-risk").tag(String?.some("at_risk"))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Filter by LTV tier")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // MARK: Health Band
                    Section("Health Band") {
                        Picker("Health Band", selection: $draft.healthBand) {
                            Text("Any").tag(String?.none)
                            Text("Good (≥70)").tag(String?.some("good"))
                            Text("Fair (≥40)").tag(String?.some("fair"))
                            Text("Poor (<40)").tag(String?.some("poor"))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Filter by health score band")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // MARK: Quick Flags
                    Section("Quick Flags") {
                        Toggle("Balance > $0", isOn: $draft.balanceGtZero)
                            .accessibilityLabel("Show only customers with outstanding balance")
                        Toggle("Has open tickets", isOn: $draft.hasOpenTickets)
                            .accessibilityLabel("Show only customers with open tickets")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // MARK: Location
                    Section("Location") {
                        TextField("City", text: Binding(
                            get: { draft.city ?? "" },
                            set: { draft.city = $0.isEmpty ? nil : $0 }
                        ))
                        .accessibilityLabel("Filter by city")

                        TextField("State", text: Binding(
                            get: { draft.state ?? "" },
                            set: { draft.state = $0.isEmpty ? nil : $0 }
                        ))
                        .accessibilityLabel("Filter by state")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // MARK: Tag
                    Section("Tag") {
                        TextField("Tag name", text: Binding(
                            get: { draft.tag ?? "" },
                            set: { draft.tag = $0.isEmpty ? nil : $0 }
                        ))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Filter by tag")
                    }
                    .listRowBackground(Color.bizarreSurface1)

                    // MARK: Clear
                    if draft.isActive {
                        Section {
                            Button(role: .destructive) {
                                draft = .init()
                            } label: {
                                Text("Clear all filters")
                                    .frame(maxWidth: .infinity)
                            }
                            .accessibilityLabel("Clear all active filters")
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filter Customers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel filter")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = draft
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityLabel("Apply filter")
                }
            }
        }
    }
}
#endif
