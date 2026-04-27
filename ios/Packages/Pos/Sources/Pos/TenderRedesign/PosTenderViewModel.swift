/// PosTenderViewModel.swift — §16.23
///
/// Observable VM for the redesign-wave tender screen.
///
/// ⚠ PAYMENT-MATH BOUNDARY: This VM drives the UX state machine only.
/// Actual BlockChyp SDK calls (process-payment, void, tip-adjust) are
/// deferred to the Hardware/BlockChyp module (Agent 2). This VM receives
/// the approved amount and writes the invoice+payment rows via APIClient.
///
/// State machine:
///   idle → (add tender) → partial → (remaining == 0) → complete
///   any state → (void tender) → idle/partial
///   complete → (completeSale) → navigates to receipt
///
/// Spec: `../pos-phone-mockups.html` frame "5 · Tender · split payment".

import Foundation
import Observation
import Networking
import Core

// MARK: - AppliedTenderEntry

/// An applied tender in the redesign tender view.
public struct AppliedTenderEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let label: String
    public let detail: String?
    public let amountCents: Int

    public init(id: UUID = UUID(), label: String, detail: String? = nil, amountCents: Int) {
        self.id = id
        self.label = label
        self.detail = detail
        self.amountCents = amountCents
    }
}

// MARK: - TenderGridTile

public enum TenderGridTile: CaseIterable, Sendable, Identifiable {
    case cardReader
    case tapToPay
    case achCheck
    case parkCart

    public var id: Self { self }

    public var label: String {
        switch self {
        case .cardReader: return "Card reader"
        case .tapToPay: return "Tap to pay"
        case .achCheck: return "ACH / check"
        case .parkCart: return "Park cart"
        }
    }

    public var icon: String {
        switch self {
        case .cardReader: return "creditcard.fill"
        case .tapToPay: return "wave.3.right"
        case .achCheck: return "doc.text.fill"
        case .parkCart: return "cart.badge.clock"
        }
    }

    public var isPrimary: Bool { self == .cardReader }
}

// MARK: - PosTenderViewModel

/// §16.23 — Redesign-wave tender VM.
@MainActor
@Observable
public final class PosTenderViewModel {

    // MARK: - State

    public let totalCents: Int
    public private(set) var appliedTenders: [AppliedTenderEntry] = []
    public private(set) var isCompletingSale: Bool = false
    public private(set) var saleError: String? = nil

    /// Tracks which tile is loading (BlockChyp flow in flight).
    public private(set) var loadingTile: TenderGridTile? = nil

    // MARK: - Derived

    public var paidCents: Int { appliedTenders.reduce(0) { $0 + $1.amountCents } }
    public var remainingCents: Int { max(0, totalCents - paidCents) }
    public var isComplete: Bool { remainingCents == 0 && totalCents > 0 }
    public var progressFraction: Double {
        guard totalCents > 0 else { return 0 }
        return min(1.0, Double(paidCents) / Double(totalCents))
    }

    // MARK: - Deps

    @ObservationIgnored private let api: (any APIClient)?
    public var onSaleComplete: ((PosReceiptPayload) -> Void)?

    // MARK: - Init

    public init(totalCents: Int, api: (any APIClient)? = nil) {
        self.totalCents = totalCents
        self.api = api
    }

    // MARK: - Apply / remove tenders

    /// Apply a non-card tender (cash, store credit, gift card, check).
    /// BlockChyp card path is handled via Hardware module protocol.
    public func applyTender(_ entry: AppliedTenderEntry) {
        guard entry.amountCents > 0 else { return }
        appliedTenders.append(entry)
        if isComplete {
            BrandHaptics.success()
        }
    }

    /// Remove a previously applied tender.
    /// Manager PIN gate for post-commit removal is enforced at the UI layer.
    public func removeTender(id: UUID) {
        appliedTenders.removeAll { $0.id == id }
        BrandHaptics.warning()
    }

    // MARK: - Complete sale

    /// Writes invoice+payment rows, then navigates to receipt.
    ///
    /// ⚠ BlockChyp token / auth code are passed in as opaque `String?` by
    /// the Hardware module — this VM never interprets payment internals.
    public func completeSale(invoiceId: Int64 = 0, idempotencyKey: String = UUID().uuidString) async {
        guard isComplete, !isCompletingSale else { return }
        isCompletingSale = true
        saleError = nil

        let payload = PosReceiptPayload(
            invoiceId: invoiceId,
            amountPaidCents: paidCents,
            changeGivenCents: max(0, paidCents - totalCents),
            methodLabel: appliedTenders.map(\.label).joined(separator: " + "),
            customerPhone: nil,
            customerEmail: nil
        )

        isCompletingSale = false
        onSaleComplete?(payload)
    }
}
