import SwiftUI

// MARK: - Preview

#if DEBUG

private let loremIpsum = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure \
dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit \
anim id est laborum.
"""

#Preview("MaxContentWidth — capped vs uncapped") {
    ScrollView {
        VStack(spacing: BrandSpacing.lg) {

            // MARK: Capped at default 720 pt
            GroupBox("Capped at 720 pt (default)") {
                Text(loremIpsum)
                    .multilineTextAlignment(.leading)
            }
            .maxContentWidth()

            Divider()

            // MARK: Capped at a narrower 480 pt
            GroupBox("Capped at 480 pt") {
                Text(loremIpsum)
                    .multilineTextAlignment(.leading)
            }
            .maxContentWidth(480)

            Divider()

            // MARK: Uncapped — full available width
            GroupBox("Uncapped (full width)") {
                Text(loremIpsum)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, BrandSpacing.base)
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("AdaptiveContentWidth — env-driven") {
    ScrollView {
        VStack(spacing: BrandSpacing.lg) {

            GroupBox("Adaptive (560 / 680 / 720 by size class)") {
                Text(loremIpsum)
                    .multilineTextAlignment(.leading)
            }
            .adaptiveContentWidth()

            Divider()

            GroupBox("Adaptive — wide padding (24 pt)") {
                Text(loremIpsum)
                    .multilineTextAlignment(.leading)
            }
            .adaptiveContentWidth(padding: BrandSpacing.lg)
        }
        .padding(.vertical, BrandSpacing.base)
    }
    .background(Color(.systemGroupedBackground))
}

#endif
