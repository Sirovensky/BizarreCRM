#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - CustomerBulkActionBar

/// §5.1 / §5.6 Bulk action bar — shown at bottom when `isBulkSelecting` is true.
/// Surfaces "Tag…", "Export" (§5.6), and "Delete" actions.
public struct CustomerBulkActionBar: View {
    public let selectedCount: Int
    public var onTag: () -> Void
    public var onExport: (() -> Void)?
    public var onDelete: () -> Void
    public var onCancel: () -> Void

    public init(
        selectedCount: Int,
        onTag: @escaping () -> Void,
        onExport: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.selectedCount = selectedCount
        self.onTag = onTag
        self.onExport = onExport
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Button("Cancel", action: onCancel)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("Cancel bulk selection")

            Spacer(minLength: 0)

            Text(selectedCount == 0
                 ? "Select items"
                 : "\(selectedCount) selected")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityLabel("\(selectedCount) customers selected")

            Spacer(minLength: 0)

            Button(action: onTag) {
                Label("Tag", systemImage: "tag")
                    .font(.brandBodyMedium())
            }
            .disabled(selectedCount == 0)
            .accessibilityLabel("Apply tag to \(selectedCount) selected customers")

            // §5.6 Export selected
            if let export = onExport {
                Button(action: export) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.brandBodyMedium())
                }
                .disabled(selectedCount == 0)
                .accessibilityLabel("Export \(selectedCount) selected customers as CSV")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.brandBodyMedium())
            }
            .disabled(selectedCount == 0)
            .accessibilityLabel("Delete \(selectedCount) selected customers")
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - BulkTagInputSheet

/// Simple sheet that asks for a tag name, then calls `onConfirm`.
public struct BulkTagInputSheet: View {
    @State private var tagName: String = ""
    @Environment(\.dismiss) private var dismiss
    public var onConfirm: (String) -> Void

    public init(onConfirm: @escaping (String) -> Void) {
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Tag name") {
                        TextField("e.g. vip, corporate, late-payer", text: $tagName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("Tag name to apply")
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Apply Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel tag")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let trimmed = tagName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onConfirm(trimmed)
                        dismiss()
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Confirm tag application")
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
#endif
