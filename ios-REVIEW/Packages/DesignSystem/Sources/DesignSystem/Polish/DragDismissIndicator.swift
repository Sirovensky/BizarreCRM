import SwiftUI

// MARK: - DragDismissIndicator

/// Visual cue for draggable bottom sheets and modal presentations.
///
/// A small rounded pill placed at the top of a sheet to signal
/// drag-to-dismiss is available. Honors Reduce Motion (fade-only appearance).
///
/// **Usage — place at top of sheet content:**
/// ```swift
/// .sheet(isPresented: $showSheet) {
///     VStack {
///         DragDismissIndicator()
///         // ... sheet content
///     }
/// }
/// ```
public struct DragDismissIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Width of the indicator pill.
    public var width: CGFloat = 36
    /// Height of the indicator pill.
    public var height: CGFloat = 4

    public init(width: CGFloat = 36, height: CGFloat = 4) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.primary.opacity(0.25))
            .frame(width: width, height: height)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xs)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(
                    reduceMotion
                    ? .linear(duration: 0.15)
                    : .easeOut(duration: DesignTokens.Motion.snappy)
                ) {
                    appeared = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - View extension

public extension View {
    /// Prepends a `DragDismissIndicator` inside a `VStack` at the top.
    ///
    /// Convenience so sheet bodies don't need to manually wrap:
    /// ```swift
    /// .sheet(...) { MySheetContent().dragDismissIndicator() }
    /// ```
    func dragDismissIndicator() -> some View {
        VStack(spacing: 0) {
            DragDismissIndicator()
            self
        }
    }
}
