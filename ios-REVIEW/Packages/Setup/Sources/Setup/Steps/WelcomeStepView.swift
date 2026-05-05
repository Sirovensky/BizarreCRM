import SwiftUI
import DesignSystem
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - WelcomeStepView  (§36.2 Step 1)

public struct WelcomeStepView: View {
    let onGetStarted: () -> Void
    let onSkip: () -> Void

    public init(onGetStarted: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onGetStarted = onGetStarted
        self.onSkip = onSkip
    }

    private let valuePropBullets: [(icon: String, text: String)] = [
        ("bolt.fill",     "Fast repair tickets"),
        ("cart.fill",     "POS + inventory"),
        ("person.2.fill", "Customer-first")
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.xl) {
                Spacer(minLength: BrandSpacing.xxl)

                heroMark

                Text("Welcome to\nBizarre CRM")
                    .font(.brandHeadlineLarge())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.bizarreOnSurface)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Welcome to Bizarre CRM")

                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    ForEach(valuePropBullets, id: \.text) { bullet in
                        bulletRow(icon: bullet.icon, text: bullet.text)
                    }
                }
                .padding(.horizontal, BrandSpacing.xl)

                Button("Get started", action: onGetStarted)
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.xl)
                    .accessibilityLabel("Get started with the setup wizard")
                    .accessibilityHint("Proceeds to the Company Info step")

                Spacer(minLength: BrandSpacing.lg)
            }
            .padding(.horizontal, BrandSpacing.base)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Private

    @ViewBuilder
    private var heroMark: some View {
        if brandMarkExists() {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .accessibilityLabel("Bizarre CRM logo")
        } else {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityLabel("Bizarre CRM logo")
        }
    }

    /// Returns true if the "BrandMark" asset exists in the main bundle.
    private func brandMarkExists() -> Bool {
        #if canImport(UIKit)
        return UIImage(named: "BrandMark") != nil
        #elseif canImport(AppKit)
        return NSImage(named: "BrandMark") != nil
        #else
        return false
        #endif
    }

    @ViewBuilder
    private func bulletRow(icon: String, text: String) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(Color.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(text)
                .font(.brandBodyLarge())
                .foregroundStyle(Color.bizarreOnSurface)
        }
        .accessibilityElement(children: .combine)
    }
}
