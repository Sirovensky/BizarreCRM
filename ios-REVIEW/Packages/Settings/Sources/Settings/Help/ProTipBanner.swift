import SwiftUI
import DesignSystem

// MARK: - ProTip model

public struct ProTip: Identifiable, Sendable, Equatable {
    public let id: String
    public let text: String
    public let iconName: String

    public init(id: String, text: String, iconName: String = "lightbulb.fill") {
        self.id = id
        self.text = text
        self.iconName = iconName
    }
}

// MARK: - Default tips catalog

public enum ProTipCatalog {
    public static let all: [ProTip] = [
        ProTip(id: "tip.shake", text: "Shake your iPhone to quickly report a bug — even in the field.", iconName: "iphone.radiowaves.left.and.right"),
        ProTip(id: "tip.barcode", text: "Tap the barcode icon in Inventory to scan items instantly with your camera.", iconName: "barcode.viewfinder"),
        ProTip(id: "tip.split", text: "At POS checkout, tap Split to accept multiple payment methods on one transaction.", iconName: "creditcard.and.123"),
        ProTip(id: "tip.hold", text: "Long-press a ticket in the list to quick-assign or change status.", iconName: "hand.tap"),
        ProTip(id: "tip.export", text: "Tap Export in Reports to generate a CSV or PDF and share via AirDrop.", iconName: "square.and.arrow.up")
    ]
}

// MARK: - ProTipBannerViewModel

@MainActor
@Observable
public final class ProTipBannerViewModel {

    // MARK: - Published state

    public private(set) var currentTip: ProTip?
    public private(set) var isVisible: Bool = false

    // MARK: - Private

    private let tips: [ProTip]
    private var currentIndex: Int = 0
    private var rotationTask: Task<Void, Never>?
    private static let dismissedKey = "com.bizarrecrm.dismissedProTipIDs"

    // MARK: - Init

    public init(tips: [ProTip] = ProTipCatalog.all) {
        self.tips = tips.filter { !Self.isDismissed($0.id) }
        self.currentTip = self.tips.first
        self.isVisible = self.currentTip != nil
    }

    // MARK: - Public API

    public func startRotating() {
        guard tips.count > 1 else { return }
        rotationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                advance()
            }
        }
    }

    public func stopRotating() {
        rotationTask?.cancel()
        rotationTask = nil
    }

    public func dismiss(id: String) {
        Self.markDismissed(id)
        withAnimation(.easeOut(duration: 0.25)) {
            isVisible = false
        }
    }

    // MARK: - Private helpers

    private func advance() {
        guard !tips.isEmpty else { return }
        currentIndex = (currentIndex + 1) % tips.count
        withAnimation(.easeInOut(duration: 0.35)) {
            currentTip = tips[currentIndex]
        }
    }

    // MARK: - Persistence helpers

    private static func dismissedIDs() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        return Set(raw)
    }

    private static func isDismissed(_ id: String) -> Bool {
        dismissedIDs().contains(id)
    }

    private static func markDismissed(_ id: String) {
        var ids = dismissedIDs()
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: dismissedKey)
    }
}

// MARK: - ProTipBanner

/// Rotating Dashboard tip banner. 5-second cycle. Dismissable.
/// Dismissed tip IDs are persisted in `UserDefaults`.
public struct ProTipBanner: View {

    @State private var vm: ProTipBannerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: ProTipBannerViewModel = ProTipBannerViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        if vm.isVisible, let tip = vm.currentTip {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: tip.iconName)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(tip.text)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Pro tip: \(tip.text)")

                Spacer()

                Button {
                    vm.dismiss(id: tip.id)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityLabel("Dismiss tip")
                        .accessibilityHint("Hides this tip permanently")
                }
                .buttonStyle(.plain)
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, BrandSpacing.base)
            .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
            .onAppear { vm.startRotating() }
            .onDisappear { vm.stopRotating() }
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ProTipBanner()
        .padding()
}
#endif
