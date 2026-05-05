import SwiftUI
import DesignSystem

// MARK: - SmsIconRail
//
// Compact icon-only sidebar column (~72 pt wide) replacing the full-text
// folder List. Shows SF Symbol icon, optional count badge, tooltip on hover.
// Used exclusively in SmsThreeColumnView on iPad.

struct SmsIconRail: View {
    @Binding var selectedFolder: SmsFolder
    let folderCount: (SmsFolder) -> Int
    let onCompose: () -> Void

    /// Target width of the rail column. NavigationSplitView respects the
    /// `navigationSplitViewColumnWidth` modifier set on the sidebar child.
    static let preferredWidth: CGFloat = 72

    var body: some View {
        VStack(spacing: BrandSpacing.xs) {
            railHeader
            Divider()
                .padding(.horizontal, BrandSpacing.sm)
            folderButtons
            Spacer()
            composeButton
                .padding(.bottom, BrandSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BrandSpacing.sm)
        .background(Color.bizarreSurfaceBase)
        .navigationBarHidden(true)
        .navigationSplitViewColumnWidth(SmsIconRail.preferredWidth)
    }

    // MARK: - Header

    private var railHeader: some View {
        Image(systemName: "message.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.bizarreOrange)
            .accessibilityLabel("SMS")
            .padding(.top, BrandSpacing.xs)
    }

    // MARK: - Folder Buttons

    private var folderButtons: some View {
        ForEach(SmsFolder.allCases) { folder in
            railButton(for: folder)
        }
    }

    private func railButton(for folder: SmsFolder) -> some View {
        let isSelected = folder == selectedFolder
        let count = folderCount(folder)

        return Button {
            selectedFolder = folder
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: folder.systemImage)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .frame(width: 28, height: 28)
                    Text(folder.shortLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                .frame(width: 52, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.bizarreOrange.opacity(0.15) : Color.clear)
                )

                // Count badge
                if count > 0 {
                    Text(count < 100 ? "\(count)" : "99+")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.bizarreMagenta, in: Capsule())
                        .offset(x: 6, y: -4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(folder.rawValue)\(count > 0 ? ", \(count) conversation\(count == 1 ? "" : "s")" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #if !os(macOS)
        .hoverEffect(.highlight)
        #endif
        // Tooltip on pointer hover (iPadOS 16+)
        .help(folder.rawValue)
    }

    // MARK: - Compose Button

    private var composeButton: some View {
        Button(action: onCompose) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(width: 52, height: 48)
                .background(Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New message")
        .keyboardShortcut("n", modifiers: .command)
        #if !os(macOS)
        .hoverEffect(.highlight)
        #endif
        .help("New message (⌘N)")
    }
}

// MARK: - SmsFolder short label (for icon rail only)

extension SmsFolder {
    /// Two- or three-character label shown below the icon in the compact rail.
    var shortLabel: String {
        switch self {
        case .all:      return "All"
        case .flagged:  return "Flag"
        case .pinned:   return "Pin"
        case .archived: return "Arch"
        }
    }
}
