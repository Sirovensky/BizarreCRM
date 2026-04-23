package com.bizarreelectronics.crm.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.io.IOException

/**
 * WorkManager worker that executes a queued multipart file upload (ActionPlan §1.1 L164).
 *
 * Survives app kill / Doze / OEM task killers by running as a [CoroutineWorker]
 * managed by the WorkManager runtime. The caller must enqueue via [MultipartUpload.enqueue]
 * so that deduplication via idempotency key is enforced before the job reaches here.
 *
 * Retry semantics:
 *   - 2xx                         → [Result.success]
 *   - 408 / 429 / 5xx / IOException → [Result.retry] (WorkManager exponential backoff)
 *   - Other 4xx (400, 401, 403…)  → [Result.failure] (do not retry; caller sees dead-letter)
 *   - File not found on disk       → [Result.failure] (can't retry what doesn't exist)
 *
 * Security: the file path is validated against the app's allowed private-storage
 * roots before the request is built. Paths outside those roots are rejected with
 * [Result.failure] to prevent sandbox escapes.
 *
 * Progress is reported via [setProgress] as a 0–100 integer keyed by [KEY_PROGRESS]
 * so callers can observe upload progress via WorkInfo.progress.
 */
@HiltWorker
class MultipartUploadWorker @AssistedInject constructor(
    @Assisted private val appContext: Context,
    @Assisted params: WorkerParameters,
    private val okHttpClient: OkHttpClient,
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "MultipartUploadWorker"

        // Input data keys
        const val KEY_LOCAL_PATH       = "local_path"
        const val KEY_TARGET_URL       = "target_url"
        const val KEY_IDEMPOTENCY_KEY  = "idempotency_key"
        const val KEY_CONTENT_TYPE     = "content_type"

        /** Prefix for flattened field entries. Field "foo" → "fields.foo". */
        const val FIELD_PREFIX = "fields."

        // Progress output key
        const val KEY_PROGRESS = "progress"

        private const val DEFAULT_CONTENT_TYPE = "application/octet-stream"

        /**
         * Builds a multipart OkHttp [Request] for the given file and fields.
         *
         * Pure companion (static) function — no Android runtime dependency.
         * Extracted here so it can be unit-tested without WorkManager infrastructure.
         *
         * The [targetUrl] must be an absolute HTTPS URL. The DynamicBaseUrlInterceptor
         * on the shared OkHttpClient will rewrite the host/port to the user-configured
         * server URL; the caller need only supply a path like
         * "https://placeholder.invalid/api/v1/tickets/123/photos".
         */
        internal fun buildRequest(
            file: File,
            targetUrl: String,
            fields: Map<String, String>,
            idempotencyKey: String,
            contentType: String,
        ): Request {
            val mediaType = contentType.toMediaType()
            val fileBody  = file.asRequestBody(mediaType)

            val multipart = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .apply {
                    fields.forEach { (key, value) -> addFormDataPart(key, value) }
                }
                .addFormDataPart("file", file.name, fileBody)
                .build()

            return Request.Builder()
                .url(targetUrl)
                .post(multipart)
                .header("X-Idempotency-Key", idempotencyKey)
                .build()
        }

        /**
         * Pure file validation: returns the [File] if it exists, is readable, and its
         * canonical path starts with one of [allowedRoots]. Returns null otherwise.
         *
         * No Android framework calls — safe to invoke from plain JVM unit tests.
         *
         * @param path         Absolute path to validate.
         * @param allowedRoots Canonical directory paths (with trailing [File.separator])
         *                     that are considered inside the app sandbox. Typically built
         *                     via [buildAllowedRoots].
         * @return The validated [File], or null if any check failed. The caller is
         *         responsible for logging the failure reason using the returned null.
         */
        internal fun validateFileAgainstRoots(path: String, allowedRoots: List<String>): File? {
            val file = File(path)
            if (!file.exists() || !file.canRead()) return null

            val canonicalPath = try {
                file.canonicalPath
            } catch (_: IOException) {
                return null
            }

            return if (allowedRoots.any { root -> canonicalPath.startsWith(root) }) file else null
        }
    }

    override suspend fun doWork(): Result {
        val localPath      = inputData.getString(KEY_LOCAL_PATH)       ?: return failWith("missing local_path")
        val targetUrl      = inputData.getString(KEY_TARGET_URL)       ?: return failWith("missing target_url")
        val idempotencyKey = inputData.getString(KEY_IDEMPOTENCY_KEY)  ?: return failWith("missing idempotency_key")
        val contentType    = inputData.getString(KEY_CONTENT_TYPE)     ?: DEFAULT_CONTENT_TYPE
        val fields         = extractFields(inputData)

        Log.d(TAG, "doWork attempt=$runAttemptCount key=$idempotencyKey target=$targetUrl")

        // File existence + sandbox validation
        val file = validateFileAgainstRoots(localPath, buildAllowedRoots())
        if (file == null) {
            Log.e(TAG, "Upload aborted — file not found or outside app sandbox: $localPath")
            return Result.failure()
        }

        setProgress(workDataOf(KEY_PROGRESS to 0))

        val request = try {
            buildRequest(
                file           = file,
                targetUrl      = targetUrl,
                fields         = fields,
                idempotencyKey = idempotencyKey,
                contentType    = contentType,
            )
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "Bad request parameters: ${e.message}")
            return Result.failure()
        }

        return try {
            okHttpClient.newCall(request).execute().use { response ->
                val code = response.code
                Log.d(TAG, "Upload response code=$code key=$idempotencyKey")

                when {
                    code in 200..299 -> {
                        setProgress(workDataOf(KEY_PROGRESS to 100))
                        Result.success()
                    }
                    // Transient server errors — retry
                    code == 408 || code == 429 || code in 500..599 -> {
                        Log.w(TAG, "Transient error $code — will retry (attempt=$runAttemptCount)")
                        Result.retry()
                    }
                    // Permanent client errors — dead-letter
                    else -> {
                        Log.e(TAG, "Permanent error $code — dead-lettering upload key=$idempotencyKey")
                        Result.failure()
                    }
                }
            }
        } catch (e: IOException) {
            Log.w(TAG, "Network error during upload (attempt=$runAttemptCount): ${e.message}")
            Result.retry()
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error during upload: ${e.message}")
            Result.failure()
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers — instance methods that require Android context
    // -------------------------------------------------------------------------

    /**
     * Extracts all "fields.*" entries from WorkManager input data into a plain
     * map, stripping the [FIELD_PREFIX].
     */
    private fun extractFields(data: androidx.work.Data): Map<String, String> {
        val result = mutableMapOf<String, String>()
        data.keyValueMap.forEach { (k, v) ->
            if (k.startsWith(FIELD_PREFIX) && v is String) {
                result[k.removePrefix(FIELD_PREFIX)] = v
            }
        }
        return result
    }

    /**
     * Returns canonical paths for all storage roots the app is allowed to read from.
     *
     * Allowed roots:
     *   - appContext.filesDir          → internal files
     *   - appContext.cacheDir          → internal cache
     *   - appContext.getExternalFilesDir(null) → app-specific external storage
     *     (no permission needed, scoped to this app)
     *   - appContext.externalCacheDir  → app-specific external cache
     */
    private fun buildAllowedRoots(): List<String> {
        val roots = mutableListOf<File>()
        roots += appContext.filesDir
        roots += appContext.cacheDir
        appContext.getExternalFilesDir(null)?.let { roots += it }
        appContext.externalCacheDir?.let { roots += it }

        return roots.mapNotNull { dir ->
            try {
                dir.canonicalPath + File.separator
            } catch (_: IOException) {
                null
            }
        }
    }

    private fun failWith(reason: String): Result {
        Log.e(TAG, "Upload dead-lettered: $reason")
        return Result.failure()
    }
}
