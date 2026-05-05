package com.bizarreelectronics.crm.di

import android.content.Context
import coil3.ImageLoader
import com.bizarreelectronics.crm.util.EncryptedCoilCache
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * §29 Coil cache tuning — explicit Hilt binding for the app-wide [ImageLoader].
 *
 * Sizes:
 *   - Disk cache : 100 MB cap (§29.7) in [Context.noBackupFilesDir] (encrypted,
 *     excluded from Auto-Backup).  Managed by [EncryptedCoilCache.buildImageLoader].
 *   - Memory cache: 25 % of available heap (§29.4).  Evicted on
 *     [TRIM_MEMORY_RUNNING_LOW] via [BizarreCrmApp.onTrimMemory].
 *
 * The singleton [ImageLoader] injected here is also installed as Coil's
 * process-level singleton in [BizarreCrmApp.newImageLoader], so every
 * [AsyncImage] call picks up the same instance regardless of how it resolves
 * the loader (explicit inject vs. [LocalImageLoader.current]).
 *
 * Bitmap decoding respects Coil's built-in [coil3.size.Size] mechanism —
 * callers that pass a [Modifier.size] or explicit [ImageRequest.size()] trigger
 * inSampleSize downsampling so heap allocation is bounded to the rendered
 * pixel budget, not the original server image size (§29.4).
 */
@Module
@InstallIn(SingletonComponent::class)
object CoilModule {

    /**
     * Provides the singleton [ImageLoader] configured with the encrypted disk
     * cache (100 MB cap) and a 25 %-of-heap memory cache.
     *
     * Inject this wherever an explicit [ImageLoader] reference is needed (e.g.,
     * in a custom [coil3.intercept.Interceptor] or a test double).  Regular
     * [AsyncImage] composables resolve it automatically via Coil's singleton.
     */
    @Provides
    @Singleton
    fun provideImageLoader(@ApplicationContext context: Context): ImageLoader =
        EncryptedCoilCache.buildImageLoader(context)
}
