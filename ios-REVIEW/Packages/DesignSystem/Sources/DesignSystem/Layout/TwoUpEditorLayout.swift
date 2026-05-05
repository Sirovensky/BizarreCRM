import SwiftUI

// §22.1 — Two-up editor scaffold.
//
// Shows two editors side-by-side on iPad 13" landscape (horizontal size class
// `.regular` and width ≥ 900 pt).  Collapses to a tab-switched single column
// on narrower screens.
//
// Canonical use-case: Ticket detail left + Invoice editor right.
//
// Usage:
//   TwoUpEditorLayout(
//       leadingTitle:  "Ticket",
//       trailingTitle: "Invoice",
//       leading:  { TicketEditorView(ticket: ticket) },
//       trailing: { InvoiceEditorView(invoice: invoice) }
//   )

// MARK: - TwoUpEditorLayout

/// A two-up (side-by-side) editor scaffold for iPad 13" landscape (§22.1).
///
/// On compact width or when the available width is below
/// `TwoUpEditorConstants.minWidthForSideBySide` the layout collapses into a
/// tab-switched single-column view so the caller's content is always
/// accessible without horizontal scrolling.
public struct TwoUpEditorLayout<Leading: View, Trailing: View>: View {

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - State

    @State private var selectedTab: TwoUpTab = .leading

    // MARK: - Properties

    private let leadingTitle: String
    private let trailingTitle: String
    private let leading: () -> Leading
    private let trailing: () -> Trailing

    // MARK: - Init

    /// Creates a two-up editor layout.
    ///
    /// - Parameters:
    ///   - leadingTitle: Tab / header label for the left pane.
    ///   - trailingTitle: Tab / header label for the right pane.
    ///   - leading: View builder for the left pane.
    ///   - trailing: View builder for the right pane.
    public init(
        leadingTitle: String,
        trailingTitle: String,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leadingTitle = leadingTitle
        self.trailingTitle = trailingTitle
        self.leading = leading
        self.trailing = trailing
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            if hSizeClass == .regular && proxy.size.width >= TwoUpEditorConstants.minWidthForSideBySide {
                sideBySide
            } else {
                tabbed
            }
        }
    }

    // MARK: - Side-by-side layout (iPad 13" landscape)

    @ViewBuilder
    private var sideBySide: some View {
        HStack(spacing: 0) {
            // Leading pane
            VStack(spacing: 0) {
                panelHeader(leadingTitle)
                leading()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))

            Divider()

            // Trailing pane
            VStack(spacing: 0) {
                panelHeader(trailingTitle)
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    // MARK: - Tabbed layout (compact / narrow)

    @ViewBuilder
    private var tabbed: some View {
        VStack(spacing: 0) {
            // Segmented picker acting as tab bar
            Picker("Editor", selection: $selectedTab) {
                Text(leadingTitle).tag(TwoUpTab.leading)
                Text(trailingTitle).tag(TwoUpTab.trailing)
            }
            .pickerStyle(.segmented)
            .padding(BrandSpacing.sm)
            .background(Color(uiColor: .secondarySystemBackground))

            Divider()

            switch selectedTab {
            case .leading:
                leading()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            case .trailing:
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }

    // MARK: - Panel header

    @ViewBuilder
    private func panelHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(Color(uiColor: .secondarySystemBackground))

        Divider()
    }
}

// MARK: - TwoUpTab

private enum TwoUpTab: Hashable {
    case leading
    case trailing
}

// MARK: - Constants

/// Layout constants for `TwoUpEditorLayout` (§22.1).
public enum TwoUpEditorConstants {
    /// Minimum available width (pts) before the side-by-side layout activates.
    /// 900 pt covers iPad 13" in landscape split-view at ≥ 2/3 width.
    public static let minWidthForSideBySide: CGFloat = 900
}
