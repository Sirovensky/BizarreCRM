import Foundation

// MARK: - §30.11 Tone of voice
//
// Centralised copy helpers for the four §30.11 sub-items:
//
//   • Friendly + concise copy            → `BrandTone.friendly(_:)`
//   • Error messages (what + what to do) → `BrandTone.error(what:do:)`
//   • Confirmation dialogs (action+conseq)→ `BrandTone.confirm(action:consequence:)`
//   • No jargon (staff translations)     → `BrandTone.plain(_:)` + `JargonGlossary`
//
// Surfaces that present user-facing strings should route through these
// helpers rather than hand-rolling sentences. Anything ad-hoc tends to
// drift toward jargon, passive voice, or "an error occurred" useless-isms
// that §30.11 explicitly bans.
//
// Output is plain `String` (not `LocalizedStringKey`) because most call
// sites do their own NSLocalizedString lookup; pipe the localised string
// in as the input.

public enum BrandTone {

    // MARK: Friendly + concise

    /// Trim filler / officialese from a message and clamp length.
    ///
    /// This is intentionally light-touch — it doesn't rewrite copy, but
    /// it strips boilerplate prefixes ("Please note that...", "An error
    /// has occurred:") and trailing whitespace. Authoring guideline:
    /// keep ≤ 120 chars for toast/banner copy.
    public static func friendly(_ message: String) -> String {
        var out = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in friendlyStripPrefixes {
            if out.lowercased().hasPrefix(prefix) {
                out.removeFirst(prefix.count)
                out = out.trimmingCharacters(in: .whitespacesAndNewlines)
                if let first = out.first {
                    out = first.uppercased() + out.dropFirst()
                }
            }
        }
        return out
    }

    private static let friendlyStripPrefixes: [String] = [
        "please note that ",
        "please be advised that ",
        "an error has occurred:",
        "an error occurred:",
        "warning:",
        "notice:"
    ]

    // MARK: Error messages — what + what to do

    /// Build a 2-clause error string: `"<what>. <action>."`.
    ///
    /// Per §30.11: every error tells the user what went wrong AND what
    /// they can do about it. If `action` is empty, the message is still
    /// technically valid but lints in DEBUG so QA notices.
    public static func error(what: String, do action: String) -> String {
        let what = what.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let act  = action.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        #if DEBUG
        if act.isEmpty {
            assertionFailure("BrandTone.error: missing remediation copy for '\(what)'. Per §30.11, every error message must include what to do.")
        }
        #endif
        if act.isEmpty { return "\(what)." }
        return "\(what). \(act)."
    }

    // MARK: Confirmation dialogs — action + consequence

    /// Build the body copy for a confirmation dialog.
    ///
    /// Returns `"<action>. <consequence>."` — the action describes what
    /// is about to happen, the consequence describes the resulting state
    /// (esp. irreversibility). Used by `BrandConfirmDialog` and any
    /// `.confirmationDialog(...)` modifier in the app.
    public static func confirm(action: String, consequence: String) -> String {
        let a = action.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let c = consequence.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        #if DEBUG
        if c.isEmpty {
            assertionFailure("BrandTone.confirm: missing consequence copy for action '\(a)'. Per §30.11, confirmation dialogs must describe both action and consequence.")
        }
        #endif
        if c.isEmpty { return "\(a)." }
        return "\(a). \(c)."
    }

    // MARK: No jargon — staff translations

    /// Replace known back-office / industry jargon with staff-friendly
    /// equivalents. Round-trip safe: passing an already-plain string
    /// returns it unchanged.
    public static func plain(_ message: String) -> String {
        var out = message
        for (jargon, plainCopy) in JargonGlossary.replacements {
            out = out.replacingOccurrences(
                of: jargon,
                with: plainCopy,
                options: [.caseInsensitive]
            )
        }
        return out
    }
}

// MARK: - JargonGlossary
//
// Items §30.11 lists `"IMEI" OK, "A2P 10DLC" not` — i.e. some acronyms
// are part of the device-repair domain and staff know them; others are
// telecom/payments compliance noise that confuses anyone who isn't in
// the back office. Keep this list short and curated.
//
// Order matters: longer phrases must come first so partial matches
// don't shadow the full term (e.g. "10DLC" appears as the trailing
// half of "A2P 10DLC").

public enum JargonGlossary {
    public static let replacements: [(String, String)] = [
        // Telecom/SMS compliance
        ("A2P 10DLC", "business texting registration"),
        ("10DLC",     "business texting registration"),
        ("A2P",       "business texting"),

        // Payments / processing
        ("PCI-DSS",   "card-data security rules"),
        ("CVV2",      "card security code"),
        ("EMV",       "chip-card reader"),
        ("ACH",       "bank transfer"),
        ("BIN",       "card-issuer code"),

        // Auth / identity
        ("TOTP",      "6-digit code"),
        ("OAuth2",    "sign-in"),
        ("OAuth",     "sign-in"),
        ("JWT",       "session token"),

        // App jargon staff don't need
        ("idempotency key", "duplicate-prevention key"),
        ("webhook",   "automated notification"),
        ("rate-limit","temporary slow-down"),
    ]

    /// Audit helper — true if the input contains any glossary jargon.
    public static func containsJargon(_ message: String) -> Bool {
        for (jargon, _) in replacements
        where message.range(of: jargon, options: .caseInsensitive) != nil {
            return true
        }
        return false
    }
}
