import SwiftUI

// MARK: - §30.10 Component library
//
// Reusable brand-flavored UI primitives. Every component:
//   - uses only DesignTokens / BrandColors (no inline hex/points/radii)
//   - respects Dynamic Type via `.font(.brandBody())` et al.
//   - respects Reduce Motion via `.brandAnimation()`
//   - respects Reduce Transparency via `.reduceTransparencyFallback()`
//   - is a11y-labelled where needed
//
// Components that already exist elsewhere are re-exported here as
// typealiases for discoverability.

// MARK: - BrandButton

/// Branded button with four style variants and three sizes.
///
/// ```swift
/// BrandButton("Save", style: .primary, size: .lg) { saveTapped() }
/// BrandButton("Cancel", style: .ghost)  { dismiss() }
/// BrandButton("Delete", style: .destructive) { confirmDelete() }
/// ```
public struct BrandButton: View {
    public enum Style: Sendable {
        case primary, secondary, ghost, destructive
    }
    public enum Size: Sendable {
        case sm, md, lg
        var hPad: CGFloat {
            switch self { case .sm: return 12; case .md: return 16; case .lg: return 20 }
        }
        var vPad: CGFloat {
            switch self { case .sm: return 7; case .md: return 10; case .lg: return 14 }
        }
        var font: Font {
            switch self {
            case .sm: return .brandCaption1()
            case .md: return .brandFootnote()
            case .lg: return .brandCallout()
            }
        }
    }

    private let label: String
    private let systemImage: String?
    private let style: Style
    private let size: Size
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ label: String,
        systemImage: String? = nil,
        style: Style = .primary,
        size: Size = .md,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .controlSize(.small)
                } else if let img = systemImage {
                    Image(systemName: img)
                }
                Text(label)
                    .font(size.font)
                    .fontWeight(style == .ghost ? .regular : .semibold)
            }
            .padding(.horizontal, size.hPad)
            .padding(.vertical, size.vPad)
            .frame(maxWidth: style == .primary ? .infinity : nil)
        }
        .buttonStyle(InternalBrandButtonStyle(style: style, size: size))
        .disabled(isLoading)
        .accessibilityLabel(label)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:     return .bizarreOnPrimary
        case .secondary:   return .bizarrePrimary
        case .ghost:       return .bizarrePrimary
        case .destructive: return .white
        }
    }
}

private struct InternalBrandButtonStyle: ButtonStyle {
    let style: BrandButton.Style
    let size: BrandButton.Size

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(fg)
            .background(bg(isPressed: configuration.isPressed), in: shape)
            .overlay { if style == .secondary { shape.strokeBorder(Color.bizarrePrimary, lineWidth: 1.5) } }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
    }

    private var fg: Color {
        switch style {
        case .primary:     return .bizarreOnPrimary
        case .secondary:   return .bizarrePrimary
        case .ghost:       return .bizarrePrimary
        case .destructive: return .white
        }
    }

    private func bg(isPressed: Bool) -> Color {
        let alpha: Double = isPressed ? 0.80 : 1.0
        switch style {
        case .primary:     return .bizarrePrimary.opacity(alpha)
        case .secondary:   return .clear
        case .ghost:       return .bizarrePrimary.opacity(isPressed ? 0.10 : 0)
        case .destructive: return .bizarreError.opacity(alpha)
        }
    }
}

// MARK: - BrandCard

/// Elevated surface card with brand stroke + shadow.
///
/// ```swift
/// BrandCard {
///     Text("Card content")
/// }
/// ```
public struct BrandCard<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .padding(DesignTokens.Spacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .strokeBorder(Color.bizarreOutline.opacity(0.5), lineWidth: 0.5)
            }
            .shadow(
                color: Color.black.opacity(DesignTokens.Shadows.sm.opacityDark),
                radius: DesignTokens.Shadows.sm.blur,
                y: DesignTokens.Shadows.sm.y
            )
    }
}

// MARK: - BrandTextField

/// Branded text field with floating label, hint, and error state.
///
/// ```swift
/// BrandTextField("Email", text: $email, hint: "your@email.com", error: emailError)
/// ```
public struct BrandTextField: View {
    private let label: String
    private let hint: String?
    private let error: String?
    private let isSecure: Bool
    @Binding private var text: String
    @FocusState private var isFocused: Bool

    public init(
        _ label: String,
        text: Binding<String>,
        hint: String? = nil,
        error: String? = nil,
        isSecure: Bool = false
    ) {
        self.label = label
        self._text = text
        self.hint = hint
        self.error = error
        self.isSecure = isSecure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(label)
                .font(.brandCaption1())
                .foregroundStyle(isFocused ? Color.bizarrePrimary : Color.bizarreOnSurfaceMuted)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

            Group {
                if isSecure {
                    SecureField(hint ?? "", text: $text)
                } else {
                    TextField(hint ?? "", text: $text)
                }
            }
            .font(.brandBody())
            .focused($isFocused)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            if let errorMsg = error {
                Text(errorMsg)
                    .font(.brandCaption2())
                    .foregroundStyle(Color.bizarreError)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }

    private var borderColor: Color {
        if error != nil { return .bizarreError }
        return isFocused ? .bizarrePrimary : .bizarreOutline
    }
}

// MARK: - BrandChip

/// Status / category chip with icon + tinted background.
///
/// ```swift
/// BrandChip("Open", icon: "circle.fill", color: .bizarreSuccess)
/// BrandChip(status: .open)
/// ```
public struct BrandChip: View {
    private let label: String
    private let icon: String?
    private let color: Color

    public init(_ label: String, icon: String? = nil, color: Color = .bizarrePrimary) {
        self.label = label
        self.icon = icon
        self.color = color
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.brandCaption2())
                .fontWeight(.semibold)
        }
        .foregroundStyle(color)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
        .accessibilityLabel(label)
    }
}

// MARK: - BrandEmpty

/// Branded empty state — icon + title + subtitle + optional CTA.
///
/// This is a convenience wrapper over `EmptyStateCard` that uses brand tokens.
///
/// ```swift
/// BrandEmpty(
///     icon: "ticket",
///     title: "No tickets yet",
///     subtitle: "Create your first repair ticket to get started.",
///     cta: BrandEmptyCTA("New Ticket") { createTicket() }
/// )
/// ```
public struct BrandEmptyCTA: Sendable {
    public let label: String
    public let systemImage: String?
    public let action: @Sendable @MainActor () -> Void

    public init(_ label: String, systemImage: String? = nil, action: @escaping @Sendable @MainActor () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }
}

public struct BrandEmpty: View {
    private let icon: String
    private let title: String
    private let subtitle: String?
    private let cta: BrandEmptyCTA?

    public init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        cta: BrandEmptyCTA? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.cta = cta
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Color.bizarrePrimary.opacity(0.7))

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(.brandTitle2())
                    .foregroundStyle(Color.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                if let sub = subtitle {
                    Text(sub)
                        .font(.brandBody())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
            }

            if let cta {
                BrandButton(cta.label, systemImage: cta.systemImage, style: .primary, size: .md) {
                    Task { @MainActor in cta.action() }
                }
                .frame(maxWidth: 240)
            }
        }
        .padding(DesignTokens.Spacing.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(subtitle.map { ". \($0)" } ?? "")")
    }
}

// MARK: - BrandLoading

/// Branded skeleton / loading placeholder.
///
/// Use for first-load states (replace with real content via `.redacted(reason:)`
/// or swap Views). For pull-to-refresh refreshes, use the existing rows + a
/// subtle top indicator — not a full skeleton.
///
/// ```swift
/// if viewModel.isLoading {
///     BrandLoading(rows: 5)
/// } else {
///     RealList(items: viewModel.items)
/// }
/// ```
public struct BrandLoading: View {
    private let rows: Int

    public init(rows: Int = 4) {
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonListRowShape()
            }
        }
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct SkeletonListRowShape: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(shimmer)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(shimmer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                    .fill(shimmer)
                    .frame(maxWidth: 160)
                    .frame(height: 11)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmer: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.bizarreSurface2, location: 0),
                .init(color: Color.bizarreSurface1, location: 0.4 + phase * 0.3),
                .init(color: Color.bizarreSurface2, location: 0.8 + phase * 0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - BrandBadge

/// Numeric count or status dot badge.
///
/// ```swift
/// BrandBadge(count: unreadCount)        // "12" bubble
/// BrandBadge(status: .active)           // coloured dot
/// ```
public struct BrandBadge: View {
    public enum Style: Sendable {
        case count(Int)
        case dot(Color)
    }

    private let style: Style

    public init(count: Int) {
        self.style = .count(count)
    }

    public init(dot color: Color = .bizarreError) {
        self.style = .dot(color)
    }

    public var body: some View {
        switch style {
        case .count(let n):
            if n > 0 {
                Text(n > 99 ? "99+" : "\(n)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, n > 9 ? DesignTokens.Spacing.xs : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.bizarreError, in: Capsule())
                    .accessibilityLabel("\(n) unread")
            } else {
                EmptyView()
            }
        case .dot(let color):
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - BrandToast

/// Full-width glass toast chip that floats at the top of the screen.
///
/// Typically shown via `ToastPresenter` in a `.overlay`. This View is the
/// visual component only — use `ToastPresenter` for lifetime management.
///
/// ```swift
/// BrandToast(kind: .success, message: "Ticket saved")
/// BrandToast(kind: .error, message: "Failed to connect")
/// ```
public struct BrandToast: View {
    public enum Kind: Sendable {
        case info, success, warning, error
    }

    private let kind: Kind
    private let message: String

    public init(kind: Kind = .info, message: String) {
        self.kind = kind
        self.message = message
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.brandFootnote())
                .foregroundStyle(Color.bizarreOnSurface)
                .lineLimit(2)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .reduceTransparencyFallback(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isStaticText)
    }

    private var iconName: String {
        switch kind {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .info:    return .bizarreInfo
        case .success: return .bizarreSuccess
        case .warning: return .bizarreWarning
        case .error:   return .bizarreError
        }
    }
}

// MARK: - BrandBanner

/// Sticky top banner for persistent states (offline, sync-pending, warnings).
///
/// Uses `.brandGlass(.regular)` per §30 glass rules — chrome element only.
///
/// ```swift
/// BrandBanner(kind: .offline, message: "Offline — changes saved locally") {
///     Button("Retry") { retryTapped() }
/// }
/// ```
public struct BrandBanner<Action: View>: View {
    public enum Kind: Sendable {
        case offline, syncPending, warning, info
    }

    private let kind: Kind
    private let message: String
    private let action: () -> Action

    public init(
        kind: Kind,
        message: String,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.kind = kind
        self.message = message
        self.action = action
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            Text(message)
                .font(.brandFootnote())
                .foregroundStyle(Color.bizarreOnSurface)
                .lineLimit(1)
            Spacer(minLength: 0)
            action()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .brandGlass(.regular, in: Rectangle())
        .reduceTransparencyFallback(Color.bizarreSurface1, in: Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private var iconName: String {
        switch kind {
        case .offline:     return "wifi.slash"
        case .syncPending: return "arrow.triangle.2.circlepath"
        case .warning:     return "exclamationmark.triangle.fill"
        case .info:        return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .offline:     return .bizarreWarning
        case .syncPending: return .bizarreInfo
        case .warning:     return .bizarreWarning
        case .info:        return .bizarreInfo
        }
    }
}

// MARK: - BrandBanner (no-action convenience)

public extension BrandBanner where Action == EmptyView {
    init(kind: Kind, message: String) {
        self.init(kind: kind, message: message) { EmptyView() }
    }
}

// MARK: - BrandPicker

/// Bottom-sheet picker on iPhone, popover on iPad.
///
/// ```swift
/// BrandPicker("Status", selection: $status, options: TicketStatus.allCases) { opt in
///     Text(opt.displayName)
/// }
/// ```
public struct BrandPicker<T: Hashable & Sendable, Label: View>: View {
    private let title: String
    @Binding private var selection: T
    private let options: [T]
    private let label: (T) -> Label
    @State private var isPresented = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(
        _ title: String,
        selection: Binding<T>,
        options: [T],
        @ViewBuilder label: @escaping (T) -> Label
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        Button {
            BrandHaptics.selection()
            isPresented = true
        } label: {
            HStack {
                Text(title)
                    .font(.brandCallout())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                Spacer()
                label(selection)
                    .font(.brandCallout())
                    .foregroundStyle(Color.bizarreOnSurface)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            pickerSheet
                .presentationDetents([.medium, .large])
        }
        .popover(isPresented: Binding(
            get: { isPresented && hSizeClass == .regular },
            set: { if !$0 { isPresented = false } }
        )) {
            pickerSheet
                .frame(minWidth: 300, minHeight: 300)
        }
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var pickerSheet: some View {
        NavigationStack {
            List(options, id: \.self) { option in
                Button {
                    BrandHaptics.selection()
                    selection = option
                    isPresented = false
                } label: {
                    HStack {
                        label(option)
                        Spacer()
                        if option == selection {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.bizarrePrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
