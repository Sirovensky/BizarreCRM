package com.bizarreelectronics.crm.ui.screens.settings

import androidx.lifecycle.ViewModel
import com.bizarreelectronics.crm.util.RateLimiter
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * Thin Hilt ViewModel that exposes [RateLimiter] to [RateLimitBucketsScreen].
 *
 * No additional state or logic lives here — the screen collects [RateLimiter.buckets]
 * and [RateLimiter.queueState] directly. The ViewModel's only job is to survive
 * recomposition and provide Hilt-injected access to the singleton [RateLimiter].
 *
 * [plan:L258] — ActionPlan §1.2 line 258.
 */
@HiltViewModel
class RateLimitBucketsViewModel @Inject constructor(
    val rateLimiter: RateLimiter,
) : ViewModel()
