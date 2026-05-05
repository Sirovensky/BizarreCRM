package com.bizarreelectronics.crm.data.training

/**
 * §53 Training Mode — data-source abstraction.
 *
 * When training mode is enabled, every ViewModel that fetches or mutates data
 * should delegate to a [TrainingDataSource] implementation instead of hitting
 * the real Retrofit API.  This keeps all canned-data logic in one place and
 * lets production code paths stay unmodified.
 *
 * ## Usage contract
 * 1. Inject [TrainingDataSource] alongside your real API interface.
 * 2. Check [com.bizarreelectronics.crm.data.local.prefs.TrainingPreferences.trainingModeEnabled]
 *    (or collect [trainingModeEnabledFlow]) at the ViewModel layer.
 * 3. When true, call [TrainingDataSource] methods instead of real API methods.
 * 4. All write operations (create ticket, send SMS, etc.) are silently
 *    discarded by the fake — nothing reaches the server (§53.4 no-send guard).
 *
 * ## Seeded data (§53.2)
 * [FakeTrainingDataSource] pre-populates canned demo customers, tickets,
 * inventory items, and SMS threads.  Test BlockChyp card numbers are
 * exposed via [testBlockChypCardNumbers].  The data is reset in-memory
 * when [reset] is called.
 */
interface TrainingDataSource {

    // -------------------------------------------------------------------------
    // §53.2 — Seeded demo data
    // -------------------------------------------------------------------------

    /** Returns a list of canned demo customer summaries for list screens. */
    fun getDemoCustomers(): List<TrainingCustomer>

    /** Returns a list of canned demo tickets for list screens. */
    fun getDemoTickets(): List<TrainingTicket>

    /** Returns a list of canned demo inventory items for list screens. */
    fun getDemoInventoryItems(): List<TrainingInventoryItem>

    /** Returns a list of canned demo SMS threads for the messages screen. */
    fun getDemoSmsThreads(): List<TrainingSmsThread>

    /**
     * §53.2 — Test BlockChyp card numbers for the POS tender flow.
     *
     * These numbers are accepted by the BlockChyp sandbox terminal and can be
     * used during training mode to simulate approved / declined transactions
     * without touching the live payment network.
     */
    val testBlockChypCardNumbers: List<TestCard>

    // -------------------------------------------------------------------------
    // §53.4 — No-send guards
    // -------------------------------------------------------------------------

    /**
     * §53.4 — Intercept an outbound SMS send.
     *
     * Instead of calling the real SMS API, this method logs the intercepted
     * message to the training log and returns `true` to indicate the send
     * was "handled" (i.e. swallowed).
     *
     * @param to      Recipient phone number.
     * @param body    Message body.
     * @return true  — caller should treat send as successful; nothing was sent.
     */
    fun interceptSmsSend(to: String, body: String): Boolean

    /**
     * §53.4 — Intercept an outbound email send.
     *
     * Same pattern as [interceptSmsSend]: logs locally, never calls the
     * real email API.
     *
     * @param to      Recipient email address.
     * @param subject Email subject line.
     * @param body    Email body (plain text or HTML).
     * @return true  — caller should treat send as successful; nothing was sent.
     */
    fun interceptEmailSend(to: String, subject: String, body: String): Boolean

    /**
     * §53.4 — Read-only log of intercepted outbound sends during this session.
     * Shown on the Training Mode screen so staff can confirm sends were blocked.
     */
    fun getInterceptedSendLog(): List<InterceptedSend>

    // -------------------------------------------------------------------------
    // §53.3 — Reset
    // -------------------------------------------------------------------------

    /**
     * §53.3 — Reset all in-memory training state.
     *
     * Called when the user taps "Reset training data" on [TrainingModeScreen].
     * Restores seeded demo data to its original state and clears the
     * intercepted-send log.  Persisted checklist completion is cleared by
     * [com.bizarreelectronics.crm.data.local.prefs.TrainingPreferences.resetTrainingData].
     */
    fun reset()
}

// =============================================================================
// Data models used exclusively in training mode
// =============================================================================

data class TrainingCustomer(
    val id: Long,
    val name: String,
    val phone: String,
    val email: String,
    val ticketCount: Int,
)

data class TrainingTicket(
    val id: Long,
    val customerName: String,
    val deviceName: String,
    val status: String,
    val createdAt: String,
    val assignedTo: String,
)

data class TrainingInventoryItem(
    val id: Long,
    val name: String,
    val sku: String,
    val quantity: Int,
    val price: Double,
)

data class TrainingSmsThread(
    val phone: String,
    val customerName: String,
    val lastMessage: String,
    val unreadCount: Int,
)

data class TestCard(
    val label: String,
    val number: String,
    val expectedResult: String,
)

data class InterceptedSend(
    val type: Type,
    val to: String,
    val preview: String,
    val timestamp: Long = System.currentTimeMillis(),
) {
    enum class Type { SMS, EMAIL }
}
