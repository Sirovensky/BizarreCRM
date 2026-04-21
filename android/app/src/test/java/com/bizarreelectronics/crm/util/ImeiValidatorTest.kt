package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for the §4.17 IMEI validator. Pure-Kotlin logic so
 * runs on the JVM (no Robolectric needed).
 */
class ImeiValidatorTest {

    @Test fun `valid 15-digit IMEI passes Luhn`() {
        // 4 9 0 1 5 4 2 0 3 2 3 7 5 1 8 — known-valid sample IMEI used by the
        // GSMA test-IMEI list. Sum after Luhn = 60.
        assertEquals(ImeiValidator.Result.Ok, ImeiValidator.validate("490154203237518"))
        assertTrue(ImeiValidator.isValid("490154203237518"))
    }

    @Test fun `wrong length is rejected before Luhn runs`() {
        assertEquals(ImeiValidator.Result.WrongLength, ImeiValidator.validate(""))
        assertEquals(ImeiValidator.Result.WrongLength, ImeiValidator.validate("12345"))
        // 14 digits — common mistake when copy-pasting IMEISV without the spare digit
        assertEquals(ImeiValidator.Result.WrongLength, ImeiValidator.validate("12345678901234"))
        // 16 digits — too many.
        assertEquals(ImeiValidator.Result.WrongLength, ImeiValidator.validate("4901542032375180"))
    }

    @Test fun `non-digit characters are rejected`() {
        assertEquals(ImeiValidator.Result.NonDigit, ImeiValidator.validate("35321890563238A"))
        assertEquals(ImeiValidator.Result.NonDigit, ImeiValidator.validate("353218 056323840".take(15)))
    }

    @Test fun `Luhn checksum failure surfaces`() {
        // Take the known-valid sample, flip the last digit. Now the checksum
        // doesn't add to a multiple of 10.
        assertEquals(ImeiValidator.Result.ChecksumFailed, ImeiValidator.validate("490154203237519"))
        assertEquals(ImeiValidator.Result.ChecksumFailed, ImeiValidator.validate("123456789012345"))
    }

    @Test fun `whitespace is trimmed before validation`() {
        assertEquals(ImeiValidator.Result.Ok, ImeiValidator.validate("  490154203237518  "))
    }

    @Test fun `TAC lookup hits known device when prefix matches`() {
        // 35332218 == Apple iPhone 15 Pro per the inline table.
        val model = ImeiValidator.lookupTacModel("353322189056323")
        assertEquals("Apple iPhone 15 Pro", model)
    }

    @Test fun `TAC lookup returns null for unknown prefix`() {
        assertNull(ImeiValidator.lookupTacModel("999999991234567"))
    }

    @Test fun `TAC lookup returns null when input shorter than 8 digits`() {
        assertNull(ImeiValidator.lookupTacModel("3533221"))
    }
}
