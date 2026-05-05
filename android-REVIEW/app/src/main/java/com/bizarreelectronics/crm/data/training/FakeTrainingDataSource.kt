package com.bizarreelectronics.crm.data.training

import android.util.Log
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §53 — Concrete in-memory implementation of [TrainingDataSource].
 *
 * Returns canned demo data for every list/detail screen so staff can practice
 * workflows without server access.  All mutation calls are silently swallowed
 * (§53.4 no-send guards) — nothing is persisted or sent to the network.
 *
 * ## Seeded data overview (§53.2)
 * - 3 demo customers
 * - 4 demo tickets across different statuses
 * - 5 inventory items at varying stock levels
 * - 2 SMS threads
 * - BlockChyp sandbox test card numbers
 *
 * All IDs use negative values (–1, –2, …) so they can never collide with
 * real server IDs and are trivially identifiable in logs.
 */
@Singleton
class FakeTrainingDataSource @Inject constructor() : TrainingDataSource {

    private val interceptedLog = mutableListOf<InterceptedSend>()

    // -------------------------------------------------------------------------
    // §53.2 — Seeded demo data
    // -------------------------------------------------------------------------

    override fun getDemoCustomers(): List<TrainingCustomer> = DEMO_CUSTOMERS

    override fun getDemoTickets(): List<TrainingTicket> = DEMO_TICKETS

    override fun getDemoInventoryItems(): List<TrainingInventoryItem> = DEMO_INVENTORY

    override fun getDemoSmsThreads(): List<TrainingSmsThread> = DEMO_SMS_THREADS

    override val testBlockChypCardNumbers: List<TestCard> = TEST_CARDS

    // -------------------------------------------------------------------------
    // §53.4 — No-send guards
    // -------------------------------------------------------------------------

    override fun interceptSmsSend(to: String, body: String): Boolean {
        val entry = InterceptedSend(
            type = InterceptedSend.Type.SMS,
            to = to,
            preview = body.take(80),
        )
        interceptedLog.add(0, entry)
        Log.i(TAG, "[TRAINING] SMS intercepted → $to: ${body.take(40)}…")
        return true
    }

    override fun interceptEmailSend(to: String, subject: String, body: String): Boolean {
        val entry = InterceptedSend(
            type = InterceptedSend.Type.EMAIL,
            to = to,
            preview = subject.take(80),
        )
        interceptedLog.add(0, entry)
        Log.i(TAG, "[TRAINING] Email intercepted → $to: $subject")
        return true
    }

    override fun getInterceptedSendLog(): List<InterceptedSend> = interceptedLog.toList()

    // -------------------------------------------------------------------------
    // §53.3 — Reset
    // -------------------------------------------------------------------------

    override fun reset() {
        interceptedLog.clear()
        Log.i(TAG, "[TRAINING] Training data reset.")
    }

    // -------------------------------------------------------------------------
    // Canned data definitions
    // -------------------------------------------------------------------------

    private companion object {
        private const val TAG = "FakeTrainingDataSource"

        val DEMO_CUSTOMERS = listOf(
            TrainingCustomer(
                id = -1L,
                name = "Alex Demo",
                phone = "+15550001111",
                email = "alex.demo@example.com",
                ticketCount = 2,
            ),
            TrainingCustomer(
                id = -2L,
                name = "Sam Trainee",
                phone = "+15550002222",
                email = "sam.trainee@example.com",
                ticketCount = 1,
            ),
            TrainingCustomer(
                id = -3L,
                name = "Jordan Practice",
                phone = "+15550003333",
                email = "jordan.practice@example.com",
                ticketCount = 3,
            ),
        )

        val DEMO_TICKETS = listOf(
            TrainingTicket(
                id = -1L,
                customerName = "Alex Demo",
                deviceName = "iPhone 15 Pro",
                status = "Diagnosed",
                createdAt = "2026-04-25",
                assignedTo = "Tech A",
            ),
            TrainingTicket(
                id = -2L,
                customerName = "Alex Demo",
                deviceName = "Samsung Galaxy S24",
                status = "Waiting for Parts",
                createdAt = "2026-04-26",
                assignedTo = "Tech B",
            ),
            TrainingTicket(
                id = -3L,
                customerName = "Sam Trainee",
                deviceName = "Google Pixel 8",
                status = "Ready for Pickup",
                createdAt = "2026-04-20",
                assignedTo = "Tech A",
            ),
            TrainingTicket(
                id = -4L,
                customerName = "Jordan Practice",
                deviceName = "iPad Air (5th gen)",
                status = "In Progress",
                createdAt = "2026-04-27",
                assignedTo = "Tech C",
            ),
        )

        val DEMO_INVENTORY = listOf(
            TrainingInventoryItem(id = -1L, name = "iPhone 15 Screen (OEM)",   sku = "TRN-IP15-SCR", quantity = 5,  price = 89.99),
            TrainingInventoryItem(id = -2L, name = "iPhone 15 Battery",        sku = "TRN-IP15-BAT", quantity = 12, price = 24.99),
            TrainingInventoryItem(id = -3L, name = "Samsung S24 Back Glass",   sku = "TRN-S24-BKG",  quantity = 3,  price = 19.99),
            TrainingInventoryItem(id = -4L, name = "USB-C Charging Port",      sku = "TRN-USBC-PORT", quantity = 0, price = 8.99),
            TrainingInventoryItem(id = -5L, name = "Gorilla Glass Protector",  sku = "TRN-GG-PROT",  quantity = 20, price = 4.99),
        )

        val DEMO_SMS_THREADS = listOf(
            TrainingSmsThread(
                phone = "+15550001111",
                customerName = "Alex Demo",
                lastMessage = "[TRAINING] Your iPhone 15 Pro is ready for pickup!",
                unreadCount = 1,
            ),
            TrainingSmsThread(
                phone = "+15550003333",
                customerName = "Jordan Practice",
                lastMessage = "[TRAINING] Hi, any update on my iPad repair?",
                unreadCount = 2,
            ),
        )

        /**
         * §53.2 — BlockChyp sandbox test card numbers.
         *
         * These numbers simulate approved / declined / partial outcomes in
         * the BlockChyp test environment.  They do NOT reach the live network.
         * See https://docs.blockchyp.com/testing for the full test-card list.
         */
        val TEST_CARDS = listOf(
            TestCard(label = "Visa — Approved",       number = "4111111111111111", expectedResult = "Approved"),
            TestCard(label = "Mastercard — Approved", number = "5500005555555559", expectedResult = "Approved"),
            TestCard(label = "Visa — Declined",        number = "4000000000000002", expectedResult = "Declined"),
            TestCard(label = "Discover — Approved",   number = "6011111111111117", expectedResult = "Approved"),
            TestCard(label = "Amex — Approved",       number = "371449635398431",  expectedResult = "Approved"),
        )
    }
}
