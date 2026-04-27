#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

/// §16 CFD — Shown on the secondary display when no active cart is loaded.
///
/// **§16 Marketing slideshow** — when `slideShowEnabled` is `true` (set in
/// `CFDSettingsView`) and the display has been idle for more than 30 seconds,
/// the view switches into slideshow mode and rotates tenant-configured
/// promotional slides. Tapping anywhere exits the slideshow back to the idle
/// message. Each slide shows a system-symbol placeholder until real artwork
/// is supplied via the §30 asset-upload pipeline.
///
/// Reduce Motion: auto-rotate is paused; the first image stays static; no
/// cross-fade animation between slides.
public struct CFDIdleView: View {

    @AppStorage(CFDSettingsView.Keys.idleMessage)    private var idleMessage:      String = "Welcome! Your cashier will be with you shortly."
    @AppStorage(CFDSettingsView.Keys.slideShowEnabled) private var slideShowEnabled: Bool   = false

    @State private var currentIndex: Int = 0
    @State private var inSlideShow:  Bool = false
    @State private var idleSeconds:  Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the display must be idle (seconds) before the slideshow starts.
    private let slideshowTriggerSeconds: Int = 30
    /// Duration (seconds) each slideshow slide is visible.
    private let rotationInterval: TimeInterval = 5

    // Placeholder brand slides (system symbols until real artwork is supplied).
    // In production, tenant-uploaded images will replace these entries.
    private let slides: [CFDSlide] = [
        CFDSlide(symbol: "cart.fill",      headline: "Shop with confidence",  body: "Quality repairs you can trust."),
        CFDSlide(symbol: "star.fill",      headline: "Leave us a review",     body: "Tell us how we did!"),
        CFDSlide(symbol: "gift.fill",      headline: "Gift cards available",  body: "Give the gift of repairs."),
        CFDSlide(symbol: "creditcard.fill", headline: "Flexible payments",    body: "We accept all major methods."),
    ]

    public init() {}

    public var body: some View {
        ZStack {
            if inSlideShow && slideShowEnabled {
                slideshowContent
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                    .onTapGesture { exitSlideshow() }
            } else {
                idleContent
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: inSlideShow)
        .task {
            await runIdleTimer()
        }
    }

    // MARK: - Idle content (default state)

    private var idleContent: some View {
        VStack(spacing: BrandSpacing.xxl) {
            Spacer()

            Image(systemName: slides[0].symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(.bizarreOrange.opacity(0.7))
                .accessibilityHidden(true)

            Text(idleMessage)
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xxl)
                .accessibilityIdentifier("cfd.idle.message")

            if slideShowEnabled {
                Text("Slideshow in \(max(0, slideshowTriggerSeconds - idleSeconds))s…")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }

            Spacer()
        }
    }

    // MARK: - Slideshow content

    private var slideshowContent: some View {
        let slide = slides[currentIndex % slides.count]
        return VStack(spacing: BrandSpacing.xl) {
            Spacer()

            ZStack {
                ForEach(slides.indices, id: \.self) { index in
                    Image(systemName: slides[index].symbol)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .foregroundStyle(.bizarreOrange.opacity(0.7))
                        .opacity(index == currentIndex % slides.count ? 1 : 0)
                        .scaleEffect(index == currentIndex % slides.count ? 1 : 0.9)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: currentIndex)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: BrandSpacing.sm) {
                Text(slide.headline)
                    .font(.brandHeadlineLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text(slide.body)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BrandSpacing.xxl)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: currentIndex)

            Text("Tap anywhere to exit")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)

            Spacer()
        }
        .accessibilityLabel("\(slide.headline). \(slide.body). Marketing slide \(currentIndex + 1) of \(slides.count).")
        .accessibilityIdentifier("cfd.slideshow")
    }

    // MARK: - Timer loop

    private func runIdleTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            idleSeconds += 1

            // Trigger slideshow after threshold
            if slideShowEnabled && !reduceMotion && idleSeconds >= slideshowTriggerSeconds && !inSlideShow {
                withAnimation { inSlideShow = true }
            }

            // While in slideshow, rotate slides every `rotationInterval` seconds
            if inSlideShow && Int(idleSeconds) % Int(rotationInterval) == 0 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    currentIndex += 1
                }
            }
        }
    }

    private func exitSlideshow() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
            inSlideShow = false
            idleSeconds = 0
        }
    }
}

// MARK: - CFDSlide

/// A single marketing slide for the CFD idle slideshow.
/// In production, tenant-uploaded images will be bundled as URLs via §30.
private struct CFDSlide {
    let symbol: String    // SF Symbol name (placeholder)
    let headline: String  // Primary promo text
    let body: String      // Supporting text
}
#endif
