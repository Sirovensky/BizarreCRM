import SwiftUI
import DesignSystem

// MARK: - DeadLetterListView

/// Lists dead-lettered sync ops with entity, error reason, original timestamp.
/// Entry point: Settings → Diagnostics → Sync Dead Letter.
public struct DeadLetterListView: View {
    @State private var viewModel = DeadLetterViewModel()
    @State private var selectedItem: DeadLetterItem?

    public init() {}

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading dead-lettered sync operations")
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Sync Dead Letter")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                DeadLetterDetailView(item: item, viewModel: viewModel)
            }
        }
    }

    // MARK: - List

    private var listContent: some View {
        List {
            Section {
                ForEach(viewModel.items) { item in
                    DeadLetterRowView(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                        .accessibilityLabel(rowA11yLabel(item))
                        .accessibilityHint("Double-tap to view details and retry or discard")
                }
            } header: {
                Text("\(viewModel.items.count) failed operation\(viewModel.items.count == 1 ? "" : "s")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No failed operations")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Sync dead letter queue is empty.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync dead letter queue is empty. No failed operations.")
    }

    // MARK: - A11y

    private func rowA11yLabel(_ item: DeadLetterItem) -> String {
        let entityOp = "\(item.entity) \(item.op)"
        let attempts = "\(item.attemptCount) attempt\(item.attemptCount == 1 ? "" : "s")"
        let error = item.lastError.map { "Error: \($0)." } ?? ""
        return "\(entityOp). \(attempts). \(error)"
    }
}

// MARK: - DeadLetterRowView

private struct DeadLetterRowView: View {
    let item: DeadLetterItem

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Label {
                    Text(item.entity)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(.bizarreError)
                        .accessibilityHidden(true)
                }

                Spacer()

                Text(Self.dateFormatter.localizedString(for: item.movedAt, relativeTo: Date()))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            HStack(spacing: BrandSpacing.sm) {
                Text(item.op.uppercased())
                    .font(.brandMono(size: 11))
                    .foregroundStyle(.bizarreTeal)

                if let error = item.lastError {
                    Text(error)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreError)
                        .lineLimit(2)
                }
            }

            Text("\(item.attemptCount) attempt\(item.attemptCount == 1 ? "" : "s")")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xxs)
    }
}
