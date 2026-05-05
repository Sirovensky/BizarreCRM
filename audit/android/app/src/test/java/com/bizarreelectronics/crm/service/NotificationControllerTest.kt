package com.bizarreelectronics.crm.service

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.core.app.RemoteInput
import com.bizarreelectronics.crm.util.ActiveChatTracker
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * §1.7 L244–245 — Unit coverage for [NotificationController] and
 * [ActiveChatTracker] dedup logic.
 *
 * Uses Robolectric so [android.app.Notification], [android.app.PendingIntent],
 * and [androidx.core.app.RemoteInput] resolve without a device.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [33])
class NotificationControllerTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication<Application>()
        ActiveChatTracker.currentThreadPhone = null
    }

    @After
    fun tearDown() {
        ActiveChatTracker.currentThreadPhone = null
    }

    // ─── handle() — basic payload parsing ────────────────────────────────────────

    @Test
    fun `handle returns non-null notification for minimal payload`() {
        val data = mapOf("type" to "ticket_assigned", "title" to "New ticket", "body" to "T-42 assigned")
        val (id, notification) = NotificationController.handle(context, data)
        assertTrue("notification id must be positive", id > 0)
        assertNotNull("notification must not be null", notification)
    }

    @Test
    fun `handle returns notification for completely empty data map`() {
        val (id, notification) = NotificationController.handle(context, emptyMap())
        assertTrue(id > 0)
        assertNotNull(notification)
    }

    @Test
    fun `handle increments id on successive calls`() {
        val (id1, _) = NotificationController.handle(context, mapOf("type" to "system"))
        val (id2, _) = NotificationController.handle(context, mapOf("type" to "system"))
        assertTrue("ids must be monotonically increasing", id2 > id1)
    }

    // ─── SMS dedup — ActiveChatTracker ───────────────────────────────────────────

    @Test
    fun `sms_inbound uses sms_inbound channel when no thread is active`() {
        ActiveChatTracker.currentThreadPhone = null
        val data = mapOf(
            "type" to "sms_inbound",
            "thread_phone" to "+15550001234",
            "title" to "SMS",
            "body" to "Hi",
        )
        val (_, notification) = NotificationController.handle(context, data)
        // Channel ID is embedded in the Notification object.
        assertEquals("sms_inbound", notification.channelId)
    }

    @Test
    fun `sms_inbound uses sms_silent channel when thread is currently open`() {
        ActiveChatTracker.currentThreadPhone = "+15550001234"
        val data = mapOf(
            "type" to "sms_inbound",
            "thread_phone" to "+15550001234",
            "title" to "SMS",
            "body" to "Hi",
        )
        val (_, notification) = NotificationController.handle(context, data)
        assertEquals("sms_silent", notification.channelId)
    }

    @Test
    fun `sms_inbound uses normal channel when different thread is open`() {
        ActiveChatTracker.currentThreadPhone = "+15559999999"
        val data = mapOf(
            "type" to "sms_inbound",
            "thread_phone" to "+15550001234",
            "title" to "SMS",
            "body" to "Hi",
        )
        val (_, notification) = NotificationController.handle(context, data)
        assertEquals("sms_inbound", notification.channelId)
    }

    // ─── ActiveChatTracker standalone ────────────────────────────────────────────

    @Test
    fun `ActiveChatTracker starts null`() {
        assertNull(ActiveChatTracker.currentThreadPhone)
    }

    @Test
    fun `ActiveChatTracker stores and clears phone`() {
        ActiveChatTracker.currentThreadPhone = "+15550001111"
        assertEquals("+15550001111", ActiveChatTracker.currentThreadPhone)
        ActiveChatTracker.currentThreadPhone = null
        assertNull(ActiveChatTracker.currentThreadPhone)
    }

    // ─── RemoteInput extraction (receiver logic) ─────────────────────────────────

    @Test
    fun `RemoteInput getResultsFromIntent returns null for plain intent without results`() {
        val intent = Intent(NotificationController.ACTION_REPLY_SMS)
        val bundle = RemoteInput.getResultsFromIntent(intent)
        // No results added — must be null (not crash).
        assertNull(bundle)
    }

    @Test
    fun `RemoteInput extraction returns text from filled bundle`() {
        // Simulate what the system does when the user submits a direct-reply.
        val bundle = Bundle().apply {
            putCharSequence(NotificationController.EXTRA_REPLY_TEXT, "Hello world")
        }
        val intent = Intent(NotificationController.ACTION_REPLY_SMS)
        RemoteInput.addResultsToIntent(
            arrayOf(RemoteInput.Builder(NotificationController.EXTRA_REPLY_TEXT).build()),
            intent,
            bundle,
        )
        val results = RemoteInput.getResultsFromIntent(intent)
        assertNotNull("results bundle must not be null", results)
        val text = results!!.getCharSequence(NotificationController.EXTRA_REPLY_TEXT)?.toString()
        assertEquals("Hello world", text)
    }

    @Test
    fun `RemoteInput extraction returns null for blank text`() {
        val bundle = Bundle().apply {
            putCharSequence(NotificationController.EXTRA_REPLY_TEXT, "   ")
        }
        val intent = Intent(NotificationController.ACTION_REPLY_SMS)
        RemoteInput.addResultsToIntent(
            arrayOf(RemoteInput.Builder(NotificationController.EXTRA_REPLY_TEXT).build()),
            intent,
            bundle,
        )
        val results = RemoteInput.getResultsFromIntent(intent)
        val text = results?.getCharSequence(NotificationController.EXTRA_REPLY_TEXT)?.toString()?.trim()
        // Blank text should be treated as empty — receiver guards against this.
        assertTrue("blank reply text should be blank after trim", text.isNullOrBlank())
    }

    // ─── Malformed / missing extras ──────────────────────────────────────────────

    @Test
    fun `handle survives missing title and body`() {
        val data = mapOf("type" to "sms_inbound", "thread_phone" to "+15550001234")
        val (id, notification) = NotificationController.handle(context, data)
        assertTrue(id > 0)
        assertNotNull(notification)
    }

    @Test
    fun `handle survives null-ish entity_id`() {
        val data = mapOf("type" to "ticket_assigned", "entity_id" to "", "entity_type" to "ticket")
        val (id, notification) = NotificationController.handle(context, data)
        assertTrue(id > 0)
        assertNotNull(notification)
    }

    @Test
    fun `handle unknown type falls through to sync channel`() {
        val data = mapOf("type" to "totally_unknown_event", "title" to "Test", "body" to "Body")
        val (_, notification) = NotificationController.handle(context, data)
        assertEquals("sync", notification.channelId)
    }
}
