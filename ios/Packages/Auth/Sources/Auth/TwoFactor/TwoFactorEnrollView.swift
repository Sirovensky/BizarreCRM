#if canImport(UIKit)
import SwiftUI
import UIKit
import Core
import DesignSystem
import UniformTypeIdentifiers

// MARK: - TwoFactorEnrollView
// iPhone: NavigationStack wizard with step indicator in glass toolbar.
// iPad: .sheet centered card, 520pt wide.

public struct TwoFactorEnrollView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm: TwoFactorEnrollmentViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vm: TwoFactorEnrollmentViewModel) {
        _vm = State(initialValue: vm)
    }

    public var body: some View {
        if Platform.isCompact {
            phoneLayout
        } else {
            padLayout
        }
    }

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        NavigationStack {
            stepContent
                .navigationTitle("Enable 2FA")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
        }
    }

    // MARK: - iPad layout

    private var padLayout: some View {
        NavigationStack {
            stepContent
                .navigationTitle("Enable 2FA")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
        }
        .frame(width: 520)
    }

    // MARK: - Toolbar (glass chrome)

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            StepIndicatorView(totalSteps: 4, currentStep: currentStep)
                .brandGlass(.clear, in: Capsule())
                .padding(.horizontal, BrandSpacing.sm)
                .accessibilityLabel("Step \(currentStep) of 4")
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
    }

    private var currentStep: Int {
        switch vm.state {
        case .idle: return 1
        case .enrolling, .showingQR: return 2
        case .verifying: return 3
        case .showingCodes, .done: return 4
        case .error: return 2
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch vm.state {
        case .idle:
            IntroStep(onContinue: { Task { await vm.continueFromIntro() } })
        case .enrolling:
            ProgressView("Setting up…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .showingQR, .verifying:
            QRStep(vm: vm)
        case .showingCodes:
            BackupCodesStep(vm: vm, onDone: { dismiss() })
        case .done:
            EmptyView().onAppear { dismiss() }
        case .error(let msg):
            ErrorStep(message: msg, onRetry: { vm.reset() })
        }
    }
}

// MARK: - Step 1: Intro

private struct IntroStep: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.bizarreOrange)
                    .padding(.top, BrandSpacing.xxl)
                    .accessibilityHidden(true)

                Text("Two-Factor Authentication")
                    .font(.brandHeadlineMedium())
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: BrandSpacing.md) {
                    FeatureBullet(icon: "qrcode", text: "Scan a QR code with your authenticator app (Google Authenticator, Authy, or iCloud Keychain).")
                    FeatureBullet(icon: "key.fill", text: "Each login requires a time-based 6-digit code from your app.")
                    FeatureBullet(icon: "doc.on.doc.fill", text: "You'll receive 10 backup codes to use if you lose access to your app.")
                }
                .padding(.horizontal, BrandSpacing.base)

                Button("Continue", action: onContinue)
                    .buttonStyle(.brandGlassProminent)
                    .tint(.bizarreOrange)
                    .padding(.horizontal, BrandSpacing.base)
                    .padding(.top, BrandSpacing.lg)
                    .accessibilityHint("Begins the 2FA enrollment process")
            }
            .padding(.bottom, BrandSpacing.xxl)
        }
    }
}

private struct FeatureBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            Image(systemName: icon)
                .foregroundStyle(.bizarreTeal)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
        }
    }
}

// MARK: - Step 2+3: QR + Verify

private struct QRStep: View {
    @Bindable var vm: TwoFactorEnrollmentViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                qrSection
                secretSection
                verifySection
            }
            .padding(BrandSpacing.base)
        }
        .overlay {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var qrSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("Scan this QR code")
                .font(.brandTitleLarge())

            if vm.otpauthURI.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .overlay(ProgressView())
            } else {
                if let img = TwoFactorQRGenerator.qrImage(
                    from: vm.otpauthURI,
                    size: CGSize(width: 200, height: 200)
                ) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .cornerRadius(8)
                        .accessibilityLabel("QR code. If you can't scan it, use the manual entry key shown below.")
                        .accessibilityValue(vm.otpauthURI)
                }
            }

            Text("Open your authenticator app and scan the code above.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var secretSection: some View {
        DisclosureGroup("Can't scan? Enter key manually") {
            Text(vm.secret)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(BrandSpacing.sm)
                .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Manual entry key: \(vm.secret.map { String($0) }.joined(separator: " "))")
        }
        .font(.brandBodyMedium())
    }

    private var verifySection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Enter the 6-digit code")
                .font(.brandTitleSmall())

            TextField("000000", text: $vm.verifyCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(.title2, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(BrandSpacing.md)
                .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("6-digit TOTP code")
                .onChange(of: vm.verifyCode) { _, new in
                    vm.verifyCode = String(new.filter(\.isNumber).prefix(6))
                }

            if let err = vm.verifyFieldError {
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }

            Button("Verify Code") {
                Task { await vm.submitVerifyCode() }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(vm.isLoading)
        }
    }
}

// MARK: - Step 4: Backup Codes

private struct BackupCodesStep: View {
    @Bindable var vm: TwoFactorEnrollmentViewModel
    let onDone: () -> Void

    @State private var showingDocPicker = false
    @State private var exportFileURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                headerSection
                codesGrid
                actionsSection
                confirmationSection
            }
            .padding(BrandSpacing.base)
        }
        .sheet(isPresented: $showingDocPicker) {
            if let url = exportFileURL {
                DocumentExporter(url: url)
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "key.2.on.ring.fill")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Save your recovery codes")
                .font(.brandHeadlineMedium())

            Text("These 10 codes can be used once each if you lose access to your authenticator app. Store them somewhere safe — they won't be shown again.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var codesGrid: some View {
        VStack(spacing: BrandSpacing.xs) {
            ForEach(Array(vm.recoveryCodeList.grid.enumerated()), id: \.offset) { _, pair in
                HStack {
                    codeCell(pair.0)
                    if let right = pair.1 {
                        codeCell(right)
                    }
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
    }

    private func codeCell(_ code: String) -> some View {
        Text(code)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityLabel("Recovery code: \(code.map { String($0) }.joined(separator: " "))")
    }

    private var actionsSection: some View {
        HStack(spacing: BrandSpacing.md) {
            Button {
                UIPasteboard.general.string = vm.recoveryCodeList.exportText
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Copy all recovery codes to clipboard")

            Button {
                exportToFiles()
            } label: {
                Label("Save to Files", systemImage: "folder")
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Save recovery codes to Files app")
        }
    }

    private var confirmationSection: some View {
        VStack(spacing: BrandSpacing.md) {
            Toggle(isOn: $vm.hasSavedCodes) {
                Text("I've saved my recovery codes in a safe place")
                    .font(.brandBodyMedium())
            }
            .tint(.bizarreOrange)
            .accessibilityLabel("Confirm you've saved recovery codes")

            Button("Finish") {
                vm.confirmSaved()
                onDone()
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.hasSavedCodes)
            .accessibilityHint(vm.hasSavedCodes ? "Complete 2FA setup" : "Check the box above first")
        }
    }

    private func exportToFiles() {
        let text = vm.recoveryCodeList.exportText
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BizarreCRM-recovery-codes.txt")
        try? text.write(to: tmpURL, atomically: true, encoding: .utf8)
        exportFileURL = tmpURL
        showingDocPicker = true
    }
}

// MARK: - Error step

private struct ErrorStep: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)

            Text(message)
                .font(.brandBodyLarge())
                .multilineTextAlignment(.center)
                .accessibilityLabel("Error: \(message)")

            Button("Try Again", action: onRetry)
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step indicator (glass chrome)

private struct StepIndicatorView: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            ForEach(1...totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.bizarreOrange : Color.bizarreOutline)
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
    }
}

// MARK: - UIDocumentPickerViewController wrapper

private struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
#endif
