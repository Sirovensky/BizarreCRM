import SwiftUI
import Core
import DesignSystem

// MARK: - TrainingProfileTile

private struct TrainingTile: Identifiable, Sendable {
    let id: Int
    let title: String
    let icon: String
    let color: Color
}

// MARK: - TrainingProfileView

/// §55.3 Simplified training profile UI — large-button single-purpose screens.
/// iPhone: 2x2 grid. iPad: wider 2x2 or 4-across grid.
public struct TrainingProfileView: View {
    let onExitRequest: () -> Void
    @Bindable var idleMonitor: KioskIdleMonitor

    private let tiles: [TrainingTile] = [
        TrainingTile(id: 0, title: "New Ticket",  icon: "doc.badge.plus",      color: .orange),
        TrainingTile(id: 1, title: "POS",          icon: "creditcard.fill",      color: .teal),
        TrainingTile(id: 2, title: "Clock In",     icon: "clock.badge.checkmark",color: .green),
        TrainingTile(id: 3, title: "Clock Out",    icon: "clock.badge.xmark",   color: .red)
    ]

    @State private var selectedTileId: Int?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(onExitRequest: @escaping () -> Void, idleMonitor: KioskIdleMonitor) {
        self.onExitRequest = onExitRequest
        self.idleMonitor = idleMonitor
    }

    public var body: some View {
        NavigationStack {
            trainingGrid
                .navigationTitle("Training Mode")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onExitRequest()
                        } label: {
                            Label("Exit", systemImage: "lock.open")
                        }
                        .accessibilityLabel("Exit training mode — requires manager PIN")
                    }
                }
        }
        .onTapGesture { idleMonitor.recordActivity() }
    }

    // MARK: - Grid

    @ViewBuilder
    private var trainingGrid: some View {
        // iPad: 4-across. iPhone: 2-across.
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.lg), count: columnCount)

        ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.lg) {
                ForEach(tiles) { tile in
                    trainingTileButton(tile)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    @ViewBuilder
    private func trainingTileButton(_ tile: TrainingTile) -> some View {
        Button {
            idleMonitor.recordActivity()
            selectedTileId = tile.id
        } label: {
            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: tile.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(tile.color)
                    .accessibilityHidden(true)

                Text(tile.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(.medium ... .accessibility2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 160)
            .padding(DesignTokens.Spacing.xl)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        }
        .frame(minWidth: DesignTokens.Touch.minTargetSide, minHeight: 64)
        .accessibilityLabel(tile.title)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
