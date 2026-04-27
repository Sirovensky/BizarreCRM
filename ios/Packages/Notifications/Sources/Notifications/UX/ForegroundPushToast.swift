import SwiftUI
import UserNotifications
import Core
import DesignSystem
import Observation

// MARK: - ForegroundPushToast
//
// §13.3 — When a push arrives while the app is foregrounded on a *different* screen
// from the notification source, show a glass toast at the top of the screen.
// Auto-dismisses in 4s; tap opens the deep link; haptic on appearance.
//
// Integration: Wrap your root content in `.foregroundPushToastOverlay()`.
// Wire via `ForegroundPushToastCoordinator.shared.show(...)` from your
// `UNUserNotificationCenter` willPresent delegate callback.

// MARK: - Toast model

public struct ForegroundPushToastItem: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let body: String
    public let deepLinkPath: String?

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        deepLinkPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.deepLinkPath = deepLinkPath
    }
}

// MARK: - Coordinator

/// Thread-safe coordinator. App delegates call `show(...)` from the
/// `UNUserNotificationCenter willPresent` callback.
@MainActor
@Observable
public final class ForegroundPushToastCoordinator {

    public static let shared = ForegroundPushToastCoordinator()

    public private(set) var currentToast: ForegroundPushToastItem?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Present a foreground toast. Replaces any existing one.
    public func show(_ item: ForegroundPushToastItem) {
        dismissTask?.cancel()
        withAnimation(BrandMotion.snappy) {
            currentToast = item
        }
        BrandHaptics.selection()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Convenience: build a toast from a `UNNotificationContent`.
    public func show(content: UNNotificationContent, deepLinkPath: String? = nil) {
        let item = ForegroundPushToastItem(
            title: content.title,
            body: content.body,
            deepLinkPath: deepLinkPath
        )
        show(item)
    }

    public func dismiss() {
        dismissTask?.cancel()
        withAnimation(BrandMotion.snappy) {
            currentToast = nil
        }
    }
}

// MARK: - Toast view

private struct ForegroundPushToastView: View {
    let item: ForegroundPushToastItem
    let onTap: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "bell.fill")
                .foregroundStyle(.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, interactive: false)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, BrandSpacing.base)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.deepLinkPath != nil ? "Double tap to open" : "")
        .accessibilityAddTraits(.isButton)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
        )
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if !item.title.isEmpty { parts.append(item.title) }
        if !item.body.isEmpty { parts.append(item.body) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - View modifier

private struct ForegroundPushToastModifier: ViewModifier {
    @State private var coordinator = ForegroundPushToastCoordinator.shared
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = coordinator.currentToast {
                ForegroundPushToastView(
                    item: toast,
                    onTap: {
                        if let path = toast.deepLinkPath,
                           let url = URL(string: path) {
                            openURL(url)
                        }
                        coordinator.dismiss()
                    },
                    onDismiss: {
                        coordinator.dismiss()
                    }
                )
                .zIndex(999)
                .padding(.top, BrandSpacing.sm)
                .id(toast.id)
            }
        }
        .animation(BrandMotion.snappy, value: coordinator.currentToast?.id)
    }
}

public extension View {
    /// Overlays the foreground-push toast at the top of this view.
    /// Call once on your root content view (below the nav bar safe area).
    func foregroundPushToastOverlay() -> some View {
        modifier(ForegroundPushToastModifier())
    }
}
