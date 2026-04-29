import SwiftUI

// §22.2 — Multi-select row chord.
//
// Implements long-press-to-enter-edit-mode + ⌘-click batch selection for list
// rows on iPad/Mac.  A floating `BulkActionBar` glass footer appears whenever
// `selectedIDs` is non-empty.
//
// Usage:
//   @State private var selectedIDs: Set<String> = []
//   @State private var editMode: EditMode = .inactive
//
//   List(tickets, selection: $selectedIDs) { ticket in
//       TicketRow(ticket: ticket)
//           .multiSelectRow(id: ticket.id, selectedIDs: $selectedIDs, editMode: $editMode)
//   }
//   .environment(\.editMode, $editMode)
//   .overlay(alignment: .bottom) {
//       BulkActionBar(selectedCount: selectedIDs.count, editMode: $editMode) {
//           onBulkAssign(selectedIDs)
//       } onArchive: {
//           onBulkArchive(selectedIDs)
//       } onDelete: {
//           onBulkDelete(selectedIDs)
//       }
//   }

// MARK: - MultiSelectRowModifier

/// Adds long-press → enter edit mode and ⌘-click selection to any list row
/// (§22.2).
///
/// The modifier only activates on iPadOS / Mac; it is a no-op on compact-width
/// phones.
public struct MultiSelectRowModifier<ID: Hashable>: ViewModifier {

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Properties

    private let id: ID
    @Binding private var selectedIDs: Set<ID>
    @Binding private var editMode: EditMode

    // MARK: - Init

    public init(
        id: ID,
        selectedIDs: Binding<Set<ID>>,
        editMode: Binding<EditMode>
    ) {
        self.id = id
        self._selectedIDs = selectedIDs
        self._editMode = editMode
    }

    // MARK: - Computed

    private var isSelected: Bool { selectedIDs.contains(id) }

    // MARK: - Body

    public func body(content: Content) -> some View {
        if hSizeClass == .regular {
            content
                .overlay(alignment: .leading) {
                    selectionCheckmark
                }
                // Long-press enters edit mode and selects this row.
                .onLongPressGesture(minimumDuration: MultiSelectConstants.longPressDuration) {
                    withAnimation(MultiSelectConstants.selectionAnimation) {
                        if editMode == .inactive {
                            editMode = .active
                        }
                        toggleSelection()
                    }
                }
                // ⌘-click selects / deselects individual rows while in edit mode.
                .onTapGesture {
                    // Plain tap while in edit mode toggles selection.
                    if editMode.isEditing {
                        withAnimation(MultiSelectConstants.selectionAnimation) {
                            toggleSelection()
                        }
                    }
                }
                .background(selectionBackground)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(
                    editMode.isEditing
                        ? (isSelected ? "Double-tap to deselect" : "Double-tap to select")
                        : "Long press to begin multi-select"
                )
        } else {
            content
        }
    }

    // MARK: - Helpers

    private func toggleSelection() {
        if isSelected {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var selectionCheckmark: some View {
        if editMode.isEditing {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .font(.title3)
                .padding(.leading, BrandSpacing.small)
                .transition(.scale.combined(with: .opacity))
                .animation(MultiSelectConstants.selectionAnimation, value: isSelected)
        }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected && editMode.isEditing {
            Color.accentColor.opacity(MultiSelectConstants.selectedBackgroundOpacity)
                .ignoresSafeArea(edges: .horizontal)
        }
    }
}

// MARK: - BulkActionBar

/// Floating glass footer that appears when ≥1 row is selected (§22.2).
///
/// Provides Bulk Assign / Archive / Delete actions.  Tapping "Done" exits edit
/// mode and clears the selection.
public struct BulkActionBar: View {

    // MARK: - Properties

    public let selectedCount: Int
    @Binding public var editMode: EditMode

    public let onAssign: () -> Void
    public let onArchive: () -> Void
    public let onDelete: () -> Void

    // MARK: - Init

    public init(
        selectedCount: Int,
        editMode: Binding<EditMode>,
        onAssign: @escaping () -> Void,
        onArchive: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.selectedCount = selectedCount
        self._editMode = editMode
        self.onAssign = onAssign
        self.onArchive = onArchive
        self.onDelete = onDelete
    }

    // MARK: - Body

    public var body: some View {
        if selectedCount > 0 {
            HStack(spacing: BrandSpacing.medium) {
                // Count label
                Text("\(selectedCount) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Assign", action: onAssign)
                    .buttonStyle(.bordered)

                Button("Archive", action: onArchive)
                    .buttonStyle(.bordered)

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)

                Divider()
                    .frame(height: 20)

                Button("Done") {
                    withAnimation(MultiSelectConstants.selectionAnimation) {
                        editMode = .inactive
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.vertical, BrandSpacing.small)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: -2)
            .padding(.horizontal, BrandSpacing.medium)
            .padding(.bottom, BrandSpacing.small)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(MultiSelectConstants.selectionAnimation, value: selectedCount)
        }
    }
}

// MARK: - Constants

/// Animation / layout constants for multi-select (§22.2).
public enum MultiSelectConstants {
    /// Long-press duration before edit mode activates.
    public static let longPressDuration: Double = 0.4
    /// Animation used for selection state changes.
    public static let selectionAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.75)
    /// Tint opacity for selected row background.
    public static let selectedBackgroundOpacity: Double = 0.12
}

// MARK: - View extension

public extension View {
    /// Adds long-press → edit-mode + ⌘-click multi-select behaviour to a list
    /// row (§22.2).
    ///
    /// Only activates on iPad / Mac (regular horizontal size class).
    ///
    /// - Parameters:
    ///   - id: The unique identifier of this row (must match the list's
    ///     `selection` binding element type).
    ///   - selectedIDs: The set of currently selected identifiers.
    ///   - editMode: The list's edit-mode binding.
    func multiSelectRow<ID: Hashable>(
        id: ID,
        selectedIDs: Binding<Set<ID>>,
        editMode: Binding<EditMode>
    ) -> some View {
        modifier(MultiSelectRowModifier(id: id, selectedIDs: selectedIDs, editMode: editMode))
    }
}
