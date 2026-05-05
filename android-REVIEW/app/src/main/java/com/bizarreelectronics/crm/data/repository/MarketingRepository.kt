package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.remote.api.Campaign
import com.bizarreelectronics.crm.data.remote.api.CampaignPreviewData
import com.bizarreelectronics.crm.data.remote.api.CampaignStatsData
import com.bizarreelectronics.crm.data.remote.api.CreateCampaignRequest
import com.bizarreelectronics.crm.data.remote.api.CreateSegmentRequest
import com.bizarreelectronics.crm.data.remote.api.CustomerSegment
import com.bizarreelectronics.crm.data.remote.api.DispatchResult
import com.bizarreelectronics.crm.data.remote.api.MarketingApi
import com.bizarreelectronics.crm.data.remote.api.ReviewRequestTriggerRequest
import com.bizarreelectronics.crm.data.remote.api.SegmentMembersData
import com.bizarreelectronics.crm.data.remote.api.UpdateCampaignRequest
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for §37 Marketing & Growth.
 *
 * Wraps [MarketingApi]; thin pass-through with Timber logging on exceptions.
 * 404-tolerant — callers catch [retrofit2.HttpException] for graceful degrades.
 *
 * Plan §37 ActionPlan.md L2959-L3000.
 */
@Singleton
class MarketingRepository @Inject constructor(
    private val api: MarketingApi,
) {

    // ── Campaigns ─────────────────────────────────────────────────────────────

    suspend fun getCampaigns(): List<Campaign> {
        val resp = api.getCampaigns()
        return resp.data ?: emptyList()
    }

    suspend fun getCampaign(id: Long): Campaign? {
        return api.getCampaign(id).data
    }

    suspend fun createCampaign(request: CreateCampaignRequest): Campaign? {
        return api.createCampaign(request).data
    }

    suspend fun updateCampaign(id: Long, request: UpdateCampaignRequest): Campaign? {
        return api.updateCampaign(id, request).data
    }

    suspend fun deleteCampaign(id: Long): Boolean {
        return try {
            api.deleteCampaign(id)
            true
        } catch (e: Exception) {
            Timber.e(e, "MarketingRepository.deleteCampaign id=$id")
            false
        }
    }

    suspend fun previewCampaign(id: Long): CampaignPreviewData? {
        return api.previewCampaign(id).data
    }

    suspend fun runCampaignNow(id: Long): DispatchResult? {
        return api.runCampaignNow(id).data
    }

    suspend fun getCampaignStats(id: Long): CampaignStatsData? {
        return api.getCampaignStats(id).data
    }

    // ── Segments ──────────────────────────────────────────────────────────────

    suspend fun getSegments(): List<CustomerSegment> {
        val resp = api.getSegments()
        return resp.data ?: emptyList()
    }

    suspend fun createSegment(request: CreateSegmentRequest): CustomerSegment? {
        return api.createSegment(request).data
    }

    suspend fun refreshSegment(id: Long): CustomerSegment? {
        return api.refreshSegment(id).data
    }

    suspend fun getSegmentMembers(id: Long): SegmentMembersData? {
        return api.getSegmentMembers(id).data
    }

    // ── Review solicitation ───────────────────────────────────────────────────

    suspend fun triggerReviewRequest(ticketId: Long): DispatchResult? {
        return api.triggerReviewRequest(ReviewRequestTriggerRequest(ticketId)).data
    }
}
