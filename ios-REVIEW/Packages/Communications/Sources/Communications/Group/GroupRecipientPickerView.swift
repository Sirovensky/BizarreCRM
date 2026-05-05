import SwiftUI
import Core
import DesignSystem

// MARK: - GroupRecipientPickerView

/// Customer segment picker + manual phone entry for group SMS recipients.
/// iPhone: sheet with search. iPad: sidebar popover or split pane.
public struct GroupRecipientPickerView: View {
    @Binding var recipients: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var manualPhone: String = ""
    @State private var searchText: String = ""

    // Segment presets (mirrors §37 Marketing segments concept)
    private let segments: [(name: String, description: String, phones: [String])] = [
        ("All Customers", "Everyone in your contact list", []),
        ("Recent (30 days)", "Customers active in the last 30 days", []),
        ("Inactive (90+ days)", "Customers not seen in 90+ days", []),
        ("Opted-in", "Customers who opted into SMS marketing", []),
    ]

    public init(recipients: Binding<[String]>) {
        _recipients = recipients
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    manualEntrySection
                    segmentSection
                    recipientChipList
                }
            }
            .navigationTitle("Choose Recipients")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .searchable(text: $searchText, prompt: "Search customers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(recipients.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Manual entry

    private var manualEntrySection: some View {
        HStack(spacing: BrandSpacing.sm) {
            TextField("Add phone number", text: $manualPhone)
                .textFieldStyle(.plain)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
                .accessibilityLabel("Phone number to add")

            Button {
                addManualPhone()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.bizarreOrange)
            }
            .buttonStyle(.plain)
            .disabled(manualPhone.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Add phone number")
        }
        .padding(BrandSpacing.base)
    }

    // MARK: - Segments

    private var segmentSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Segments")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.base)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(segments, id: \.name) { seg in
                        Button {
                            // In production: fetch phone list for segment from API
                            // then append to recipients. Currently a stub.
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seg.name)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(seg.description)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.sm)
                            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(seg.name): \(seg.description)")
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }
        }
        .padding(.bottom, BrandSpacing.sm)
    }

    // MARK: - Recipient chips

    @ViewBuilder
    private var recipientChipList: some View {
        if recipients.isEmpty {
            Text("No recipients added yet")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section("Selected (\(recipients.count))") {
                    ForEach(recipients, id: \.self) { phone in
                        HStack {
                            Text(phone)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Button {
                                recipients.removeAll { $0 == phone }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(phone)")
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .scrollContentBackground(.hidden)
            .accessibilityLabel("\(recipients.count) recipients selected")
        }
    }

    // MARK: - Helpers

    private func addManualPhone() {
        let trimmed = manualPhone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !recipients.contains(trimmed) else { return }
        recipients.append(trimmed)
        manualPhone = ""
    }
}
