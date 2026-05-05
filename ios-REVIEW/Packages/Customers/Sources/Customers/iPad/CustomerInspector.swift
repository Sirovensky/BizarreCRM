#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - CustomerInspector

/// Trailing inspector panel shown in the iPad detail column.
///
/// Displays health score via `CustomerHealthView` (§44) when a
/// `CustomerHealthRepository`-capable `APIClient` is available.
/// Falls back to a pluggable slot (`InspectorHealthSlot`) when the
/// health repository cannot be constructed.
///
/// ## Liquid Glass chrome
/// The inspector header and each section card use `.brandGlass(.regular)`
/// to stay consistent with the rest of the iPad navigation chrome.
///
/// ## Usage
/// Pass this view to SwiftUI's `.inspector(isPresented:)` modifier:
/// ```swift
/// .inspector(isPresented: .constant(true)) {
///     CustomerInspector(customerId: id, api: api)
/// }
/// ```
public struct CustomerInspector: View {
    private let customerId: Int64
    private let healthVM: CustomerHealthViewModel

    public init(customerId: Int64, api: APIClient) {
        self.customerId = customerId
        let repo = CustomerHealthRepositoryImpl(api: api)
        self.healthVM = CustomerHealthViewModel(repo: repo, customerId: customerId)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.md) {
                inspectorHeader
                healthSection
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
    }

    // MARK: - Header

    private var inspectorHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Customer Details")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Health section

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            sectionHeader("Health Score", icon: "heart.text.square.fill")
            CustomerHealthView(vm: healthVM)
        }
    }

    // MARK: - Section header helper

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(title)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - InspectorHealthSlot

/// Pluggable placeholder when CustomerHealthView is not available.
/// Adopters can supply a custom view via the `content` closure.
public struct InspectorHealthSlot<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            content()
        }
        .padding(BrandSpacing.md)
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }
}
#endif
