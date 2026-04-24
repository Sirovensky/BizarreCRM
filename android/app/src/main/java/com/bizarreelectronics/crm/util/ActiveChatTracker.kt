package com.bizarreelectronics.crm.util

/**
 * §1.7 L245 — Tracks the phone number of the SMS thread currently visible to the user.
 *
 * SmsThreadScreen sets [currentThreadPhone] via a DisposableEffect on entry and
 * clears it on disposal. NotificationController reads this value to decide whether
 * an inbound SMS notification should use the silent dedup channel (user is already
 * looking at that thread) or the normal high-importance channel.
 *
 * This is a plain object — no DI, no Room, no flows. The value is transient and
 * only meaningful while a Compose screen is active. Thread-safety: Compose
 * recomposition dispatches on the Main thread, and FcmService reads on the IO
 * thread. The @Volatile annotation ensures visibility across threads without
 * locking (single-word write is atomic on JVM).
 */
object ActiveChatTracker {
    @Volatile
    var currentThreadPhone: String? = null
}
