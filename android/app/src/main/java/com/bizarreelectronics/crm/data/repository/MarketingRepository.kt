package com.bizarreelectronics.crm.data.repository

import android.util.Log
import com.bizarreelectronics.crm.data.remote.api.CampaignDto
import com.bizarreelectronics.crm.data.remote.api.CampaignPreviewData
import com.bizarreelectronics.crm.data.remote.api.CampaignRunResult
import com.bizarreelectronics.crm.data.remote.api.CampaignStatsData
import com.bizarreelectronics.crm.data.remote.api.CreateCampaignRequest
import com.bizarreelectronics.crm.data.remote.api.CreateSegmentRequest
import com.bizarreelectronics.crm.data.remote.api.MarketingApi
import com.bizarreelectronics.crm.data.remote.api.SegmentApi
import com.bizarreelectronics.crm.data.remote.api.SegmentDto
import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import retrofit2.HttpException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for marketing campaigns and customer segments.
 *
 * Campaigns and segments are server-authoritative; there is no local
 * Room cache for marketing data (admin-only, low-frequency operations).
 * All methods require online connectivity and throw
 * [IllegalStateException] if offline.
 *
 * Both [MarketingApi] and [SegmentApi] are 404-tolerant: callers
 * receive null instead of a crash when the server does not yet expose
 * these endpoints.
 *
 * Plan §37 (ActionPlan.md lines 3255-3360).
 */
@Singleton
class MarketingRepository @Inject constructor(
    private val marketingApi: MarketingApi,
    private val segmentApi: SegmentApi,
    private val serverMonitor: ServerReachabilityMonitor,
) {

    // ─── Campaigns ────────────────────────────────────────────────────────────

    /**
     * Fetch all campaigns. Returns empty list on 404 (server doesn't
     * support the endpoint yet) or when offline.
     */
    suspend fun getCampaigns(): List<CampaignDto> {
        if (!serverMonitor.isEffectivelyOnline.value) return emptyList()
        return try {
            marketingApi.getCampaigns().data ?: emptyList()
        } catch (e: HttpException) {
            if (e.code() == 404) emptyList() else throw e
        } catch (e: Exception) {
            Log.w(TAG, "getCampaigns failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * Fetch a single campaign by ID. Returns null on 404.
     */
    suspend fun getCampaign(id: Long): CampaignDto? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            marketingApi.getCampaign(id).data
        } catch (e: HttpException) {
            if (e.code() == 404) null else throw e
        }
    }

    /**
     * Create a new campaign. Throws on failure.
     */
    suspend fun createCampaign(request: CreateCampaignRequest): CampaignDto {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot create campaign while offline")
        }
        val response = marketingApi.createCampaign(request)
        return response.data ?: throw Exception(response.message ?: "Create campaign failed")
    }

    /**
     * Update a campaign's status (draft → active → paused → archived).
     */
    suspend fun patchCampaign(id: Long, fields: Map<String, Any>): CampaignDto? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            marketingApi.patchCampaign(id, fields).data
        } catch (e: HttpException) {
            if (e.code() == 404) null else throw e
        }
    }

    /**
     * Delete a campaign.
     */
    suspend fun deleteCampaign(id: Long) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot delete campaign while offline")
        }
        marketingApi.deleteCampaign(id)
    }

    /**
     * Dry-run a campaign: returns recipient count and 3 sample rendered
     * messages. Returns null on 404.
     */
    suspend fun previewCampaign(id: Long): CampaignPreviewData? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            marketingApi.previewCampaign(id).data
        } catch (e: HttpException) {
            if (e.code() == 404) null else throw e
        }
    }

    /**
     * Dispatch campaign to all eligible recipients immediately.
     * Server rate-limits this to 3 calls/minute per user.
     * Throws on offline or HTTP error.
     */
    suspend fun runCampaignNow(id: Long): CampaignRunResult {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot dispatch campaign while offline")
        }
        val response = marketingApi.runCampaignNow(id)
        return response.data ?: throw Exception(response.message ?: "Campaign dispatch failed")
    }

    /**
     * Fetch send/fail/reply/convert metrics for a campaign.
     * Returns null on 404.
     */
    suspend fun getCampaignStats(id: Long): CampaignStatsData? {
        if (!serverMonitor.isEffectivelyOnline.value) return null
        return try {
            marketingApi.getCampaignStats(id).data
        } catch (e: HttpException) {
            if (e.code() == 404) null else throw e
        }
    }

    // ─── Segments ─────────────────────────────────────────────────────────────

    /**
     * Fetch all customer segments. Returns empty list on 404.
     */
    suspend fun getSegments(): List<SegmentDto> {
        if (!serverMonitor.isEffectivelyOnline.value) return emptyList()
        return try {
            segmentApi.getSegments().data ?: emptyList()
        } catch (e: HttpException) {
            if (e.code() == 404) emptyList() else throw e
        } catch (e: Exception) {
            Log.w(TAG, "getSegments failed: ${e.message}")
            emptyList()
        }
    }

    /**
     * Create a new customer segment. Throws on failure.
     */
    suspend fun createSegment(request: CreateSegmentRequest): SegmentDto {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot create segment while offline")
        }
        val response = segmentApi.createSegment(request)
        return response.data ?: throw Exception(response.message ?: "Create segment failed")
    }

    /**
     * Trigger a server-side refresh of segment membership.
     */
    suspend fun refreshSegment(id: Long) {
        if (!serverMonitor.isEffectivelyOnline.value) return
        try {
            segmentApi.refreshSegment(id)
        } catch (e: HttpException) {
            if (e.code() != 404) throw e
        }
    }

    /**
     * Delete a segment. Throws on failure.
     */
    suspend fun deleteSegment(id: Long) {
        if (!serverMonitor.isEffectivelyOnline.value) {
            throw IllegalStateException("Cannot delete segment while offline")
        }
        segmentApi.deleteSegment(id)
    }

    companion object {
        private const val TAG = "MarketingRepository"
    }
}
