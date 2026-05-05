import SwiftUI
import DesignSystem

// MARK: - NotificationBulkActionsBar
//
// §22 iPad — floating glass bar that appears when items are selected.
// Provides: select-all, mark-read, archive, cancel.
//
// Glass is applied to the bar chrome (navigation overlay, not content).
// Uses existing routes via vm.markRead / vm.markAllRead passed as callbacks.

public struct NotificationBulkActionsBar: View {

    // MARK: - Inputs

    public let selectedCount: Int
    public var onMarkRead: (() -> Void)?
    public var onArchive: (() -> Void)?
    public var onSelectAll: (() -> Void)?
    public var onCancel: (() -> Void)?

    // MARK: - Init

    public init(
        selectedCount: Int,
        onMarkRead: (() -> Void)? = nil,
        onArchive: (() -> Void)? = nil,
        onSelectAll: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.selectedCount = selectedCount
        self.onMarkRead = onMarkRead
        self.onArchive = onArchive
        self.onSelectAll = onSelectAll
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            countChip
            Spacer()
            actionButtons
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bulk actions bar, \(selectedCount) selected")
    }

    // MARK: - Count chip

    private var countChip: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text(selectedCountLabel)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
        .accessibilityLabel(selectedCountLabel)
    }

    private var selectedCountLabel: String {
        selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: BrandSpacing.xs) {
            selectAllButton
            Divider()
                .frame(height: 20)
                .foregroundStyle(.bizarreOutline)
            markReadButton
            archiveButton
            cancelButton
        }
    }

    private var selectAllButton: some View {
        Button {
            onSelectAll?()
        } label: {
            Label("Select All", systemImage: "checkmark.circle")
                .font(.brandLabelLarge())
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.brandGlass)
        .tint(.bizarreTeal)
        .accessibilityLabel("Select all notifications")
        .accessibilityIdentifier("notif.ipad.bulk.selectAll")
        .keyboardShortcut("a", modifiers: [.command])
    }

    private var markReadButton: some View {
        Button {
            onMarkRead?()
        } label: {
            Label("Mark Read", systemImage: "envelope.open")
                .font(.brandLabelLarge())
        }
        .buttonStyle(.brandGlass)
        .tint(.bizarreTeal)
        .accessibilityLabel("Mark selected as read")
        .accessibilityIdentifier("notif.ipad.bulk.markRead")
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    private var archiveButton: some View {
        Button {
            onArchive?()
        } label: {
            Label("Archive", systemImage: "archivebox")
                .font(.brandLabelLarge())
        }
        .buttonStyle(.brandGlass)
        .tint(.bizarreWarning)
        .accessibilityLabel("Archive selected notifications")
        .accessibilityIdentifier("notif.ipad.bulk.archive")
        .keyboardShortcut("d", modifiers: [.command])
    }

    private var cancelButton: some View {
        Button {
            onCancel?()
        } label: {
            Label("Cancel", systemImage: "xmark")
                .font(.brandLabelLarge())
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.brandGlassClear)
        .tint(.bizarreOnSurfaceMuted)
        .accessibilityLabel("Cancel selection")
        .accessibilityIdentifier("notif.ipad.bulk.cancel")
        .keyboardShortcut(.escape, modifiers: [])
    }
}
