// §57.1 ETAChangedBanner — overlay banner that slides in when the server
// pushes an updated ETA for the current job.
//
// Usage:
//   Map content…
//     .overlay(alignment: .top) {
//         ETAChangedBanner(
//             previousMinutes: previousETA,
//             newMinutes: newETA,
//             isPresented: $showETABanner
//         )
//     }
//
// The banner auto-dismisses after `autoDismissDelay` seconds.
// Reduce Motion: slide animation is replaced by opacity fade.
// A11y: banner posts a VoiceOver announcement on appear.

import SwiftUI

// MARK: - ETAChangedBanner

public struct ETAChangedBanner: View {

    // MARK: - Configuration

    public let previousMinutes: Int
    public let newMinutes: Int
    @Binding public var isPresented: Bool

    public var autoDismissDelay: Double = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        previousMinutes: Int,
        newMinutes: Int,
        isPresented: Binding<Bool>,
        autoDismissDelay: Double = 5
    ) {
        self.previousMinutes = previousMinutes
        self.newMinutes = newMinutes
        self._isPresented = isPresented
        self.autoDismissDelay = autoDismissDelay
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if isPresented {
                bannerContent
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(autoDismissDelay))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            isPresented = false
                        }
                    }
                    .onAppear {
                        postA11yAnnouncement()
                    }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: isPresented)
    }

    // MARK: - Banner content

    private var bannerContent: some View {
        HStack(spacing: 12) {
            Image(systemName: deltaIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(deltaColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("ETA Updated")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitleText)
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss ETA banner")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(deltaColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Helpers

    private var isLater: Bool { newMinutes > previousMinutes }
    private var delta: Int { abs(newMinutes - previousMinutes) }

    private var deltaIcon: String {
        isLater ? "clock.badge.exclamationmark" : "clock.badge.checkmark"
    }

    private var deltaColor: Color {
        isLater ? Color(red: 1.0, green: 0.42, blue: 0.12) : Color(red: 0.2, green: 0.75, blue: 0.35)
    }

    private var subtitleText: String {
        let direction = isLater ? "later" : "sooner"
        return "\(delta) min \(direction) — now \(newMinutes) min away"
    }

    private var a11yLabel: String {
        let direction = isLater ? "later" : "sooner"
        return "ETA updated: \(delta) minutes \(direction). Now \(newMinutes) minutes away."
    }

    private func postA11yAnnouncement() {
        #if canImport(UIKit)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIAccessibility.post(notification: .announcement, argument: a11yLabel)
        }
        #endif
    }
}
