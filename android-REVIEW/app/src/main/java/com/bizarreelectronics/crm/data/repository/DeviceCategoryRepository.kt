package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.remote.api.CatalogApi
import com.bizarreelectronics.crm.data.remote.api.DeviceCategoryItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §POS device-type chip-row source of truth.
 *
 * Caches GET /catalog/categories in memory so chip-row UI renders instantly on
 * second composition. refresh() runs once on app start
 * (BizarreCrmApp.onCreate) — every restart picks up tenant catalog changes.
 *
 * Fallback list mirrors the server's CANONICAL_FALLBACK so the UI is never
 * empty even on a first-launch network failure.
 */
@Singleton
class DeviceCategoryRepository @Inject constructor(
    private val catalogApi: CatalogApi,
) {
    private val fallback = listOf(
        DeviceCategoryItem(slug = "phone",        label = "Phone"),
        DeviceCategoryItem(slug = "tablet",       label = "Tablet"),
        DeviceCategoryItem(slug = "laptop",       label = "Laptop"),
        DeviceCategoryItem(slug = "tv",           label = "TV"),
        DeviceCategoryItem(slug = "game-console", label = "Game Console"),
        DeviceCategoryItem(slug = "desktop",      label = "Desktop"),
    )

    private val _categories = MutableStateFlow(fallback)
    val categories: StateFlow<List<DeviceCategoryItem>> = _categories.asStateFlow()

    /** Refresh from server. Silent on failure — UI keeps current cache. */
    suspend fun refresh() {
        runCatching { catalogApi.getCategories() }
            .onSuccess { resp ->
                val rows = resp.data
                if (!rows.isNullOrEmpty()) _categories.value = rows
            }
    }
}
