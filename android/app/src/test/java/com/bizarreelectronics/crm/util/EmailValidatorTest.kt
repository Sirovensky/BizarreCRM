package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * §31.1 — unit coverage for the pragmatic email-address validator.
 */
class EmailValidatorTest {

    @Test fun `blank inputs classify as Empty`() {
        assertEquals(EmailValidator.Result.Empty, EmailValidator.validate(null))
        assertEquals(EmailValidator.Result.Empty, EmailValidator.validate(""))
        assertEquals(EmailValidator.Result.Empty, EmailValidator.validate("   "))
    }

    @Test fun `well-formed addresses pass`() {
        assertTrue(EmailValidator.isValid("user@example.com"))
        assertTrue(EmailValidator.isValid("first.last@example.co.uk"))
        assertTrue(EmailValidator.isValid("first+tag@example.com"))
        assertTrue(EmailValidator.isValid("user_name@sub.domain.example.com"))
        assertTrue(EmailValidator.isValid("u@a.bc"))
    }

    @Test fun `case-insensitive match`() {
        assertTrue(EmailValidator.isValid("User@EXAMPLE.COM"))
        assertTrue(EmailValidator.isValid("User@Example.Com"))
    }

    @Test fun `trims surrounding whitespace`() {
        assertEquals(EmailValidator.Result.Ok, EmailValidator.validate("  user@example.com  "))
    }

    @Test fun `missing at sign fails`() {
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("userexample.com"))
    }

    @Test fun `missing dot in domain fails`() {
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("user@example"))
    }

    @Test fun `TLD too short fails`() {
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("user@example.c"))
    }

    @Test fun `internal whitespace fails`() {
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("user name@example.com"))
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("user@exam ple.com"))
    }

    @Test fun `double at sign fails`() {
        assertEquals(EmailValidator.Result.Malformed, EmailValidator.validate("user@@example.com"))
    }

    @Test fun `special chars in local part that are not in allow-list fail`() {
        // Comma, semicolon, parens are not permitted by this pragmatic regex.
        assertFalse(EmailValidator.isValid("user,name@example.com"))
        assertFalse(EmailValidator.isValid("(user)@example.com"))
    }
}
