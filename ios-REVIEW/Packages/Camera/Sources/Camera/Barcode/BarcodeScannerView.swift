#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import VisionKit
import AVFoundation
import Core
import DesignSystem

// MARK: - BarcodeScannerView

/// Full-screen barcode scanner using `DataScannerViewController` (iOS 16+).
///
/// Publishes a ``Barcode`` event via `onScan` callback when a code is recognized.
///
/// iPhone: full-screen modal.
/// iPad: presented as a popover / sheet (caller controls presentation; this
///       view applies `.presentationDetents([.medium, .large])` on compact
///       width and uses `intrinsicContentSize` on regular width).
///
/// When `DataScannerViewController.isSupported` is false (Mac Catalyst, old
/// simulators) the view falls back to a manual-entry field so no scan is silently
/// swallowed.
///
/// §17.2 additions:
/// - Torch toggle button (flashlight on/off)
/// - Pinch-to-zoom via `AVCaptureDevice` zoom factor
/// - Region-of-interest (ROI) center rectangle overlay
/// - Continuous/multi-scan mode with tap-to-stop button
/// - Mac Catalyst graceful fallback gate
///
/// Usage:
/// ```swift
/// .fullScreenCover(isPresented: $showScanner) {
///     BarcodeScannerView(mode: .single) { barcode in
///         handleBarcode(barcode)
///     }
/// }
/// ```
public struct BarcodeScannerView: View {

    // MARK: - Init

    private let mode: BarcodeScanMode
    private let onScan: @Sendable (Barcode) -> Void
    private let onCancel: (() -> Void)?

    public init(
        mode: BarcodeScanMode = .single,
        onScan: @escaping @Sendable (Barcode) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onScan = onScan
        self.onCancel = onCancel
        self._coordinator = State(
            wrappedValue: BarcodeCoordinator(mode: mode, onScan: onScan)
        )
    }

    // MARK: - State

    @State private var coordinator: BarcodeCoordinator
    @State private var manualCode: String = ""
    @State private var showManualEntry: Bool = false
    @State private var scanCount: Int = 0
    /// Current torch (flashlight) state.
    @State private var torchOn: Bool = false
    /// Zoom factor driven by pinch gesture (1.0 = no zoom).
    @State private var zoomFactor: CGFloat = 1.0
    /// Captured zoom at the start of each pinch gesture for delta calculation.
    @State private var baseZoomFactor: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss

    public init(
        mode: BarcodeScanMode = .single,
        onScan: @escaping @Sendable (Barcode) -> Void
    ) {
        self.mode = mode
        self.onScan = onScan
        self.onCancel = nil
        self._coordinator = State(
            wrappedValue: BarcodeCoordinator(mode: mode, onScan: onScan)
        )
    }

    // The designated full init — avoids compiler ambiguity.
    public init(
        mode: BarcodeScanMode,
        onScan: @escaping @Sendable (Barcode) -> Void,
        onCancel: (() -> Void)?,
        _internal: Bool
    ) {
        self.mode = mode
        self.onScan = onScan
        self.onCancel = onCancel
        self._coordinator = State(
            wrappedValue: BarcodeCoordinator(mode: mode) { barcode in
                onScan(barcode)
            }
        )
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if coordinator.isScannerSupported {
                scannerBody
            } else {
                fallbackBody
            }
        }
        .task { await coordinator.requestAuthorization() }
    }

    // MARK: - Scanner body

    @ViewBuilder
    private var scannerBody: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(coordinator: coordinator, mode: mode, zoomFactor: zoomFactor)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                // Pinch-to-zoom gesture
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let newZoom = (baseZoomFactor * value.magnification)
                                .clamped(to: 1.0...8.0)
                            zoomFactor = newZoom
                            coordinator.setZoom(newZoom)
                        }
                        .onEnded { _ in
                            baseZoomFactor = zoomFactor
                        }
                )

            // ROI overlay — semi-transparent frame around center scan zone
            roiOverlay

            glassOverlay
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Region-of-Interest overlay

    /// Draws a centered transparent rectangle indicating the active scan zone.
    private var roiOverlay: some View {
        GeometryReader { geo in
            let roiWidth = geo.size.width * 0.75
            let roiHeight: CGFloat = 180
            let roiX = (geo.size.width - roiWidth) / 2
            let roiY = (geo.size.height - roiHeight) / 2

            ZStack {
                // Dim surround
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                // Clear ROI cutout
                RoundedRectangle(cornerRadius: 12)
                    .blendMode(.destinationOut)
                    .frame(width: roiWidth, height: roiHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .compositingGroup()

            // Corner brackets
            roiCornerBrackets(x: roiX, y: roiY, w: roiWidth, h: roiHeight)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }

    private func roiCornerBrackets(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        let len: CGFloat = 20
        let thick: CGFloat = 3
        return ZStack {
            // Top-left
            cornerBracket(ax: x, ay: y, dx: len, dy: thick, horizontal: true)
            cornerBracket(ax: x, ay: y, dx: thick, dy: len, horizontal: false)
            // Top-right
            cornerBracket(ax: x + w - len, ay: y, dx: len, dy: thick, horizontal: true)
            cornerBracket(ax: x + w - thick, ay: y, dx: thick, dy: len, horizontal: false)
            // Bottom-left
            cornerBracket(ax: x, ay: y + h - thick, dx: len, dy: thick, horizontal: true)
            cornerBracket(ax: x, ay: y + h - len, dx: thick, dy: len, horizontal: false)
            // Bottom-right
            cornerBracket(ax: x + w - len, ay: y + h - thick, dx: len, dy: thick, horizontal: true)
            cornerBracket(ax: x + w - thick, ay: y + h - len, dx: thick, dy: len, horizontal: false)
        }
    }

    private func cornerBracket(ax: CGFloat, ay: CGFloat, dx: CGFloat, dy: CGFloat, horizontal: Bool) -> some View {
        Color.white
            .frame(width: dx, height: dy)
            .position(x: ax + dx / 2, y: ay + dy / 2)
            .cornerRadius(1.5)
    }

    // MARK: - Glass chrome overlay

    private var glassOverlay: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    onCancel?()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scanner")
                .accessibilityIdentifier("scanner.close")

                Spacer()

                if mode == .continuous {
                    countPill
                }

                Spacer()

                HStack(spacing: BrandSpacing.sm) {
                    // Torch toggle
                    torchButton

                    // Manual entry toggle
                    Button {
                        showManualEntry.toggle()
                    } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.bizarreOnSurface.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Enter barcode manually")
                    .accessibilityIdentifier("scanner.keyboard")
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.base)
            .brandGlass(.regular, in: Rectangle())

            Spacer()

            // Viewfinder hint
            viewfinderHint

            Spacer()

            // Multi-scan stop button (continuous mode only)
            if mode == .continuous {
                stopScanningButton
                    .padding(.bottom, BrandSpacing.base)
            }

            // Manual entry card (shown when keyboard button tapped)
            if showManualEntry {
                manualEntryCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: showManualEntry)
    }

    // MARK: - Torch button

    private var torchButton: some View {
        Button {
            torchOn.toggle()
            coordinator.setTorch(torchOn)
        } label: {
            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(torchOn ? .yellow : .white)
                .frame(width: 40, height: 40)
                .background(
                    torchOn ? Color.yellow.opacity(0.25) : Color.bizarreOnSurface.opacity(0.2),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
        .accessibilityIdentifier("scanner.torch")
    }

    // MARK: - Multi-scan stop button

    private var stopScanningButton: some View {
        Button {
            onCancel?()
            dismiss()
        } label: {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                Text("Stop Scanning")
                    .font(.brandBodyMedium())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.lg)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreOnSurface.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop scanning, \(scanCount) items scanned")
        .accessibilityIdentifier("scanner.stopMulti")
    }

    // MARK: - Viewfinder hint

    private var viewfinderHint: some View {
        VStack(spacing: BrandSpacing.sm) {
            if zoomFactor > 1.01 {
                Text(String(format: "%.1f×", zoomFactor))
                    .font(.brandTitleSmall())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .transition(.opacity)
            }
            Text(mode == .continuous ? "Keep scanning — tap Stop when done" : "Point at a barcode")
                .font(.brandBodyMedium())
                .foregroundStyle(.white.opacity(0.8))
        }
        .animation(.easeInOut(duration: 0.2), value: zoomFactor > 1.01)
    }

    // MARK: - Continuous scan count pill

    private var countPill: some View {
        Text("\(scanCount)")
            .font(.brandTitleSmall())
            .foregroundStyle(.white)
            .frame(minWidth: 32, minHeight: 32)
            .background(Color.bizarreOrange, in: Capsule())
            .accessibilityLabel("\(scanCount) barcodes scanned")
    }

    // MARK: - Manual entry card

    private var manualEntryCard: some View {
        VStack(spacing: BrandSpacing.base) {
            Text("Enter barcode manually")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: BrandSpacing.sm) {
                TextField("SKU / barcode", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.asciiCapable)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .accessibilityIdentifier("scanner.manualField")
                    .onSubmit { submitManual() }

                Button("Scan") {
                    submitManual()
                }
                .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityIdentifier("scanner.manualSubmit")
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, BrandSpacing.base)
        .padding(.bottom, BrandSpacing.xl)
    }

    // MARK: - Fallback (Mac Catalyst / unsupported)
    //
    // §17.2: Mac Catalyst — DataScannerViewController is unavailable on macOS.
    // Feature-gated to manual-entry + a note pointing to continuity camera.

    private var fallbackBody: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.xl) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                Text("Barcode Scanner Unavailable")
                    .font(.brandHeadlineMedium())
                    .foregroundStyle(.bizarreOnSurface)

                macCatalystHint

                fallbackField
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("Enter Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var macCatalystHint: some View {
#if targetEnvironment(macCatalyst)
        VStack(spacing: BrandSpacing.sm) {
            Text("On Mac, use Continuity Camera to scan with your iPhone.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.base)
            Text("Or type the barcode / SKU below.")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.7))
        }
#else
        Text("The camera scanner is not supported on this device. Enter the code manually.")
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurfaceMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, BrandSpacing.base)
#endif
    }

    private var fallbackField: some View {
        VStack(spacing: BrandSpacing.sm) {
            TextField("SKU / barcode", text: $manualCode)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .accessibilityIdentifier("scanner.fallbackField")
                .onSubmit { submitManual() }

            Button("Confirm") {
                submitManual()
            }
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("scanner.fallbackSubmit")
        }
        .padding(.horizontal, BrandSpacing.base)
    }

    // MARK: - Helpers

    private func submitManual() {
        let trimmed = manualCode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let barcode = Barcode(value: trimmed, symbology: "manual")
        onScan(barcode)
        if mode == .single {
            dismiss()
        } else {
            scanCount += 1
            manualCode = ""
            showManualEntry = false
        }
    }
}

// MARK: - Comparable clamped helper (local, avoids cross-module import)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - DataScannerRepresentable

/// `UIViewControllerRepresentable` bridging `DataScannerViewController`
/// into SwiftUI. The lifecycle (start / stop scanning) is mirrored via
/// `onAppear` / `onDisappear` in the coordinator.
private struct DataScannerRepresentable: UIViewControllerRepresentable {

    let coordinator: BarcodeCoordinator
    let mode: BarcodeScanMode
    /// Current zoom factor; passed in so SwiftUI re-calls `updateUIViewController`
    /// when the pinch gesture changes it.
    var zoomFactor: CGFloat

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: BarcodeCoordinator.recognizedDataTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Apply zoom factor to the underlying AVCaptureDevice.
        if let device = AVCaptureDevice.default(for: .video) {
            try? device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                        min(zoomFactor, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        }
    }

    func makeCoordinator() -> Void {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Void) {
        if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }
}

extension DataScannerRepresentable {
    // SwiftUI calls these as the host view appears / disappears.
    func makeUIViewControllerBody(context: Context) -> DataScannerViewController {
        makeUIViewController(context: context)
    }
}

// MARK: - iPad popover variant

/// iPad-specific popover presentation modifier for ``BarcodeScannerView``.
/// Use `.barcodeScannerPopover(isPresented:onScan:)` on iPad.
extension View {
    /// Presents ``BarcodeScannerView`` as a popover on iPad and a sheet on iPhone.
    public func barcodeScannerSheet(
        isPresented: Binding<Bool>,
        mode: BarcodeScanMode = .single,
        onScan: @escaping @Sendable (Barcode) -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            BarcodeScannerView(mode: mode, onScan: { barcode in
                onScan(barcode)
                isPresented.wrappedValue = false
            })
            .presentationDetents(Platform.isCompact ? [.large] : [.medium, .large])
        }
    }
}

#endif
