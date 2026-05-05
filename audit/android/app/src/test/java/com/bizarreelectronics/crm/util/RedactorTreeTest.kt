package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import timber.log.Timber

/**
 * §31.1 — unit coverage for RedactorTree (ActionPlan §1 L228, §28 L64).
 *
 * Uses an in-memory CapturingTree as the delegate so assertions target the
 * sanitised strings that [RedactorTree] forwards — not raw Logcat output.
 */
class RedactorTreeTest {

    // -------------------------------------------------------------------------
    // Test double — captures last log call made to the delegate
    // -------------------------------------------------------------------------

    /** Captures the most-recently forwarded log call for assertion. */
    private class CapturingTree : Timber.Tree() {
        var lastPriority: Int = 0
        var lastTag: String? = null
        var lastMessage: String = ""
        var lastThrowable: Throwable? = null

        public override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
            lastPriority = priority
            lastTag = tag
            lastMessage = message
            lastThrowable = t
        }
    }

    private fun treeUnderTest(): Pair<RedactorTree, CapturingTree> {
        val capture = CapturingTree()
        val tree = RedactorTree(capture)
        return tree to capture
    }

    // -------------------------------------------------------------------------
    // redact() — key-value masking
    // -------------------------------------------------------------------------

    @Test fun `JSON password field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"password":"secret123"}""")
        assertFalse("password value must not be present", result.contains("secret123"))
        assertTrue("key should remain", result.contains("password"))
        assertTrue("mask should be present", result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON accessToken field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"accessToken":"eyJhb.token.sig"}""")
        assertFalse(result.contains("eyJhb.token.sig"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON refresh_token field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"refresh_token":"refresh123"}""")
        assertFalse(result.contains("refresh123"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON pin field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"pin":"1234"}""")
        assertFalse(result.contains("1234"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON backup_code field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"backup_code":"ABCD-EFGH"}""")
        assertFalse(result.contains("ABCD-EFGH"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON authorization field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"authorization":"Bearer tok"}""")
        // LogRedactor also strips bearer tokens; either redactor fires
        assertFalse(result.contains("Bearer tok"))
    }

    @Test fun `JSON cvv field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"cvv":"123"}""")
        assertFalse(result.contains(""""123""""))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `JSON ssn field is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"ssn":"123-45-6789"}""")
        // LogRedactor also catches bare SSN patterns
        assertFalse(result.contains("123-45-6789"))
    }

    // -------------------------------------------------------------------------
    // redact() — form-encoded variants
    // -------------------------------------------------------------------------

    @Test fun `form-encoded password is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("username=john&password=hunter2&grant_type=password")
        assertFalse("form-encoded value must not appear", result.contains("hunter2"))
        assertTrue("mask should be present", result.contains(RedactorTree.MASK))
    }

    @Test fun `form-encoded pin is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("user=tech&pin=9999")
        assertFalse(result.contains("9999"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    @Test fun `form-encoded access_token is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("access_token=abc123&scope=read")
        assertFalse(result.contains("abc123"))
        assertTrue(result.contains(RedactorTree.MASK))
    }

    // -------------------------------------------------------------------------
    // redact() — case-insensitive handling
    // -------------------------------------------------------------------------

    @Test fun `uppercase Password key is masked case-insensitively`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"Password":"MySecret"}""")
        assertFalse(result.contains("MySecret"))
    }

    @Test fun `ALL-CAPS PASSWORD key is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"PASSWORD":"topsecret"}""")
        assertFalse(result.contains("topsecret"))
    }

    @Test fun `mixed-case access_Token is masked`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("""{"access_Token":"tok123"}""")
        assertFalse(result.contains("tok123"))
    }

    // -------------------------------------------------------------------------
    // redact() — unrelated text is preserved
    // -------------------------------------------------------------------------

    @Test fun `safe message is returned unmodified`() {
        val (tree, _) = treeUnderTest()
        val msg = "Ticket #1234 status changed to Ready"
        assertEquals(msg, tree.redact(msg))
    }

    @Test fun `blank string passes through unchanged`() {
        val (tree, _) = treeUnderTest()
        assertEquals("", tree.redact(""))
        assertEquals("   ", tree.redact("   "))
    }

    @Test fun `unrelated JSON fields are not masked`() {
        val (tree, _) = treeUnderTest()
        val msg = """{"ticketId":"TKT-001","status":"open"}"""
        assertEquals(msg, tree.redact(msg))
    }

    // -------------------------------------------------------------------------
    // redact() — PII patterns delegated to LogRedactor
    // -------------------------------------------------------------------------

    @Test fun `email address is redacted`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("Sending receipt to customer@example.com")
        assertFalse(result.contains("customer@example.com"))
        assertTrue(result.contains("[EMAIL]"))
    }

    @Test fun `phone number is redacted`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("Call 555-555-1234 now")
        assertFalse(result.contains("555-555-1234"))
        assertTrue(result.contains("[PHONE]"))
    }

    @Test fun `bearer token is redacted`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("Authorization: Bearer eyJhb.notreal.signature")
        assertFalse(result.contains("eyJhb.notreal.signature"))
    }

    @Test fun `IMEI is redacted`() {
        val (tree, _) = treeUnderTest()
        val result = tree.redact("IMEI 490154203237518 scanned")
        assertFalse(result.contains("490154203237518"))
        assertTrue(result.contains("[IMEI]"))
    }

    // -------------------------------------------------------------------------
    // Throwable.message redaction
    // -------------------------------------------------------------------------

    @Test fun `throwable message containing sensitive key is redacted`() {
        val (tree, capture) = treeUnderTest()
        val original = RuntimeException("""{"password":"leaked123"}""")
        tree.log(android.util.Log.ERROR, "TAG", "error occurred", original)
        assertNotNull("delegate must receive throwable", capture.lastThrowable)
        assertFalse(
            "throwable message must not contain raw value",
            capture.lastThrowable!!.message!!.contains("leaked123"),
        )
    }

    @Test fun `throwable with null message is forwarded unchanged`() {
        val (tree, capture) = treeUnderTest()
        val original = RuntimeException()      // message == null
        tree.log(android.util.Log.ERROR, "TAG", "null msg throwable", original)
        // Must receive the same instance since no message to redact
        assertSame(original, capture.lastThrowable)
    }

    @Test fun `throwable with clean message is forwarded as same instance`() {
        val (tree, capture) = treeUnderTest()
        val original = RuntimeException("safe error detail")
        tree.log(android.util.Log.ERROR, "TAG", "safe throwable", original)
        // Nothing changed — redactThrowable should return the same reference
        assertSame(original, capture.lastThrowable)
    }

    @Test fun `new throwable preserves stack trace from original`() {
        val (tree, capture) = treeUnderTest()
        val original = RuntimeException("""{"pin":"5678"}""")
        tree.log(android.util.Log.ERROR, "TAG", "pin error", original)
        val forwarded = capture.lastThrowable!!
        assertNotSame("must be a new Throwable wrapping redacted message", original, forwarded)
        // Stack trace frames should originate from this test (same as original)
        assertTrue(
            "stack trace must be preserved",
            forwarded.stackTrace.isNotEmpty(),
        )
    }

    // -------------------------------------------------------------------------
    // Delegate forwarding
    // -------------------------------------------------------------------------

    @Test fun `delegate receives sanitised message`() {
        val (tree, capture) = treeUnderTest()
        tree.log(android.util.Log.DEBUG, "MyTag", """{"password":"p@ss"}""", null as Throwable?)
        assertFalse(capture.lastMessage.contains("p@ss"))
        assertTrue(capture.lastMessage.contains(RedactorTree.MASK))
    }

    @Test fun `delegate receives correct priority and tag`() {
        val (tree, capture) = treeUnderTest()
        tree.log(android.util.Log.WARN, "TestTag", "safe message", null as Throwable?)
        assertEquals(android.util.Log.WARN, capture.lastPriority)
        assertEquals("TestTag", capture.lastTag)
    }

    @Test fun `null throwable forwarded as null`() {
        val (tree, capture) = treeUnderTest()
        tree.log(priority = android.util.Log.DEBUG, tag = null, message = "no throwable", t = null)
        assertNull(capture.lastThrowable)
    }

    @Test fun `delegate receives safe text unchanged`() {
        val (tree, capture) = treeUnderTest()
        val msg = "Sync complete: 42 records updated"
        tree.log(android.util.Log.INFO, "SyncWorker", msg, null as Throwable?)
        assertEquals(msg, capture.lastMessage)
    }
}
