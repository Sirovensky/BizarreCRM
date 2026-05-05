#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import Core

// MARK: - DocumentScannerView

/// Public alias for ``DocumentScanner`` using the `View`-suffixed naming
/// convention required by the Camera package public API.
///
/// Usage:
/// ```swift
/// .fullScreenCover(isPresented: $showScanner) {
///     DocumentScannerView(
///         onFinished: { result in process(result) },
///         onCanceled: { showScanner = false },
///         onError:    { err in handle(err) }
///     )
/// }
/// ```
///
/// iPhone: use `.fullScreenCover`.
/// iPad: use `.sheet` with `.presentationDetents([.large])`.
public struct DocumentScannerView: View {

    private let onFinished: @Sendable (ScanResult) -> Void
    private let onCanceled: @Sendable () -> Void
    private let onError:    @Sendable (Error) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(
        onFinished: @escaping @Sendable (ScanResult) -> Void,
        onCanceled: @escaping @Sendable () -> Void,
        onError:    @escaping @Sendable (Error) -> Void
    ) {
        self.onFinished = onFinished
        self.onCanceled = onCanceled
        self.onError    = onError
    }

    public var body: some View {
        DocumentScanner(
            onFinished: onFinished,
            onCanceled: onCanceled,
            onError:    onError
        )
    }
}

#endif
