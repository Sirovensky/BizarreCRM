package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.remote.api.StocktakeApi
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCommitRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCount
import com.bizarreelectronics.crm.data.remote.dto.StocktakeCreateRequest
import com.bizarreelectronics.crm.data.remote.dto.StocktakeListItem
import com.bizarreelectronics.crm.data.remote.dto.StocktakeSessionDetail
import com.bizarreelectronics.crm.data.remote.dto.StocktakeUpsertCountRequest
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class StocktakeRepository @Inject constructor(
    private val stocktakeApi: StocktakeApi,
) {
    suspend fun listSessions(status: String? = null): List<StocktakeListItem> =
        stocktakeApi.listSessions(status).data ?: emptyList()

    suspend fun createSession(request: StocktakeCreateRequest): StocktakeListItem =
        stocktakeApi.createSession(request).data
            ?: throw IllegalStateException("Server returned no stocktake session")

    suspend fun getSession(id: Int): StocktakeSessionDetail =
        stocktakeApi.getSession(id).data
            ?: throw IllegalStateException("Server returned no stocktake detail")

    suspend fun upsertCount(
        sessionId: Int,
        inventoryItemId: Long,
        countedQty: Int,
        notes: String? = null,
    ): StocktakeCount =
        stocktakeApi.upsertCount(
            id = sessionId,
            request = StocktakeUpsertCountRequest(
                inventoryItemId = inventoryItemId,
                countedQty = countedQty,
                notes = notes,
            ),
        ).data ?: throw IllegalStateException("Server returned no stocktake count")

    suspend fun commitSession(id: Int) {
        stocktakeApi.commitById(id)
    }

    suspend fun cancelSession(id: Int) {
        stocktakeApi.cancelById(id)
    }

    suspend fun startLegacySession(): String? =
        stocktakeApi.startSession().data?.sessionId

    suspend fun commitLegacySession(request: StocktakeCommitRequest) {
        stocktakeApi.commitSession(request)
    }
}
