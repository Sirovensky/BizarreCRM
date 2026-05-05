package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * §31.1 — unit coverage for the §28.6 / §32.6 PII redactor.
 */
class LogRedactorTest {

    @Test fun `blank input returns unchanged`() {
        assertEquals("", LogRedactor.redact(""))
        assertEquals("   ", LogRedactor.redact("   "))
    }

    @Test fun `bearer token replaced`() {
        val out = LogRedactor.redact("Authorization: Bearer eyJhb.notreal.signature")
        assertFalse("Bearer payload must be stripped", out.contains("eyJhb"))
        assertEquals("Authorization: Bearer [REDACTED]", out)
    }

    @Test fun `jwt-style tokens replaced`() {
        val jwt = "aaaaaaaaaaaa.bbbbbbbbbbbb.cccccccccccc"
        val out = LogRedactor.redact("token=$jwt")
        assertEquals("token=[JWT]", out)
    }

    @Test fun `card number keeps last 4 digits only`() {
        val out = LogRedactor.redact("card 4242 4242 4242 4242 declined")
        assertEquals("card ****-****-****-4242 declined", out)
    }

    @Test fun `ssn replaced`() {
        val out = LogRedactor.redact("customer 123-45-6789 on file")
        assertEquals("customer [SSN] on file", out)
        val alt = LogRedactor.redact("alt 123456789 form")
        assertEquals("alt [SSN] form", alt)
    }

    @Test fun `imei replaced as 15 digits`() {
        val out = LogRedactor.redact("IMEI 490154203237518 sent")
        assertEquals("IMEI [IMEI] sent", out)
    }

    @Test fun `phone replaced`() {
        assertEquals("call [PHONE] now", LogRedactor.redact("call (555) 555-1234 now"))
        // Leading "+1 " country code is preserved outside the phone body
        // because the regex starts at the first digit group; the 10-digit
        // body is still masked, which is the PII-protection intent.
        assertEquals("call +1 [PHONE]", LogRedactor.redact("call +1 555-555-1234"))
        assertEquals("call [PHONE]", LogRedactor.redact("call 5555551234"))
    }

    @Test fun `email replaced`() {
        assertEquals("to [EMAIL] re: ticket", LogRedactor.redact("to user@example.com re: ticket"))
    }

    @Test fun `imei takes priority over phone for 15-digit strings`() {
        // Runs IMEI before PHONE so 15-digit IMEIs are not mis-classified.
        assertEquals("ctx [IMEI] end", LogRedactor.redact("ctx 490154203237518 end"))
    }

    @Test fun `multiple patterns in one string all replaced`() {
        val out = LogRedactor.redact(
            "order phone 555-555-1234 email foo@bar.com token Bearer abc.def.ghi",
        )
        assertFalse(out.contains("555-555-1234"))
        assertFalse(out.contains("foo@bar.com"))
        assertFalse(out.contains("abc.def.ghi"))
    }
}
