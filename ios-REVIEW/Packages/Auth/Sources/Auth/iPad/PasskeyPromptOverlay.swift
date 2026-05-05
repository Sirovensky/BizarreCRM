#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - PasskeyPromptOverlay
//
// §22 iPad polish — floating capsule that gently nudges the user towards
// FaceID / Passkey authentication.
//
// The overlay appears as a Liquid Glass capsule anchored near the top-right
// of the form panel (or bottom-center on iPhone). It auto-dismisses after
// `autoDismissDelay` seconds or immediately when the user acts.
//
// Pluggable — attach with `.passkeyPromptOverlay(...)` modifier rather than
// embedding directly. Does not trigger auth itself; fires `onAccept` /
// `onDismiss` so the host decides how to proceed.

// MARK: - Prompt Kind

public enum PasskeyPromptKind: Sendable {
    case faceID
    case touchID
    case passkey

    public var sfSymbol: String {
        switch self {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        case .passkey:  return "person.badge.key.fill"
        }
    }

    public var label: String {
        switch self {
        case .faceID:   return "Sign in with Face ID"
        case .touchID:  return "Sign in with Touch ID"
        case .passkey:  return "Use a Passkey"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .faceID:   return "Sign in with Face ID instead of your password"
        case .touchID:  return "Sign in with Touch ID instead of your password"
        case .passkey:  return "Sign in using a saved passkey"
        }
    }
}

// MARK: - PasskeyPromptOverlay View

public struct PasskeyPromptOverlay: View {
    private let kind: PasskeyPromptKind
    private let onAccept: () -> Void
    private let onDismiss: () -> Void

    @State private var visible: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    /// How long before the overlay auto-dismisses. 0 = never auto-dismiss.
    private let autoDismissDelay: TimeInterval

    public init(
        kind: PasskeyPromptKind,
        autoDismissDelay: TimeInterval = 8,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.kind = kind
        self.autoDismissDelay = autoDismissDelay
        self.onAccept = onAccept
        self.onDismiss = onDismiss
    }

    public var body: some View {
        if visible {
            capsule
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .zIndex(DesignTokens.Z.toast)
                .onAppear {
                    scheduleAutoDismiss()
                }
        }
    }

    // MARK: - Capsule

    private var capsule: some View {
        HStack(spacing: BrandSpacing.md) {
            iconView
            labelView
            Spacer(minLength: 0)
            acceptButton
            dismissButton
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .frame(minHeight: DesignTokens.Touch.minTargetSide + BrandSpacing.sm)
        .brandGlass(.regular, in: Capsule(), tint: Color.bizarreOrange.opacity(0.15), interactive: true)
        .overlay(
            Capsule()
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, BrandSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.accessibilityLabel)
    }

    private var iconView: some View {
        Image(systemName: kind.sfSymbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.bizarreOrange)
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
    }

    private var labelView: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(kind.label)
                .font(.brandTitleSmall())
                .foregroundStyle(Color.bizarreOnSurface)
            Text("Faster and more secure")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
    }

    private var acceptButton: some View {
        Button {
            dismiss()
            onAccept()
        } label: {
            Text("Try it")
                .font(.brandLabelLarge())
                .foregroundStyle(Color.bizarreOnOrange)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.sm)
                .background(Color.bizarreOrange, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Try \(kind.label)")
        .accessibilityAddTraits(.isButton)
    }

    private var dismissButton: some View {
        Button {
            dismiss()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .frame(width: DesignTokens.Touch.minTargetSide, height: DesignTokens.Touch.minTargetSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss passkey suggestion")
    }

    // MARK: - Dismiss

    private func dismiss() {
        dismissTask?.cancel()
        withAnimation(BrandMotion.snappy) {
            visible = false
        }
    }

    private func scheduleAutoDismiss() {
        guard autoDismissDelay > 0 else { return }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoDismissDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(BrandMotion.snappy) { visible = false }
            onDismiss()
        }
    }
}

// MARK: - PasskeyPromptState (observable host model)

/// Observable state object the host creates and injects. Decouples the
/// overlay's show/hide logic from the form view hierarchy.
@MainActor
@Observable
public final class PasskeyPromptState {
    public var isVisible: Bool = false
    public var kind: PasskeyPromptKind = .passkey

    public init() {}

    public func show(kind: PasskeyPromptKind = .passkey) {
        self.kind = kind
        withAnimation(BrandMotion.snappy) { isVisible = true }
    }

    public func hide() {
        withAnimation(BrandMotion.snappy) { isVisible = false }
    }
}

// MARK: - View modifier for easy attachment

public extension View {
    /// Attaches a `PasskeyPromptOverlay` aligned to the top of this view.
    /// The overlay auto-manages its own slide-in/-out transitions.
    ///
    /// - Parameters:
    ///   - state: Observable state controlling visibility & kind.
    ///   - onAccept: Called when the user taps "Try it".
    ///   - onDismiss: Called when dismissed (auto or manual).
    func passkeyPromptOverlay(
        _ state: PasskeyPromptState,
        onAccept: @escaping () -> Void,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        overlay(alignment: .top) {
            PasskeyPromptOverlay(
                kind: state.kind,
                onAccept: onAccept,
                onDismiss: {
                    state.hide()
                    onDismiss()
                }
            )
            .opacity(state.isVisible ? 1 : 0)
            .animation(BrandMotion.snappy, value: state.isVisible)
            .allowsHitTesting(state.isVisible)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Passkey prompt — passkey kind") {
    let state = PasskeyPromptState()
    state.show(kind: .passkey)
    return ZStack(alignment: .top) {
        Color.bizarreSurfaceBase.ignoresSafeArea()
        VStack {
            Spacer().frame(height: 40)
        }
        .passkeyPromptOverlay(state, onAccept: { }, onDismiss: { })
    }
    .preferredColorScheme(.dark)
}

#Preview("Passkey prompt — Face ID kind") {
    let state = PasskeyPromptState()
    state.show(kind: .faceID)
    return ZStack(alignment: .top) {
        Color.bizarreSurfaceBase.ignoresSafeArea()
        VStack { Spacer() }
            .passkeyPromptOverlay(state, onAccept: { }, onDismiss: { })
    }
    .preferredColorScheme(.dark)
}
#endif

#endif
