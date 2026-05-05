import SwiftUI
import Core
import DesignSystem

// MARK: - ImportRowAction

/// Actions that can be performed on an individual import row with errors.
public enum ImportRowAction: Sendable {
    case retryRow(Int)
    case skipRow(Int)
    case copyError(String)
}

// MARK: - ImportContextMenu

/// Context menu for import error rows.
///
/// Provides three actions:
/// - **Retry failed row** — re-attempt ingestion of the row.
/// - **Skip row** — exclude this row from the import.
/// - **Copy error** — puts the error reason on the clipboard.
///
/// Usage: attach via `.importRowContextMenu(error:onAction:)` modifier.
public struct ImportContextMenu: View {
    public let error: ImportRowError
    public let onAction: (ImportRowAction) -> Void

    public init(error: ImportRowError, onAction: @escaping (ImportRowAction) -> Void) {
        self.error = error
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            Button {
                onAction(.retryRow(error.row))
            } label: {
                Label("Retry Row \(error.row)", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("import.context.retry.\(error.row)")

            Button(role: .destructive) {
                onAction(.skipRow(error.row))
            } label: {
                Label("Skip Row \(error.row)", systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("import.context.skip.\(error.row)")

            Divider()

            Button {
                onAction(.copyError(error.reason))
            } label: {
                Label("Copy Error", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("import.context.copyError.\(error.row)")
        }
    }
}

// MARK: - View modifier

public extension View {
    /// Attaches an import-row context menu that fires `onAction` for the three
    /// standard row actions (retry, skip, copy error).
    func importRowContextMenu(
        error: ImportRowError,
        onAction: @escaping (ImportRowAction) -> Void
    ) -> some View {
        contextMenu {
            ImportContextMenu(error: error, onAction: onAction)
        }
    }
}

// MARK: - ImportRowActionHandler

/// Default handler wired to `ImportWizardViewModel`.
/// Retry and skip are best-effort local operations; the ViewModel owns state.
@MainActor
public struct ImportRowActionHandler {

    private let vm: ImportWizardViewModel

    public init(vm: ImportWizardViewModel) {
        self.vm = vm
    }

    /// Dispatch an `ImportRowAction`.
    public func handle(_ action: ImportRowAction) {
        switch action {
        case .retryRow(let row):
            vm.retryRow(row)
        case .skipRow(let row):
            vm.skipRow(row)
        case .copyError(let reason):
            copyToPasteboard(reason)
        }
    }

    // MARK: - Pasteboard

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
