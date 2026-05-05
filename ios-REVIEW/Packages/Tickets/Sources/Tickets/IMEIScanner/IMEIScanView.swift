#if canImport(UIKit)
import SwiftUI
import AVFoundation
import Core
import DesignSystem

/// §4 — IMEI/serial scanner.
/// Combines camera barcode scanning with a manual-entry fallback.
/// Validates with Luhn (15-digit) via `IMEIValidator`.
public struct IMEIScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manualEntry: String = ""
    @State private var isScanning = false
    @State private var scanResult: String?
    @State private var validationError: String?
    @State private var conflictResult: IMEIConflictChecker.ConflictResult?
    @State private var isCheckingConflict = false

    private let onConfirm: @Sendable (String) -> Void
    private let conflictChecker: IMEIConflictChecker?

    public init(
        conflictChecker: IMEIConflictChecker? = nil,
        onConfirm: @escaping @Sendable (String) -> Void
    ) {
        self.conflictChecker = conflictChecker
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.lg) {
                    scannerPreviewPlaceholder
                    manualEntrySection
                    if let err = validationError {
                        errorBanner(err)
                    }
                    if let conflict = conflictResult {
                        conflictBanner(conflict)
                    }
                    confirmButton
                }
                .padding(BrandSpacing.base)
            }
            .navigationTitle("Scan IMEI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Scanner placeholder
    // In a real app this would embed AVCaptureVideoPreviewLayer.
    // We keep it as a tappable placeholder so the view compiles without
    // AVFoundation entitlements in unit-test targets.
    private var scannerPreviewPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.85))
                .frame(height: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.bizarreOrange, lineWidth: 2)
                )
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                Text("Point camera at barcode")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .accessibilityLabel("Camera viewfinder for barcode scan")
        .accessibilityHint("Point camera at device barcode or IMEI label")
    }

    // MARK: - Manual entry

    private var manualEntrySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Or enter manually")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            HStack(spacing: BrandSpacing.sm) {
                TextField("IMEI (15 digits)", text: $manualEntry)
                    .keyboardType(.numberPad)
                    .font(.brandMono(size: 16))
                    .padding(BrandSpacing.md)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                manualEntry.isEmpty ? Color.bizarreOutline.opacity(0.4) :
                                    (IMEIValidator.isValid(manualEntry) ? Color.bizarreSuccess : Color.bizarreError),
                                lineWidth: 1
                            )
                    )
                    .onChange(of: manualEntry) { _, new in
                        handleManualChange(new)
                    }
                    .accessibilityLabel("IMEI number field")
                    .accessibilityHint("Enter 15-digit IMEI number")

                if !manualEntry.isEmpty {
                    Image(systemName: IMEIValidator.isValid(manualEntry) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(IMEIValidator.isValid(manualEntry) ? Color.bizarreSuccess : Color.bizarreError)
                        .accessibilityLabel(IMEIValidator.isValid(manualEntry) ? "Valid IMEI" : "Invalid IMEI")
                }
            }
        }
    }

    // MARK: - Banners

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(msg)")
    }

    private func conflictBanner(_ conflict: IMEIConflictChecker.ConflictResult) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                Text("Already in for repair")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOrange)
            }
            Text("Ticket \(conflict.orderId)\(conflict.statusName.map { " — \($0)" } ?? "")")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(BrandSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: IMEI already in for repair, ticket \(conflict.orderId)")
    }

    // MARK: - Confirm

    private var confirmButton: some View {
        Button {
            let imei = manualEntry.filter(\.isNumber)
            guard IMEIValidator.isValid(imei) else {
                validationError = "IMEI must be 15 digits and pass the Luhn check."
                return
            }
            onConfirm(imei)
            dismiss()
        } label: {
            Group {
                if isCheckingConflict {
                    ProgressView()
                } else {
                    Text("Use This IMEI")
                        .font(.brandBodyLarge())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.md)
        }
        .buttonStyle(.borderedProminent)
        .tint(.bizarreOrange)
        .disabled(!IMEIValidator.isValid(manualEntry) || isCheckingConflict)
        .accessibilityLabel("Confirm IMEI")
    }

    // MARK: - Handlers

    private func handleManualChange(_ new: String) {
        validationError = nil
        conflictResult = nil
        let digits = new.filter(\.isNumber)
        if digits.count == 15 && IMEIValidator.isValid(digits) {
            Task { await checkConflict(digits) }
        }
    }

    @MainActor
    private func checkConflict(_ imei: String) async {
        guard let checker = conflictChecker else { return }
        isCheckingConflict = true
        defer { isCheckingConflict = false }
        conflictResult = try? await checker.check(imei: imei)
    }
}
#endif
