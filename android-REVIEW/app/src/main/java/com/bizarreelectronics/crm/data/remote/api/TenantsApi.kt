package com.bizarreelectronics.crm.data.remote.api

import com.bizarreelectronics.crm.data.remote.dto.ApiResponse
import com.bizarreelectronics.crm.data.remote.dto.TenantSupportDto
import retrofit2.http.GET

/**
 * Retrofit interface for tenant-scoped configuration endpoints.
 *
 * ActionPlan §2.12 L355 — support-contact endpoint.
 *
 * NOTE: GET /api/v1/tenants/me/support-contact is not yet implemented server-side.
 * The client must gracefully handle 404 / network failure by showing "Contact your
 * admin." copy with no mail intent. See AccountLockedModal for the fallback logic.
 *
 * Registered in [com.bizarreelectronics.crm.data.remote.RetrofitClient.provideTenantsApi].
 */
interface TenantsApi {

    /**
     * Fetches the support contact for the current tenant.
     *
     * Returns `{ email, phone?, hours? }`. All fields are nullable — self-hosted
     * tenants return their own admin's contact; bizarrecrm.com-hosted tenants
     * return the operator's contact. Never interpret a null here as "use a
     * hardcoded fallback address".
     *
     * On 404 (server endpoint pending) or any network failure the caller must
     * catch the exception / check [ApiResponse.success] and degrade gracefully.
     */
    @GET("tenants/me/support-contact")
    suspend fun getSupportContact(): ApiResponse<TenantSupportDto>
}
