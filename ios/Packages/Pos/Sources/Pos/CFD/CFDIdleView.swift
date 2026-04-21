#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16 CFD — Shown on the secondary display when no active cart is loaded.
/// Displays a rotating brand placeholder animation and the tenant's
/// configurable marketing message.
///
/// Reduce Motion: auto-rotate is paused; the first image stays static.
public struct CFDIdleView: View {

    // Read the idle message from UserDefaults. CFDSettingsView writes it.
    @AppStorage(CFDSettingsView.Keys.idleMessage) private var idleMessage: String = "Welcome! Your cashier will be with you shortly."

    @State private var currentIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rotationInterval: TimeInterval = 5

    // Placeholder brand slides (system symbols until real artwork is supplied).
    private let slides: [String] = [
        "cart.fill",
        "star.fill",
        "gift.fill",
        "creditcard.fill"
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer()

            ZStack {
                ForEach(slides.indices, id: \.self) { index in
                    Image(systemName: slides[index])
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .foregroundStyle(.bizarreOrange.opacity(0.7))
                        .opacity(index == currentIndex ? 1 : 0)
                        .scaleEffect(index == currentIndex ? 1 : 0.9)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: currentIndex)
                }
            }
            .accessibilityHidden(true)

            Text(idleMessage)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xxl)
                .accessibilityIdentifier("cfd.idle.message")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !reduceMotion else { return }
            await rotateSlides()
        }
    }

    // MARK: - Private helpers

    private func rotateSlides() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rotationInterval))
            withAnimation {
                currentIndex = (currentIndex + 1) % slides.count
            }
        }
    }
}
#endif
