package com.bizarreelectronics.crm.util

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkRequest
import androidx.work.workDataOf
import com.bizarreelectronics.crm.data.sync.MultipartUploadWorker
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * High-level multipart upload helper. Enqueues a WorkManager job so the
 * upload survives app kill / Doze / OEM task killers (ActionPlan §1.1 L164).
 *
 * Usage:
 *   multipartUpload.enqueue(
 *       localPath      = "/data/user/0/.../photo.jpg",
 *       targetUrl      = "/api/v1/tickets/123/photos",
 *       fields         = mapOf("ticketId" to "123", "kind" to "before"),
 *       idempotencyKey = UUID.randomUUID().toString(),
 *   )
 *
 * The Worker retries with exponential backoff on 5xx/network failure,
 * dead-letters after WorkManager's default 5 attempts.
 *
 * Idempotency: the caller MUST supply a stable idempotencyKey so repeated
 * enqueues (e.g. after app restart) don't re-upload the same file.
 *
 * Security: only paths under the app's private storage directories are
 * permitted. Absolute paths that escape the app sandbox are rejected by
 * [MultipartUploadWorker] before the request is built.
 */
@Singleton
class MultipartUpload @Inject constructor(
    @ApplicationContext private val context: Context,
    private val workManager: WorkManager,
) {

    companion object {
        private const val TAG = "MultipartUpload"

        /** Initial backoff before the first retry (exponential thereafter). */
        private const val INITIAL_BACKOFF_SECONDS = 30L
    }

    /**
     * Enqueues a multipart upload as a [OneTimeWorkRequest] with CONNECTED
     * network constraint and exponential backoff.
     *
     * Duplicate calls with the same [idempotencyKey] are deduplicated via
     * [ExistingWorkPolicy.KEEP] — the already-enqueued work wins.
     *
     * @param localPath     Absolute path to the file to upload. Must be under
     *                      the app's private storage (filesDir, cacheDir, or
     *                      getExternalFilesDir). Paths outside these roots are
     *                      rejected by the Worker.
     * @param targetUrl     Relative URL path (e.g. "/api/v1/tickets/123/photos").
     *                      The Worker prefixes the base URL stored in
     *                      AuthPreferences via OkHttp's DynamicBaseUrlInterceptor.
     * @param fields        Extra form fields to include in the multipart body.
     * @param idempotencyKey Stable per-upload identifier. Re-enqueuing with the
     *                      same key has no effect if the work is still pending.
     * @param contentType   MIME type for the file part (default: application/octet-stream).
     * @return The [WorkRequest] that was enqueued.
     */
    fun enqueue(
        localPath: String,
        targetUrl: String,
        fields: Map<String, String>,
        idempotencyKey: String,
        contentType: String = "application/octet-stream",
    ): WorkRequest {
        require(localPath.isNotBlank()) { "localPath must not be blank" }
        require(targetUrl.isNotBlank()) { "targetUrl must not be blank" }
        require(idempotencyKey.isNotBlank()) { "idempotencyKey must not be blank" }

        val inputData = buildInputData(
            localPath      = localPath,
            targetUrl      = targetUrl,
            fields         = fields,
            idempotencyKey = idempotencyKey,
            contentType    = contentType,
        )

        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = OneTimeWorkRequestBuilder<MultipartUploadWorker>()
            .setInputData(inputData)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, INITIAL_BACKOFF_SECONDS, TimeUnit.SECONDS)
            .build()

        workManager.enqueueUniqueWork(
            idempotencyKey,
            ExistingWorkPolicy.KEEP,
            workRequest,
        )

        Log.d(TAG, "Enqueued upload key=$idempotencyKey target=$targetUrl path=$localPath")

        return workRequest
    }

    /**
     * Serializes upload parameters into WorkManager [androidx.work.Data].
     *
     * Field entries are flattened as individual string key-value pairs with a
     * "fields." prefix so they round-trip cleanly through WorkManager's
     * string-only Data store without any JSON dependency.
     *
     * Exposed as package-internal for testing.
     */
    internal fun buildInputData(
        localPath: String,
        targetUrl: String,
        fields: Map<String, String>,
        idempotencyKey: String,
        contentType: String,
    ): androidx.work.Data {
        val pairs = mutableListOf<Pair<String, Any?>>(
            MultipartUploadWorker.KEY_LOCAL_PATH to localPath,
            MultipartUploadWorker.KEY_TARGET_URL to targetUrl,
            MultipartUploadWorker.KEY_IDEMPOTENCY_KEY to idempotencyKey,
            MultipartUploadWorker.KEY_CONTENT_TYPE to contentType,
        )
        fields.forEach { (k, v) ->
            pairs += "${MultipartUploadWorker.FIELD_PREFIX}$k" to v
        }
        return workDataOf(*pairs.toTypedArray())
    }
}
