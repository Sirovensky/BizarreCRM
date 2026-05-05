import SwiftUI
import DesignSystem

// MARK: - AppointmentConflictToast

/// Non-modal conflict warning toast that slides in from the top.
///
/// Use this lightweight alert when a scheduling conflict is detected on a
/// partial-form change (e.g. time picker updated) and a full modal sheet
/// would be too disruptive. The toast auto-dismisses after `autoDismissAfter`
/// seconds or can be dismissed by the user tapping the "X" button.
///
/// For the full conflict-resolution flow (change-tech / pick-slot / admin
/// override), present `AppointmentConflictAlertView` instead.
///
/// Usage:
/// ```swift
/// .overlay(alignment: .top) {
///     AppointmentConflictToast(isVisible: $showConflictToast) {
///         vm.openConflictResolver()
///     }
/// }
/// ```
public struct AppointmentConflictToast: View {

    // MARK: Configuration

    @Binding public var isVisible: Bool
    public var message: String
    public var autoDismissAfter: TimeInterval
    public var onResolve: (() -> Void)?

    // MARK: Init

    public init(
        isVisible: Binding<Bool>,
        message: String = "This time slot conflicts with an existing appointment.",
        autoDismissAfter: TimeInterval = 6,
        onResolve: (() -> Void)? = nil
    ) {
        _isVisible = isVisible
        self.message = message
        self.autoDismissAfter = autoDismissAfter
        self.onResolve = onResolve
    }

    // MARK: Body

    public var body: some View {
        if isVisible {
            toastBanner
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isVisible)
                .task(id: isVisible) {
                    if isVisible {
                        try? await Task.sleep(for: .seconds(autoDismissAfter))
                        withAnimation { isVisible = false }
                    }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Toast banner

    private var toastBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduling Conflict")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Text(message)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let resolve = onResolve {
                Button("Fix") {
                    withAnimation { isVisible = false }
                    resolve()
                }
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOrange)
                .accessibilityLabel("Fix scheduling conflict")
            }

            Button {
                withAnimation { isVisible = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Dismiss conflict warning")
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreWarning.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.top, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduling conflict. \(message)")
    }
}

// MARK: - View modifier convenience

public extension View {
    /// Overlays a conflict-warning toast at the top of the view.
    ///
    /// - Parameters:
    ///   - isVisible: Binding that controls visibility.
    ///   - message: Custom warning text. Defaults to the standard conflict copy.
    ///   - autoDismissAfter: Seconds before auto-dismiss. Default 6.
    ///   - onResolve: Optional closure called when the user taps "Fix".
    func appointmentConflictToast(
        isVisible: Binding<Bool>,
        message: String = "This time slot conflicts with an existing appointment.",
        autoDismissAfter: TimeInterval = 6,
        onResolve: (() -> Void)? = nil
    ) -> some View {
        overlay(alignment: .top) {
            AppointmentConflictToast(
                isVisible: isVisible,
                message: message,
                autoDismissAfter: autoDismissAfter,
                onResolve: onResolve
            )
        }
    }
}
