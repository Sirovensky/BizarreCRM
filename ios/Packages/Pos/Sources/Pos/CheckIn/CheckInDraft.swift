/// CheckInDraft.swift — §16.25
///
/// Shared mutable model for the 6-step repair check-in wizard.
/// Passed through SwiftUI environment. All mutations create new value-copies
/// per immutability rule (arrays replaced, not mutated in place).
///
/// API mapping:
///   PATCH /api/v1/tickets/:id  — autosave on every step navigation.
///   POST  /api/v1/tickets/:id/signatures — step 6 signature upload.

import Foundation
import Observation

// MARK: - Supporting types

public struct DamageMarker: Identifiable, Sendable, Equatable {
    public enum MarkerType: String, CaseIterable, Sendable { case crack, scratch, dent, stain }
    public enum Face: String, CaseIterable, Sendable { case front, back, sides }

    public let id: UUID
    public var x: Double     // normalized [0,1]
    public var y: Double     // normalized [0,1]
    public var type: MarkerType
    public var face: Face
    public var note: String?

    public init(id: UUID = UUID(), x: Double, y: Double, type: MarkerType, face: Face, note: String? = nil) {
        self.id = id; self.x = x; self.y = y; self.type = type; self.face = face; self.note = note
    }
}

public struct DiagnosticResult: Identifiable, Sendable, Equatable {
    public enum State: String, CaseIterable, Sendable { case ok, fail, untested }
    public let id: String     // item name as stable key
    public let displayName: String
    public var state: State

    public init(id: String, displayName: String, state: State = .untested) {
        self.id = id; self.displayName = displayName; self.state = state
    }
}

public enum OverallCondition: String, CaseIterable, Sendable { case mint, good, fair, poor, salvage }

public enum LDIStatus: String, CaseIterable, Sendable { case notTested = "Not tested", clean = "Clean", tripped = "Tripped" }

public enum DepositPreset: CaseIterable, Sendable, Equatable {
    case zero, twentyFive, fifty, oneHundred, full

    public var label: String {
        switch self {
        case .zero: return "$0"
        case .twentyFive: return "$25"
        case .fifty: return "$50"
        case .oneHundred: return "$100"
        case .full: return "Full"
        }
    }

    public func amountCents(for total: Int) -> Int {
        switch self {
        case .zero: return 0
        case .twentyFive: return 2500
        case .fifty: return 5000
        case .oneHundred: return 10000
        case .full: return total
        }
    }
}

// MARK: - CheckInDraft

/// §16.25 — Shared draft model for all 6 wizard steps.
@MainActor
@Observable
public final class CheckInDraft {

    // MARK: - Ticket metadata
    public var ticketId: Int64?
    public var customerId: Int64?

    // MARK: - Step 1: Symptoms
    public var symptoms: [String] = []
    public var symptomOtherText: String = ""

    // MARK: - Step 2: Details
    public var diagnosticNotes: String = ""
    public var internalNotes: String = ""
    public var passcodeType: PasscodeType = .none
    public var passcode: String = ""
    public var photoPaths: [String] = []

    public enum PasscodeType: String, CaseIterable, Sendable {
        case none = "None"
        case pin4 = "4-digit PIN"
        case pin6 = "6-digit PIN"
        case alphanumeric = "Alphanumeric"
        case pattern = "Pattern"
    }

    // MARK: - Step 3: Damage
    public var damageMarkers: [DamageMarker] = []
    public var overallCondition: OverallCondition = .good
    public var accessories: [String] = []
    public var ldiStatus: LDIStatus = .notTested

    // MARK: - Step 4: Diagnostic
    public var diagnosticResults: [DiagnosticResult] = CheckInDraft.defaultDiagnosticItems()

    private static func defaultDiagnosticItems() -> [DiagnosticResult] {
        [
            .init(id: "power",      displayName: "Power on"),
            .init(id: "touchscreen", displayName: "Touchscreen"),
            .init(id: "faceID",     displayName: "Face ID"),
            .init(id: "touchID",    displayName: "Touch ID"),
            .init(id: "earpiece",   displayName: "Speakers — earpiece"),
            .init(id: "loudSpeaker",displayName: "Speakers — loudspeaker"),
            .init(id: "frontCam",   displayName: "Camera — front"),
            .init(id: "rearCam",    displayName: "Camera — rear"),
            .init(id: "wifi",       displayName: "Wi-Fi + Bluetooth"),
            .init(id: "cellular",   displayName: "Cellular"),
            .init(id: "sim",        displayName: "SIM"),
            .init(id: "battery",    displayName: "Battery health"),
        ]
    }

    // MARK: - Step 5: Quote / parts
    public var selectedPartIds: [Int64] = []
    public var depositPreset: DepositPreset = .zero
    public var laborCents: Int = 0
    public var partsCents: Int = 0

    public var subtotalCents: Int { laborCents + partsCents }
    public var depositCents: Int { depositPreset.amountCents(for: subtotalCents) }

    // MARK: - Step 6: Sign
    public var agreedToTerms: Bool = false
    public var consentToBackup: Bool = false
    public var authorizedDeposit: Bool = false
    public var optInToSMSUpdates: Bool = false
    public var signaturePNGBase64: String? = nil

    public var canSign: Bool { agreedToTerms && consentToBackup && authorizedDeposit }
    public var signatureAttached: Bool { signaturePNGBase64 != nil }

    public init() {}

    // MARK: - Symptom helpers

    public func toggleSymptom(_ symptom: String) {
        if symptoms.contains(symptom) {
            symptoms = symptoms.filter { $0 != symptom }
        } else {
            symptoms = symptoms + [symptom]
        }
    }

    // MARK: - Diagnostic helpers

    public func setDiagnosticState(id: String, state: DiagnosticResult.State) {
        diagnosticResults = diagnosticResults.map { item in
            guard item.id == id else { return item }
            var updated = item; updated.state = state; return updated
        }
    }

    public func setAllDiagnosticOK() {
        diagnosticResults = diagnosticResults.map {
            DiagnosticResult(id: $0.id, displayName: $0.displayName, state: .ok)
        }
    }
}
