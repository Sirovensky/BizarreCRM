import SwiftUI
import Core
import DesignSystem
#if canImport(UIKit)
import UIKit
#endif

// MARK: - §21.7 Real-time UX helpers

// MARK: - Pulse animation modifier

/// §21.7 — Attaches a subtle pulse animation to a list row when an item
/// has been updated via WebSocket. Usage:
/// ```swift
/// TicketRow(ticket: t)
///     .wsUpdatePulse(triggered: recentlyUpdatedIds.contains(t.id))
/// ```
public struct WSUpdatePulseModifier: ViewModifier {
    let triggered: Bool
    @State private var animating: Bool = false

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreOrange.opacity(animating ? 0 : 0.6), lineWidth: 1.5)
                    .scaleEffect(animating ? 1.06 : 1.0)
                    .animation(
                        animating
                            ? .easeOut(duration: 0.55)
                            : .linear(duration: 0),
                        value: animating
                    )
            )
            .onChange(of: triggered) { _, newValue in
                guard newValue else { return }
                animating = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    animating = true
                }
            }
    }
}

public extension View {
    /// Attaches a WebSocket update pulse animation when `triggered` flips to `true`.
    func wsUpdatePulse(triggered: Bool) -> some View {
        modifier(WSUpdatePulseModifier(triggered: triggered))
    }
}

// MARK: - WS toast model

/// §21.7 — A transient toast message shown at the top of the screen for
/// a real-time push event (e.g. "New message from Alice").
public struct WSToast: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    public let systemImage: String
    /// Deep-link to navigate to on tap (e.g. `bizarrecrm://sms/456`).
    public let deepLink: String?

    public init(
        id: UUID = UUID(),
        message: String,
        systemImage: String = "bell.fill",
        deepLink: String? = nil
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
        self.deepLink = deepLink
    }
}

// MARK: - WS toast overlay

/// §21.7 — Top-of-screen glass toast banner for incoming real-time events.
/// Present above root navigation via `.wsToastOverlay(toast: $currentToast, onTap:)`.
///
/// Auto-dismisses after 4 seconds. Swipe-up to dismiss early.
private struct WSToastBanner: View {
    let toast: WSToast
    let onTap: (WSToast) -> Void
    let onDismiss: () -> Void

    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0

    var body: some View {
        Button {
            onTap(toast)
            dismiss()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: toast.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(toast.message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
        }
        .buttonStyle(.plain)
        .background(.brandGlass(radius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bizarreOutline.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .offset(y: offset)
        .opacity(opacity)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height < -20 { dismiss() }
                }
        )
        .onAppear { present() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(.isButton)
    }

    private func present() {
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            offset = 0
            opacity = 1
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.25)) {
            offset = -100
            opacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(280))
            await MainActor.run { onDismiss() }
        }
    }
}

// MARK: - View modifier

private struct WSToastOverlayModifier: ViewModifier {
    @Binding var toast: WSToast?
    let onTap: (WSToast) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let t = toast {
                    WSToastBanner(
                        toast: t,
                        onTap: onTap,
                        onDismiss: { toast = nil }
                    )
                    .padding(.horizontal, BrandSpacing.md)
                    .padding(.top, BrandSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: toast != nil)
    }
}

public extension View {
    /// Overlays a top-of-screen glass toast for WebSocket events.
    /// - Parameters:
    ///   - toast: Binding to the current toast. Set to `nil` to dismiss; system auto-dismisses after 4s.
    ///   - onTap: Called with the toast when the user taps it; use `deepLink` to navigate.
    func wsToastOverlay(toast: Binding<WSToast?>, onTap: @escaping (WSToast) -> Void = { _ in }) -> some View {
        modifier(WSToastOverlayModifier(toast: toast, onTap: onTap))
    }
}
