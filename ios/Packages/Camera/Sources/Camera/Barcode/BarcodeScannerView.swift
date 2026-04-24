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
            DataScannerRepresentable(coordinator: coordinator, mode: mode)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            glassOverlay
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Scan Barcode")
        .navigationBarTitleDisplayMode(.inline)
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
                        .background(Color.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close scanner")
                .accessibilityIdentifier("scanner.close")

                Spacer()

                if mode == .continuous {
                    countPill
                }

                Spacer()

                // Manual entry toggle
                Button {
                    showManualEntry.toggle()
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enter barcode manually")
                .accessibilityIdentifier("scanner.keyboard")
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.top, BrandSpacing.base)
            .brandGlass(.regular, in: Rectangle())

            Spacer()

            // Viewfinder hint
            viewfinderHint

            Spacer()

            // Manual entry card (shown when keyboard button tapped)
            if showManualEntry {
                manualEntryCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.snappy), value: showManualEntry)
    }

    // MARK: - Viewfinder hint

    private var viewfinderHint: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "viewfinder")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
            Text("Point at a barcode")
                .font(.brandBodyMedium())
                .foregroundStyle(.white.opacity(0.8))
        }
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

                Text("The camera scanner is not supported on this device. Enter the code manually.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.base)

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

// MARK: - DataScannerRepresentable

/// `UIViewControllerRepresentable` bridging `DataScannerViewController`
/// into SwiftUI. The lifecycle (start / stop scanning) is mirrored via
/// `onAppear` / `onDisappear` in the coordinator.
private struct DataScannerRepresentable: UIViewControllerRepresentable {

    let coordinator: BarcodeCoordinator
    let mode: BarcodeScanMode

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

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

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
