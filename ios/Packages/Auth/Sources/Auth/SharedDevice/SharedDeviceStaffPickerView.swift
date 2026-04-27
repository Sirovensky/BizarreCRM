#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - §2.13 Shared-device staff quick-pick

/// A pre-populated grid of staff avatars for the shared-device lock screen.
///
/// Tapping an avatar navigates to the PIN entry pad for that user.
/// The roster is loaded from `MultiUserRoster` — every user who has ever
/// signed in on this device and set up a PIN appears here.
///
/// **iPhone**: 3-column grid.
/// **iPad**: 4-column grid, centred, max-width 560 pt.
///
/// Callers receive the chosen `RosterEntry` via `onSelect`; they then push
/// `PinPadView` pre-configured for that user.
///
/// ```swift
/// SharedDeviceStaffPickerView { entry in
///     selectedEntry = entry
///     showPinPad = true
/// }
/// ```
public struct SharedDeviceStaffPickerView: View {

    // MARK: - State

    @State private var entries: [RosterEntry] = []
    @State private var isLoaded: Bool = false

    // MARK: - Dependencies

    private let roster: MultiUserRoster
    private let onSelect: @MainActor (RosterEntry) -> Void

    // MARK: - Init

    public init(
        roster: MultiUserRoster = .shared,
        onSelect: @escaping @MainActor (RosterEntry) -> Void
    ) {
        self.roster = roster
        self.onSelect = onSelect
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .task {
            entries = await roster.all
            isLoaded = true
        }
    }

    // MARK: - Layouts

    private var iPhoneLayout: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            header
            if isLoaded {
                if entries.isEmpty {
                    emptyState
                } else {
                    staffGrid(columns: 3)
                }
            } else {
                skeletonGrid(columns: 3)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxxl)
    }

    private var iPadLayout: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            header
            if isLoaded {
                if entries.isEmpty {
                    emptyState
                } else {
                    staffGrid(columns: 4)
                }
            } else {
                skeletonGrid(columns: 4)
            }
        }
        .frame(maxWidth: 560)
        .padding(DesignTokens.Spacing.xxxl)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .padding(.horizontal, DesignTokens.Spacing.xxl)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)

            Text("Who's using this device?")
                .font(.brandDisplaySmall())
                .foregroundStyle(Color.bizarreOnSurface)
                .multilineTextAlignment(.center)

            Text("Tap your name and enter your PIN.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Staff grid

    private func staffGrid(columns: Int) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.md), count: columns)

        return LazyVGrid(columns: gridColumns, spacing: DesignTokens.Spacing.lg) {
            ForEach(entries) { entry in
                staffCell(entry: entry)
            }
        }
    }

    private func staffCell(entry: RosterEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            VStack(spacing: DesignTokens.Spacing.sm) {
                // Avatar circle
                ZStack {
                    Circle()
                        .fill(avatarBackgroundColor(for: entry))
                        .frame(width: 64, height: 64)

                    if let urlString = entry.avatarUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            default:
                                avatarInitials(entry: entry)
                            }
                        }
                    } else {
                        avatarInitials(entry: entry)
                    }
                }
                .frame(width: 64, height: 64)

                // Name
                Text(shortDisplayName(entry: entry))
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                // Role chip
                Text(entry.role.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            .padding(.vertical, DesignTokens.Spacing.md)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StaffCellButtonStyle())
        .accessibilityLabel("\(entry.displayName), \(entry.role)")
        .accessibilityHint("Tap to enter your PIN and sign in.")
    }

    private func avatarInitials(entry: RosterEntry) -> some View {
        Text(initials(for: entry))
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

    // MARK: - Skeleton loading

    private func skeletonGrid(columns: Int) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.md), count: columns)

        return LazyVGrid(columns: gridColumns, spacing: DesignTokens.Spacing.lg) {
            ForEach(0..<columns * 2, id: \.self) { _ in
                skeletonCell
            }
        }
    }

    private var skeletonCell: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(Color.bizarreOnSurface.opacity(0.12))
                .frame(width: 64, height: 64)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.bizarreOnSurface.opacity(0.10))
                .frame(height: 12)
                .padding(.horizontal, DesignTokens.Spacing.sm)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity)
        .shimmer()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Text("No staff registered yet")
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurface)

            Text("Each staff member must sign in once with their password to appear here.")
                .font(.brandBodyMedium())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Spacing.xl)
    }

    // MARK: - Helpers

    private func initials(for entry: RosterEntry) -> String {
        let parts = entry.displayName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last  = parts.dropFirst().last?.prefix(1) ?? ""
        let result = "\(first)\(last)".uppercased()
        return result.isEmpty ? "?" : result
    }

    private func shortDisplayName(entry: RosterEntry) -> String {
        let parts = entry.displayName.split(separator: " ")
        guard parts.count > 1, let first = parts.first else { return entry.displayName }
        let lastInitial = parts.last.map { "\($0.prefix(1))." } ?? ""
        return "\(first) \(lastInitial)"
    }

    private func avatarBackgroundColor(for entry: RosterEntry) -> Color {
        // Deterministic color per user ID so the same person always gets the same color
        let colors: [Color] = [
            Color.bizarreOrange.opacity(0.8),
            Color.bizarreTeal.opacity(0.8),
            Color.bizarreSuccess.opacity(0.7),
            Color.bizarreWarning.opacity(0.8),
            Color.bizarreMagenta.opacity(0.7),
        ]
        return colors[abs(entry.id) % colors.count]
    }
}

// MARK: - StaffCellButtonStyle

private struct StaffCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brandGlass(
                .regular,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg),
                tint: configuration.isPressed ? Color.bizarreOrange.opacity(0.12) : .clear,
                interactive: true
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.20, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - View shimmer helper (local stub, uses DesignSystem if available)

private extension View {
    @ViewBuilder
    func shimmer() -> some View {
        self
            .overlay(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

#endif
