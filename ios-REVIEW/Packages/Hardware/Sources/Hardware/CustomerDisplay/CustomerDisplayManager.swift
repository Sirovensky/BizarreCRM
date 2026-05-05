#if canImport(UIKit)
import UIKit
import SwiftUI
import Core

// §17.8 Customer-facing display.
//
// iPad with external display via USB-C/HDMI or AirPlay to Apple TV.
// Shows cart mirror + tip prompt on the external screen.
//
// Architecture:
//   - `CustomerDisplayManager` owns the `UIWindow` on the external screen.
//   - POS passes `CustomerDisplayModel` updates; manager re-renders.
//   - Primary path: USB-C/HDMI via `UIScreen.screens` (wired).
//   - Fallback: AirPlay via same `UIScreen.screens` API when Apple TV is selected.
//
// Usage:
//   1. Instantiate in `AppServices` (or POS ViewModel).
//   2. Call `start()` once to observe screen connect/disconnect events.
//   3. Push `CustomerDisplayModel` updates via `update(model:)`.
//   4. Call `showTipPrompt(options:)` at charge time.

// MARK: - CustomerDisplayModel

/// Data pushed to the external customer-facing display.
public struct CustomerDisplayModel: Sendable, Equatable {
    public struct LineItem: Sendable, Equatable {
        public let name: String
        public let quantityLabel: String  // "1×" or "2.3 lb"
        public let priceCentsLabel: String
        public init(name: String, quantityLabel: String, priceCentsLabel: String) {
            self.name = name
            self.quantityLabel = quantityLabel
            self.priceCentsLabel = priceCentsLabel
        }
    }

    public let tenantName: String
    public let lineItems: [LineItem]
    public let subtotalLabel: String
    public let taxLabel: String
    public let totalLabel: String
    /// When `nil` the display shows the cart mirror.
    /// When set, the display switches to a tip-selection screen.
    public let tipPromptOptions: [TipOption]?

    public init(
        tenantName: String,
        lineItems: [LineItem],
        subtotalLabel: String,
        taxLabel: String,
        totalLabel: String,
        tipPromptOptions: [TipOption]? = nil
    ) {
        self.tenantName = tenantName
        self.lineItems = lineItems
        self.subtotalLabel = subtotalLabel
        self.taxLabel = taxLabel
        self.totalLabel = totalLabel
        self.tipPromptOptions = tipPromptOptions
    }
}

// MARK: - TipOption

public struct TipOption: Sendable, Equatable, Identifiable {
    public let id: String
    /// Display label shown to customer (e.g. "18%", "$2.00", "No Tip").
    public let label: String
    public let amountCents: Int

    public init(id: String = UUID().uuidString, label: String, amountCents: Int) {
        self.id = id
        self.label = label
        self.amountCents = amountCents
    }

    /// Standard percentage options for a given total.
    public static func standard(totalCents: Int) -> [TipOption] {
        let pcts: [(String, Int)] = [("No Tip", 0), ("15%", 15), ("18%", 18), ("20%", 20), ("25%", 25)]
        return pcts.map { label, pct in
            TipOption(
                label: label,
                amountCents: pct == 0 ? 0 : (totalCents * pct + 50) / 100
            )
        }
    }
}

// MARK: - CustomerDisplayManager

@MainActor
public final class CustomerDisplayManager {

    // MARK: - State

    private var externalWindow: UIWindow?
    private var screenObserver: NSObjectProtocol?
    private var hostingController: UIHostingController<CustomerDisplayRootView>?

    /// Callback invoked when the customer taps a tip option on the external display.
    public var onTipSelected: ((TipOption) -> Void)?

    private var currentModel: CustomerDisplayModel = .init(
        tenantName: "",
        lineItems: [],
        subtotalLabel: "$0.00",
        taxLabel: "$0.00",
        totalLabel: "$0.00"
    )

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        // Watch for new screens (USB-C/HDMI plug-in, AirPlay start)
        screenObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateExternalWindow() }
        }
        NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.teardownExternalWindow() }
        }
        // Handle already-connected screens on launch
        updateExternalWindow()
    }

    public func stop() {
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
        teardownExternalWindow()
    }

    // MARK: - Model updates

    /// Push a cart update to the customer display.
    public func update(model: CustomerDisplayModel) {
        currentModel = model
        hostingController?.rootView = CustomerDisplayRootView(model: model, onTipSelected: onTipSelected)
    }

    /// Switch to tip-prompt screen with the given options.
    public func showTipPrompt(options: [TipOption]) {
        let model = CustomerDisplayModel(
            tenantName: currentModel.tenantName,
            lineItems: currentModel.lineItems,
            subtotalLabel: currentModel.subtotalLabel,
            taxLabel: currentModel.taxLabel,
            totalLabel: currentModel.totalLabel,
            tipPromptOptions: options
        )
        update(model: model)
    }

    /// Return to cart-mirror mode (dismiss tip prompt).
    public func hideTipPrompt() {
        let model = CustomerDisplayModel(
            tenantName: currentModel.tenantName,
            lineItems: currentModel.lineItems,
            subtotalLabel: currentModel.subtotalLabel,
            taxLabel: currentModel.taxLabel,
            totalLabel: currentModel.totalLabel,
            tipPromptOptions: nil
        )
        update(model: model)
    }

    /// `true` when an external display is active.
    public var isConnected: Bool { externalWindow != nil }

    // MARK: - Private

    private func updateExternalWindow() {
        guard let externalScreen = UIScreen.screens.first(where: { $0 !== UIScreen.main }) else {
            return
        }
        if externalWindow == nil {
            let window = UIWindow(frame: externalScreen.bounds)
            window.windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.screen === externalScreen }
            let view = CustomerDisplayRootView(model: currentModel, onTipSelected: onTipSelected)
            let hc = UIHostingController(rootView: view)
            hostingController = hc
            window.rootViewController = hc
            window.isHidden = false
            externalWindow = window
            AppLog.hardware.info("CustomerDisplayManager: external display connected")
        }
    }

    private func teardownExternalWindow() {
        externalWindow?.isHidden = true
        externalWindow = nil
        hostingController = nil
        AppLog.hardware.info("CustomerDisplayManager: external display disconnected")
    }
}

// MARK: - CustomerDisplayRootView

/// Root view rendered on the external customer-facing display.
/// Not using Liquid Glass — this is content, not chrome.
public struct CustomerDisplayRootView: View {

    public let model: CustomerDisplayModel
    public let onTipSelected: ((TipOption) -> Void)?

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let options = model.tipPromptOptions {
                CustomerTipPromptView(totalLabel: model.totalLabel, options: options, onSelect: onTipSelected ?? { _ in })
            } else {
                CustomerCartMirrorView(model: model)
            }
        }
    }
}

// MARK: - CustomerCartMirrorView

private struct CustomerCartMirrorView: View {
    let model: CustomerDisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(model.tenantName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .accessibilityAddTraits(.isHeader)

            Divider().padding(.horizontal, 40).padding(.vertical, 12)

            // Line items
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.lineItems.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.name)
                                .font(.title3)
                            Spacer()
                            Text(item.quantityLabel)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(item.priceCentsLabel)
                                .font(.title3)
                                .fontWeight(.medium)
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.name), \(item.quantityLabel), \(item.priceCentsLabel)")
                    }
                }
                .padding(.horizontal, 40)
            }

            Divider().padding(.horizontal, 40).padding(.vertical, 12)

            // Totals
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Text("Subtotal")
                    Spacer()
                    Text(model.subtotalLabel)
                }
                HStack {
                    Text("Tax")
                    Spacer()
                    Text(model.taxLabel)
                }
                Divider()
                HStack {
                    Text("Total")
                        .font(.title2).fontWeight(.bold)
                    Spacer()
                    Text(model.totalLabel)
                        .font(.title2).fontWeight(.bold)
                }
            }
            .font(.title3)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Subtotal \(model.subtotalLabel), Tax \(model.taxLabel), Total \(model.totalLabel)")
        }
    }
}

// MARK: - CustomerTipPromptView

private struct CustomerTipPromptView: View {
    let totalLabel: String
    let options: [TipOption]
    let onSelect: (TipOption) -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("Add a Tip?")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Text("Total: \(totalLabel)")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: min(options.count, 3)), spacing: 20) {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        VStack(spacing: 8) {
                            Text(option.label)
                                .font(.title2).fontWeight(.bold)
                            if option.amountCents > 0 {
                                Text(formatCents(option.amountCents))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label + (option.amountCents > 0 ? ", \(formatCents(option.amountCents))" : ""))
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 60)
        }
    }

    private func formatCents(_ cents: Int) -> String {
        String(format: "$%d.%02d", cents / 100, abs(cents % 100))
    }
}
#endif
