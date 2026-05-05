#if canImport(UIKit)
import SwiftUI
import AVFoundation
import Core
import DesignSystem
import Networking

// MARK: - §5.3 Barcode / QR scan — quick customer card lookup
//
// Tenant may print customer cards (QR or barcode) encoding the customer ID
// or a token. Staff scan them at intake for instant lookup.
// Uses AVCaptureSession (no third-party SDK — per sdk-ban rules).

// MARK: - Scanner sheet

public struct CustomerBarcodeScanSheet: View {
    let api: APIClient
    var onFound: ((Int64) -> Void)?
    var onDismiss: () -> Void

    @State private var errorMessage: String?
    @State private var isLooking = false

    public init(
        api: APIClient,
        onFound: ((Int64) -> Void)? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.api = api
        self.onFound = onFound
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                BarcodeCameraView { code in
                    guard !isLooking else { return }
                    isLooking = true
                    Task { await lookup(code: code) }
                }
                .ignoresSafeArea()

                // Targeting reticle
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                    .frame(width: 260, height: 160)
                    .shadow(color: .black.opacity(0.3), radius: 8)

                // Status
                VStack {
                    Spacer()
                    if let err = errorMessage {
                        Text(err)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(BrandSpacing.base)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, BrandSpacing.lg)
                    } else if isLooking {
                        ProgressView()
                            .tint(.white)
                            .padding(BrandSpacing.base)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Scan a customer card QR or barcode")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(BrandSpacing.base)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, BrandSpacing.lg)
                    }
                    Spacer().frame(height: 40)
                }
            }
            .navigationTitle("Scan Customer Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(.white)
                }
                if errorMessage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Retry") {
                            errorMessage = nil
                            isLooking = false
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func lookup(code: String) async {
        do {
            let customerId = try await api.lookupCustomerByCardCode(code: code)
            onFound?(customerId)
            onDismiss()
        } catch {
            errorMessage = "Customer not found for code \"\(code)\". Try again."
            isLooking = false
        }
    }
}

// MARK: - Camera capture view (AVFoundation, no SDK)

struct BarcodeCameraView: UIViewRepresentable {
    var onCodeDetected: (String) -> Void

    func makeUIView(context: Context) -> BarcodeCameraUIView {
        let v = BarcodeCameraUIView()
        v.onCodeDetected = onCodeDetected
        return v
    }
    func updateUIView(_ uiView: BarcodeCameraUIView, context: Context) {}
}

@MainActor
final class BarcodeCameraUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeDetected: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .code128, .ean13, .ean8, .code39]

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue, !value.isEmpty else { return }
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        Task { @MainActor [weak self] in
            self?.session.stopRunning()
            self?.onCodeDetected?(value)
        }
    }
}

// MARK: - Scan button for customer create/list toolbar

public struct CustomerBarcodeScanButton: View {
    let api: APIClient
    var onFound: ((Int64) -> Void)?

    @State private var showingSheet = false

    public init(api: APIClient, onFound: ((Int64) -> Void)? = nil) {
        self.api = api
        self.onFound = onFound
    }

    public var body: some View {
        Button { showingSheet = true } label: {
            Label("Scan Card", systemImage: "qrcode.viewfinder")
        }
        .accessibilityLabel("Scan customer card barcode or QR code")
        .sheet(isPresented: $showingSheet) {
            CustomerBarcodeScanSheet(api: api, onFound: onFound) {
                showingSheet = false
            }
        }
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `GET /api/v1/customers/lookup?code=:code` — resolve barcode/QR to a customer ID.
    public func lookupCustomerByCardCode(code: String) async throws -> Int64 {
        let q = [URLQueryItem(name: "code", value: code)]
        let r = try await get("/api/v1/customers/lookup", query: q, as: CustomerCardCodeLookupResponse.self)
        return r.customerId
    }
}

private struct CustomerCardCodeLookupResponse: Decodable, Sendable {
    let customerId: Int64
    enum CodingKeys: String, CodingKey { case customerId = "customer_id" }
}

#endif
