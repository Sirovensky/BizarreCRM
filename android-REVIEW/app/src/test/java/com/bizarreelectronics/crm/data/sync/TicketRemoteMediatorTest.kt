package com.bizarreelectronics.crm.data.sync

import androidx.paging.ExperimentalPagingApi
import androidx.paging.LoadType
import androidx.paging.PagingConfig
import androidx.paging.PagingState
import com.bizarreelectronics.crm.data.local.db.dao.SyncStateDao
import com.bizarreelectronics.crm.data.local.db.dao.TicketDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncStateEntity
import com.bizarreelectronics.crm.data.local.db.entities.TicketEntity
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.TicketPageResponse
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM unit tests for [TicketRemoteMediator] (plan:L632 §4.3).
 *
 * Each test stubs [TicketApi] and the DAO interfaces in-memory (no Room, no
 * network). [PagingState] is constructed with an empty snapshot because the
 * mediator only reads [PagingConfig.pageSize] from it in REFRESH/APPEND paths.
 *
 * Tests:
 * - REFRESH happy-path: upserts items, writes cursor, returns Success(endOfPaginationReached=false).
 * - REFRESH exhausted: empty server response → endOfPaginationReached=true.
 * - APPEND happy-path: reads stored cursor, upserts items, returns Success.
 * - APPEND pre-exhausted: serverExhaustedAt set → returns Success(true) without API call.
 * - PREPEND: always no-op, returns Success(endOfPaginationReached=true).
 * - Error path: API throws → MediatorResult.Error wraps exception.
 */
@OptIn(ExperimentalPagingApi::class)
class TicketRemoteMediatorTest {

    // -----------------------------------------------------------------------
    // Stub infrastructure
    // -----------------------------------------------------------------------

    private lateinit var ticketDao: StubTicketDao
    private lateinit var syncStateDao: StubSyncStateDao
    private lateinit var ticketApi: StubTicketApi

    @Before
    fun setUp() {
        ticketDao = StubTicketDao()
        syncStateDao = StubSyncStateDao()
        ticketApi = StubTicketApi()
    }

    private fun mediator(filterKey: String = "") = TicketRemoteMediator(
        ticketDao = ticketDao,
        syncStateDao = syncStateDao,
        ticketApi = ticketApi,
        filterKey = filterKey,
    )

    private fun emptyPagingState(): PagingState<Int, TicketEntity> = PagingState(
        pages = emptyList(),
        anchorPosition = null,
        config = PagingConfig(pageSize = 50),
        leadingPlaceholderCount = 0,
    )

    // -----------------------------------------------------------------------
    // Tests
    // -----------------------------------------------------------------------

    @Test
    fun `REFRESH happy-path upserts items and writes cursor`() = runTest {
        val items = listOf(stubTicket(1L), stubTicket(2L))
        ticketApi.nextPage = TicketPageResponse(tickets = items, cursor = "cursor-abc", serverExhausted = false)

        val result = mediator().load(LoadType.REFRESH, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Success)
        val success = result as androidx.paging.RemoteMediator.MediatorResult.Success
        assertEquals(false, success.endOfPaginationReached)
        assertEquals(2, ticketDao.insertedCount)
        assertEquals("cursor-abc", syncStateDao.storedState?.cursor)
    }

    @Test
    fun `REFRESH with no cursor in response marks endOfPaginationReached`() = runTest {
        ticketApi.nextPage = TicketPageResponse(tickets = listOf(stubTicket(3L)), cursor = null, serverExhausted = false)

        val result = mediator().load(LoadType.REFRESH, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Success)
        val success = result as androidx.paging.RemoteMediator.MediatorResult.Success
        assertEquals(true, success.endOfPaginationReached)
        assertTrue(syncStateDao.storedState?.serverExhaustedAt != null)
    }

    @Test
    fun `APPEND happy-path reads stored cursor and upserts items`() = runTest {
        syncStateDao.storedState = SyncStateEntity(entity = "tickets", cursor = "page-2", lastUpdatedAt = 0L)
        val items = listOf(stubTicket(10L), stubTicket(11L))
        ticketApi.nextPage = TicketPageResponse(tickets = items, cursor = "page-3", serverExhausted = false)

        val result = mediator().load(LoadType.APPEND, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Success)
        assertEquals(2, ticketDao.insertedCount)
        // API must have been called with the stored cursor
        assertEquals("page-2", ticketApi.lastRequestedCursor)
    }

    @Test
    fun `APPEND when serverExhaustedAt is set skips API call`() = runTest {
        syncStateDao.storedState = SyncStateEntity(
            entity = "tickets",
            serverExhaustedAt = System.currentTimeMillis() - 1000L,
        )

        val result = mediator().load(LoadType.APPEND, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Success)
        val success = result as androidx.paging.RemoteMediator.MediatorResult.Success
        assertEquals(true, success.endOfPaginationReached)
        // API was never called
        assertEquals(0, ticketApi.callCount)
    }

    @Test
    fun `PREPEND always returns endOfPaginationReached=true without API call`() = runTest {
        val result = mediator().load(LoadType.PREPEND, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Success)
        assertEquals(true, (result as androidx.paging.RemoteMediator.MediatorResult.Success).endOfPaginationReached)
        assertEquals(0, ticketApi.callCount)
    }

    @Test
    fun `REFRESH API error returns MediatorResult Error`() = runTest {
        val error = RuntimeException("Network failure")
        ticketApi.throwOnLoad = error

        val result = mediator().load(LoadType.REFRESH, emptyPagingState())

        assertTrue(result is androidx.paging.RemoteMediator.MediatorResult.Error)
        assertEquals(error, (result as androidx.paging.RemoteMediator.MediatorResult.Error).throwable)
    }

    // -----------------------------------------------------------------------
    // Stub helpers
    // -----------------------------------------------------------------------

    private fun stubTicket(id: Long) = com.bizarreelectronics.crm.data.remote.dto.TicketListItem(
        id = id,
        orderId = "T-$id",
        customerId = null,
        customer = null,
        status = null,
        assignedUser = null,
        firstDevice = null,
        deviceCount = null,
        total = null,
        createdAt = "2024-01-01 00:00:00",
        updatedAt = "2024-01-01 00:00:00",
        isPinned = null,
        latestInternalNote = null,
    )

    // -----------------------------------------------------------------------
    // Stub DAOs and API
    // -----------------------------------------------------------------------

    private class StubTicketDao : TicketDao {
        var insertedCount = 0
        override suspend fun insertAll(tickets: List<TicketEntity>) { insertedCount += tickets.size }
        override fun pagingSource() = error("stub")
        override fun pagingSourceByStatusClosed(statusIsClosed: Boolean) = error("stub")
        override fun pagingSourceByAssignee(assignedTo: Long) = error("stub")
        override fun getAll() = error("stub")
        override fun getById(id: Long) = error("stub")
        override fun getOpenTickets() = error("stub")
        override fun getByCustomerId(customerId: Long) = error("stub")
        override fun getByAssignedTo(userId: Long) = error("stub")
        override fun search(query: String) = error("stub")
        override suspend fun getModifiedSince(since: String) = emptyList<TicketEntity>()
        override suspend fun getLocallyModified() = emptyList<TicketEntity>()
        override suspend fun upsert(ticket: TicketEntity) {}
        override suspend fun insert(ticket: TicketEntity) {}
        override suspend fun update(ticket: TicketEntity) {}
        override suspend fun deleteById(id: Long) {}
        override suspend fun repointDevices(tempId: Long, serverId: Long) {}
        override suspend fun repointNotes(tempId: Long, serverId: Long) {}
        override suspend fun updateCustomerIdByOldTempId(oldTempId: Long, newRealId: Long) {}
        override fun getCount() = error("stub")
        override fun getOpenCount() = error("stub")
    }

    private class StubSyncStateDao : SyncStateDao {
        var storedState: SyncStateEntity? = null
        override suspend fun upsert(entity: SyncStateEntity) { storedState = entity }
        override suspend fun get(entity: String, filter: String, parentId: Long) = storedState
        override fun observe(entity: String, filter: String, parentId: Long) = error("stub")
        override suspend fun hasMore(entity: String, filter: String, parentId: Long) = true
        override suspend fun clear() { storedState = null }
    }

    private class StubTicketApi : TicketApi {
        var nextPage: TicketPageResponse? = null
        var throwOnLoad: Throwable? = null
        var callCount = 0
        var lastRequestedCursor: String? = null

        override suspend fun getTicketPage(
            cursor: String?,
            limit: Int,
            filters: Map<String, String>,
        ): ApiResponse<TicketPageResponse> {
            callCount++
            lastRequestedCursor = cursor
            throwOnLoad?.let { throw it }
            return ApiResponse(success = true, data = nextPage ?: TicketPageResponse())
        }

        // Stubs for unused TicketApi methods
        override suspend fun getTickets(filters: Map<String, String>) = error("stub")
        override suspend fun getStats() = error("stub")
        override suspend fun getTicket(id: Long) = error("stub")
        override suspend fun createTicket(request: com.bizarreelectronics.crm.data.remote.dto.CreateTicketRequest) = error("stub")
        override suspend fun updateTicket(id: Long, request: com.bizarreelectronics.crm.data.remote.dto.UpdateTicketRequest) = error("stub")
        override suspend fun deleteTicket(id: Long) = error("stub")
        override suspend fun addNote(id: Long, note: Map<String, Any>) = error("stub")
        override suspend fun deleteNote(noteId: Long) = error("stub")
        override suspend fun togglePin(id: Long) = error("stub")
        override suspend fun convertToInvoice(id: Long) = error("stub")
        override suspend fun addDevice(ticketId: Long, request: com.bizarreelectronics.crm.data.remote.dto.CreateTicketDeviceRequest) = error("stub")
        override suspend fun updateDevice(deviceId: Long, request: com.bizarreelectronics.crm.data.remote.dto.UpdateTicketDeviceRequest) = error("stub")
        override suspend fun deleteDevice(deviceId: Long) = error("stub")
        override suspend fun addPartToDevice(deviceId: Long, request: com.bizarreelectronics.crm.data.remote.dto.AddTicketPartRequest) = error("stub")
        override suspend fun removePartFromDevice(partId: Long) = error("stub")
        override suspend fun uploadTicketPhotos(
            ticketId: Long,
            photos: List<okhttp3.MultipartBody.Part>,
            type: okhttp3.RequestBody,
            ticketDeviceId: okhttp3.RequestBody,
        ) = error("stub")
    }
}
