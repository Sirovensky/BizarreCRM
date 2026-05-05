#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5.7 — Devices section embedded in CustomerDetailView.

public struct CustomerDeviceListView: View {
    @State private var devices: [CustomerDevice] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedDevice: CustomerDevice? = nil

    private let api: APIClient
    private let customerId: Int64

    public init(api: APIClient, customerId: Int64) {
        self.api = api
        self.customerId = customerId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Devices")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, BrandSpacing.sm)
            } else if devices.isEmpty {
                Text("No devices on file.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            } else {
                ForEach(devices) { device in
                    Button {
                        selectedDevice = device
                    } label: {
                        deviceRow(device)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(deviceAccessLabel(device))
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(item: $selectedDevice) { device in
            CustomerDeviceDetailView(api: api, customerId: customerId, device: device)
        }
    }

    private func load() async {
        isLoading = devices.isEmpty
        defer { isLoading = false }
        errorMessage = nil
        do {
            devices = try await api.customerDevices(id: customerId)
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }

    private func deviceRow(_ d: CustomerDevice) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "laptopcomputer.and.iphone")
                .foregroundStyle(.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.deviceName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if let imei = d.imei, !imei.isEmpty {
                    Text("IMEI: \(imei)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                } else if let serial = d.serial, !serial.isEmpty {
                    Text("S/N: \(serial)")
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private func deviceAccessLabel(_ d: CustomerDevice) -> String {
        var parts = [d.deviceName]
        if let imei = d.imei, !imei.isEmpty { parts.append("IMEI \(imei)") }
        else if let serial = d.serial, !serial.isEmpty { parts.append("Serial \(serial)") }
        return parts.joined(separator: ", ")
    }
}
#endif
