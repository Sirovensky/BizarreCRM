import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Toast model

/// A single toast notification. Immutable value type (§coding-style).
public struct Toast: Identifiable, Sendable {
    public enum Style: Sendable {
        case info, success, warning, error
    }

    public let id: UUID
    public let message: String
    public let style: Style
    /// Override auto-dismiss duration. nil = use default per style.
    public let duration: Double?

    public init(
        id: UUID = UUID(),
        message: String,
        style: Style = .info,
        duration: Double? = nil
    ) {
        self.id = id
        self.message = message
        self.style = style
        self.duration = duration
    }

    var effectiveDuration: Double {
        if let d = duration { return d }
        return style == .error ? 5.0 : 4.0
    }

    var iconSystemName: String {
        switch style {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch style {
        case .info:    return .bizarreTeal
        case .success: return .bizarreSuccess
        case .warning: return .bizarreWarning
        case .error:   return .bizarreError
        }
    }
}

// MARK: - ToastPresenter

/// `@Observable` store for queued toasts. Max 3 visible at once.
///
/// **Usage:**
/// ```swift
/// @Environment(ToastPresenter.self) var toasts
/// toasts.show("Saved!", style: .success)
/// ```
@Observable
@MainActor
public final class ToastPresenter {
    /// Maximum concurrent toasts shown (oldest removed if exceeded).
    public static let maxStack = 3

    public private(set) var toasts: [Toast] = []

    public init() {}

    /// Enqueue a new toast. Removes oldest if stack is full.
    ///
    /// When VoiceOver is active the message is also posted as a `.announcement`
    /// notification so the user hears it without needing to navigate to the toast
    /// pill. The announcement is silent when VoiceOver is off — §26.1.
    public func show(_ message: String, style: Toast.Style = .info, duration: Double? = nil) {
        let toast = Toast(message: message, style: style, duration: duration)
        var updated = toasts
        if updated.count >= ToastPresenter.maxStack {
            updated.removeFirst()
        }
        updated.append(toast)
        toasts = updated
        scheduleAutoDismiss(toast)
        postVoiceOverAnnouncement(message)
    }

    // MARK: Private — VoiceOver

    private func postVoiceOverAnnouncement(_ message: String) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    /// Immediately dismiss a specific toast.
    public func dismiss(_ toast: Toast) {
        toasts = toasts.filter { $0.id != toast.id }
    }

    /// Dismiss all toasts.
    public func dismissAll() {
        toasts = []
    }

    // MARK: Private

    private func scheduleAutoDismiss(_ toast: Toast) {
        let duration = toast.effectiveDuration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            dismiss(toast)
        }
    }
}

// MARK: - ToastPillView

/// Single glass-pill toast view.
private struct ToastPillView: View {
    let toast: Toast
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: toast.iconSystemName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(toast.iconColor)
                .accessibilityHidden(true)

            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(
                    color: .black.opacity(DesignTokens.Shadows.md.opacityDark),
                    radius: DesignTokens.Shadows.md.blur,
                    y: DesignTokens.Shadows.md.y
                )
        }
        .contentShape(Capsule())
        .onTapGesture { onDismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(toast.message)
    }
}

// MARK: - ToastStackView

/// Hosts the stack of active toasts at the bottom of the screen.
public struct ToastStackView: View {
    @Environment(ToastPresenter.self) private var presenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(presenter.toasts) { toast in
                ToastPillView(toast: toast) {
                    withAnimation(reduceMotion ? .linear(duration: 0.15) : .spring(duration: DesignTokens.Motion.snappy)) {
                        presenter.dismiss(toast)
                    }
                }
                .transition(
                    reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(
            reduceMotion ? .linear(duration: 0.15) : .spring(duration: DesignTokens.Motion.snappy),
            value: presenter.toasts.map(\.id)
        )
        .padding(.bottom, DesignTokens.Spacing.lg)
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }
}

// MARK: - View extension

public extension View {
    /// Overlays `ToastStackView` at the bottom of this view.
    ///
    /// Requires `ToastPresenter` to be injected via `.environment(toastPresenter)`.
    func toastOverlay() -> some View {
        overlay(alignment: .bottom) {
            ToastStackView()
        }
    }
}
