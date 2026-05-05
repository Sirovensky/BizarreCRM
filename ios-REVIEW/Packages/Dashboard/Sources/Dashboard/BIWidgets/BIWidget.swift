import SwiftUI
import DesignSystem

// MARK: - BIWidget
//
// Shared protocol every BI widget conforms to.
// Widgets are self-contained: each owns its own ViewModel + View.

/// Phase state shared across all BI widget view-models.
public enum BIWidgetState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(String)
}

/// Adopted by every BI widget ViewModel. @MainActor — all mutations happen on main.
@MainActor
public protocol BIWidgetViewModel: AnyObject, Observable {
    associatedtype Data: Sendable
    var title: String { get }
    var state: BIWidgetState<Data> { get }
    func load() async
}

/// A SwiftUI view that can be placed inside BIWidgetGridView.
public protocol BIWidgetView: View {
    var widgetTitle: String { get }
}

// MARK: - BIWidgetChrome
//
// Shared outer shell: title bar with glass chrome, content area bare.
// Liquid Glass on the chrome only — never on chart content (per CLAUDE.md).

public struct BIWidgetChrome<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    public init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Chrome header — Liquid Glass applied here only
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .tracking(0.5)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .brandGlass(.regular, in: UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 14
            ))

            // Content — bare surface, no glass
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.35), lineWidth: 0.5)
        )
    }
}

// MARK: - BIWidgetLoadingOverlay

struct BIWidgetLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.bizarreSurface1
            ProgressView()
                .tint(.bizarreOnSurfaceMuted)
        }
        .frame(minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - BIWidgetEmptyState

struct BIWidgetEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 8)
    }
}

// MARK: - BIWidgetErrorState

struct BIWidgetErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
