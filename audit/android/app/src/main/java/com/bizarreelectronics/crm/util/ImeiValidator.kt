package com.bizarreelectronics.crm.util

/**
 * §4.17 IMEI validation — local-only. We do NOT talk to stolen-device /
 * carrier-blacklist providers by design; those checks are explicitly out of
 * scope for Bizarre CRM. The goal here is purely identification + device
 * autofill so staff don't re-type make/model on every intake.
 *
 *  1. [validate] runs the standard Luhn checksum against a 15-digit IMEI /
 *     IMEISV string (14 + 1 check digit).
 *  2. [lookupTacModel] takes the first 8 digits (TAC — Type Allocation
 *     Code) and looks up a local table of common devices. Returns null when
 *     the TAC is unknown; the caller then falls back to free-text entry.
 *
 * The TAC table is intentionally tiny: a full TAC database is >100 MB and
 * maintained by GSMA. Bundling a full DB is out of scope; we keep the
 * highest-volume repair-shop devices inline and let the staff hand-enter
 * anything exotic. Update lists grow via the plan §44 Device Templates
 * catalog once that ships.
 */
object ImeiValidator {

    /** Result taxonomy so the UI can show a precise inline error. */
    sealed interface Result {
        data object Ok : Result
        data object WrongLength : Result
        data object NonDigit : Result
        data object ChecksumFailed : Result
    }

    fun validate(imei: String): Result {
        val digits = imei.trim()
        if (digits.length != IMEI_LENGTH) return Result.WrongLength
        if (!digits.all { it.isDigit() }) return Result.NonDigit
        return if (luhnIsValid(digits)) Result.Ok else Result.ChecksumFailed
    }

    fun isValid(imei: String): Boolean = validate(imei) is Result.Ok

    /**
     * Lookup the TAC (first 8 digits) against a short table of common
     * repair-shop devices. Returns `"Apple iPhone 15"`-style labels.
     */
    fun lookupTacModel(imei: String): String? {
        val digits = imei.trim()
        if (digits.length < TAC_LENGTH) return null
        val tac = digits.substring(0, TAC_LENGTH)
        return TAC_TABLE[tac]
    }

    /**
     * Standard Luhn algorithm. Each digit is doubled from right-to-left on
     * alternating positions; resulting digits >=10 have their two digits
     * summed; total must be a multiple of 10.
     */
    private fun luhnIsValid(digits: String): Boolean {
        var sum = 0
        var doubleIt = false
        for (i in digits.indices.reversed()) {
            var d = digits[i].digitToInt()
            if (doubleIt) {
                d *= 2
                if (d > 9) d -= 9
            }
            sum += d
            doubleIt = !doubleIt
        }
        return sum % 10 == 0
    }

    private const val IMEI_LENGTH = 15
    private const val TAC_LENGTH = 8

    /**
     * Micro-catalog of common TAC → model labels. Intentionally narrow — the
     * goal is ~90% hit-rate on the top 50 devices brought into US repair
     * shops. The real GSMA TAC database is operator-licensed; this is just
     * a hand-maintained convenience layer so staff don't re-type `iPhone
     * 15 Pro` on every intake. Add entries as new models become common.
     */
    private val TAC_TABLE: Map<String, String> = mapOf(
        // Apple — iPhones (recent)
        "35332218" to "Apple iPhone 15 Pro",
        "35244311" to "Apple iPhone 15",
        "35378010" to "Apple iPhone 14 Pro",
        "35324210" to "Apple iPhone 14",
        "35681610" to "Apple iPhone 13 Pro",
        "35317411" to "Apple iPhone 13",
        "35308611" to "Apple iPhone 12",
        "35411011" to "Apple iPhone 11",
        "35686611" to "Apple iPhone SE (2nd gen)",
        "35693411" to "Apple iPhone XR",

        // Samsung — Galaxy S and Note
        "35290310" to "Samsung Galaxy S24 Ultra",
        "35255010" to "Samsung Galaxy S24",
        "35311810" to "Samsung Galaxy S23 Ultra",
        "35325310" to "Samsung Galaxy S23",
        "35401511" to "Samsung Galaxy S22",
        "35344310" to "Samsung Galaxy S21",
        "35436411" to "Samsung Galaxy Z Fold 5",
        "35401811" to "Samsung Galaxy Z Flip 5",
        "35298811" to "Samsung Galaxy A54",
        "35303011" to "Samsung Galaxy A34",

        // Google Pixel
        "35283911" to "Google Pixel 8 Pro",
        "35259711" to "Google Pixel 8",
        "35312011" to "Google Pixel 7a",
        "35344611" to "Google Pixel 7 Pro",
        "35386111" to "Google Pixel 7",
        "35398511" to "Google Pixel 6a",

        // OnePlus
        "86732305" to "OnePlus 12",
        "86732205" to "OnePlus 11",

        // Motorola
        "35218511" to "Motorola G Power",
        "35245111" to "Motorola Edge+",
    )
}
