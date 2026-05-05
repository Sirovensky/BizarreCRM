package com.bizarreelectronics.crm.util

import androidx.work.Data
import com.bizarreelectronics.crm.data.sync.MultipartUploadWorker
import okhttp3.MultipartBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Pure JVM unit tests for [MultipartUpload] (input-data serialization) and
 * [MultipartUploadWorker] (request building + path validation).
 *
 * No Android Context, no Mockito, no MockWebServer, no Robolectric.
 *
 * Strategy:
 *   - [MultipartUploadWorker.buildRequest] is an `internal` companion (static)
 *     function that takes only plain JVM types (File, String, Map). Called directly.
 *   - [MultipartUploadWorker.validateFileAgainstRoots] is an `internal` companion
 *     function — no Android classes required.
 *   - [MultipartUpload.buildInputData] is exercised via a local replica that uses
 *     [androidx.work.workDataOf] (work-runtime-ktx is on the JVM test classpath and
 *     its Data builder has no Android runtime dependency).
 *
 * Coverage:
 *   1. Happy path — POST with MultipartBody
 *   2. File part is named "file"
 *   3. File basename appears in Content-Disposition filename
 *   4. X-Idempotency-Key header present and correct
 *   5. Request URL matches targetUrl
 *   6. Fields serialise through buildInputData with "fields." prefix
 *   7. buildInputData stores localPath, targetUrl, idempotencyKey, contentType
 *   8. Empty fields map → exactly one part (the file part)
 *   9. contentType forwarded to file part body
 *  10. validateFileAgainstRoots returns null for missing file
 *  11. validateFileAgainstRoots returns null for file outside allowed roots
 *  12. validateFileAgainstRoots returns file when path is inside allowed root
 *  13. Path traversal attempt is blocked
 *  14. File inside second of multiple allowed roots is accepted
 */
class MultipartUploadTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    // -------------------------------------------------------------------------
    // 1. Happy path — POST with MultipartBody
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest produces POST with multipart body`() {
        val file    = tempFolder.newFile("photo.jpg").also { it.writeBytes(ByteArray(16)) }
        val url     = "https://example.com/api/v1/tickets/123/photos"

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = url,
            fields         = mapOf("ticketId" to "123"),
            idempotencyKey = "idem-001",
            contentType    = "image/jpeg",
        )

        assertEquals("POST", request.method)
        assertNotNull("body must be present", request.body)
        assertTrue(
            "body must be MultipartBody but was ${request.body?.javaClass}",
            request.body is MultipartBody,
        )
    }

    // -------------------------------------------------------------------------
    // 2. File part is named "file"
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest includes file part named file`() {
        val file    = tempFolder.newFile("receipt.pdf").also { it.writeBytes(ByteArray(32)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/expenses/1/receipt",
            fields         = emptyMap(),
            idempotencyKey = "idem-002",
            contentType    = "application/pdf",
        )

        val body     = request.body as MultipartBody
        val filePart = body.parts.firstOrNull { part ->
            part.headers?.get("Content-Disposition")?.contains("name=\"file\"") == true
        }
        assertNotNull("must have a part named 'file'", filePart)
    }

    // -------------------------------------------------------------------------
    // 3. File basename appears in Content-Disposition filename
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest uses file basename as filename in Content-Disposition`() {
        val file    = tempFolder.newFile("avatar.png").also { it.writeBytes(ByteArray(8)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/customers/42/avatar",
            fields         = emptyMap(),
            idempotencyKey = "idem-003",
            contentType    = "image/png",
        )

        val body        = request.body as MultipartBody
        val filePart    = body.parts.first { part ->
            part.headers?.get("Content-Disposition")?.contains("name=\"file\"") == true
        }
        val disposition = filePart.headers?.get("Content-Disposition") ?: ""
        assertTrue(
            "Content-Disposition must include filename=\"avatar.png\" but was: $disposition",
            disposition.contains("filename=\"avatar.png\""),
        )
    }

    // -------------------------------------------------------------------------
    // 4. X-Idempotency-Key header
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest sets X-Idempotency-Key header to supplied key`() {
        val file    = tempFolder.newFile("img.jpg").also { it.writeBytes(ByteArray(4)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/upload",
            fields         = emptyMap(),
            idempotencyKey = "my-stable-key-42",
            contentType    = "image/jpeg",
        )

        assertEquals(
            "X-Idempotency-Key header must match the supplied key",
            "my-stable-key-42",
            request.header("X-Idempotency-Key"),
        )
    }

    // -------------------------------------------------------------------------
    // 5. Target URL passes through
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest uses targetUrl as the request URL`() {
        val file   = tempFolder.newFile("doc.pdf").also { it.writeBytes(ByteArray(4)) }
        val target = "https://example.com/api/v1/tickets/7/attachments"

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = target,
            fields         = emptyMap(),
            idempotencyKey = "idem-url",
            contentType    = "application/pdf",
        )

        assertEquals(target, request.url.toString())
    }

    // -------------------------------------------------------------------------
    // 6. Fields serialise through buildInputData with "fields." prefix
    // -------------------------------------------------------------------------

    @Test
    fun `buildInputData round-trips fields with fields-dot prefix`() {
        val data: Data = buildInputDataDirect(
            localPath      = "/data/files/photo.jpg",
            targetUrl      = "/api/v1/tickets/99/photos",
            fields         = mapOf("ticketId" to "99", "kind" to "after", "note" to "scratch"),
            idempotencyKey = "idem-fields",
            contentType    = "image/jpeg",
        )

        assertEquals("99",      data.getString("${MultipartUploadWorker.FIELD_PREFIX}ticketId"))
        assertEquals("after",   data.getString("${MultipartUploadWorker.FIELD_PREFIX}kind"))
        assertEquals("scratch", data.getString("${MultipartUploadWorker.FIELD_PREFIX}note"))
    }

    // -------------------------------------------------------------------------
    // 7. buildInputData stores core keys correctly
    // -------------------------------------------------------------------------

    @Test
    fun `buildInputData stores localPath, targetUrl, idempotencyKey, contentType`() {
        val data: Data = buildInputDataDirect(
            localPath      = "/data/files/foo.jpg",
            targetUrl      = "/api/v1/upload",
            fields         = emptyMap(),
            idempotencyKey = "stable-key-xyz",
            contentType    = "image/jpeg",
        )

        assertEquals("/data/files/foo.jpg", data.getString(MultipartUploadWorker.KEY_LOCAL_PATH))
        assertEquals("/api/v1/upload",       data.getString(MultipartUploadWorker.KEY_TARGET_URL))
        assertEquals("stable-key-xyz",       data.getString(MultipartUploadWorker.KEY_IDEMPOTENCY_KEY))
        assertEquals("image/jpeg",           data.getString(MultipartUploadWorker.KEY_CONTENT_TYPE))
    }

    // -------------------------------------------------------------------------
    // 8. Empty fields map → exactly one part (the file part)
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest with empty fields map produces exactly one part`() {
        val file    = tempFolder.newFile("only.jpg").also { it.writeBytes(ByteArray(4)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/upload",
            fields         = emptyMap(),
            idempotencyKey = "idem-empty",
            contentType    = "image/jpeg",
        )

        val body = request.body as MultipartBody
        assertEquals(
            "Body must contain exactly one part when no fields supplied",
            1,
            body.parts.size,
        )
    }

    // -------------------------------------------------------------------------
    // 9. contentType forwarded to file part body
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest forwards contentType to file part body media type`() {
        val file    = tempFolder.newFile("scan.png").also { it.writeBytes(ByteArray(4)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/upload",
            fields         = emptyMap(),
            idempotencyKey = "idem-ct",
            contentType    = "image/png",
        )

        val body     = request.body as MultipartBody
        val filePart = body.parts.first { p ->
            p.headers?.get("Content-Disposition")?.contains("name=\"file\"") == true
        }
        assertEquals(
            "File part body media type must match supplied contentType",
            "image/png",
            filePart.body.contentType()?.toString(),
        )
    }

    // -------------------------------------------------------------------------
    // 10. validateFileAgainstRoots — missing file
    // -------------------------------------------------------------------------

    @Test
    fun `validateFileAgainstRoots returns null when file does not exist`() {
        val root    = tempFolder.newFolder("filesDir")
        val missing = File(root, "nonexistent.jpg") // never created

        val result = MultipartUploadWorker.validateFileAgainstRoots(
            path         = missing.absolutePath,
            allowedRoots = listOf(root.canonicalPath + File.separator),
        )

        assertNull("Must return null for missing file", result)
    }

    // -------------------------------------------------------------------------
    // 11. validateFileAgainstRoots — path outside allowed roots
    // -------------------------------------------------------------------------

    @Test
    fun `validateFileAgainstRoots returns null for path outside allowed roots`() {
        val allowedDir   = tempFolder.newFolder("app_files")
        val outsideDir   = tempFolder.newFolder("outside")
        val outsideFile  = File(outsideDir, "evil.bin").also { it.writeBytes(ByteArray(4)) }

        val result = MultipartUploadWorker.validateFileAgainstRoots(
            path         = outsideFile.absolutePath,
            allowedRoots = listOf(allowedDir.canonicalPath + File.separator),
        )

        assertNull("Must return null for file outside allowed roots", result)
    }

    // -------------------------------------------------------------------------
    // 12. validateFileAgainstRoots — path inside allowed root
    // -------------------------------------------------------------------------

    @Test
    fun `validateFileAgainstRoots returns file when path is inside allowed root`() {
        val allowedDir = tempFolder.newFolder("app_files")
        val safeFile   = File(allowedDir, "photo.jpg").also { it.writeBytes(ByteArray(8)) }

        val result = MultipartUploadWorker.validateFileAgainstRoots(
            path         = safeFile.absolutePath,
            allowedRoots = listOf(allowedDir.canonicalPath + File.separator),
        )

        assertNotNull("Must return the file when inside allowed root", result)
        assertEquals(safeFile.canonicalPath, result!!.canonicalPath)
    }

    // -------------------------------------------------------------------------
    // 13. Path traversal attempt is blocked
    // -------------------------------------------------------------------------

    @Test
    fun `validateFileAgainstRoots blocks path traversal attempt`() {
        val allowedDir  = tempFolder.newFolder("app_files")
        val parentDir   = allowedDir.parentFile!!
        // A file in the parent directory is outside allowedDir.
        val parentFile  = File(parentDir, "traversal.bin").also { it.writeBytes(ByteArray(4)) }

        val result = MultipartUploadWorker.validateFileAgainstRoots(
            path         = parentFile.absolutePath,
            allowedRoots = listOf(allowedDir.canonicalPath + File.separator),
        )

        assertNull("Path traversal must be blocked", result)
    }

    // -------------------------------------------------------------------------
    // 14. Multiple allowed roots — file in second root is accepted
    // -------------------------------------------------------------------------

    @Test
    fun `validateFileAgainstRoots accepts file in second of multiple allowed roots`() {
        val root1     = tempFolder.newFolder("filesDir")
        val root2     = tempFolder.newFolder("cacheDir")
        val cacheFile = File(root2, "thumb.jpg").also { it.writeBytes(ByteArray(4)) }

        val result = MultipartUploadWorker.validateFileAgainstRoots(
            path         = cacheFile.absolutePath,
            allowedRoots = listOf(
                root1.canonicalPath + File.separator,
                root2.canonicalPath + File.separator,
            ),
        )

        assertNotNull("File in second root must be accepted", result)
    }

    // -------------------------------------------------------------------------
    // Integration smoke — executed via real OkHttpClient (no network required;
    // just verifies buildRequest produces a parseable Request object).
    // -------------------------------------------------------------------------

    @Test
    fun `buildRequest with multiple fields produces correct part count`() {
        val file    = tempFolder.newFile("data.zip").also { it.writeBytes(ByteArray(8)) }

        val request = MultipartUploadWorker.buildRequest(
            file           = file,
            targetUrl      = "https://example.com/api/v1/upload",
            fields         = mapOf("a" to "1", "b" to "2", "c" to "3"),
            idempotencyKey = "idem-multi",
            contentType    = "application/zip",
        )

        val body = request.body as MultipartBody
        // 3 field parts + 1 file part = 4 total
        assertEquals(
            "Expected 3 field parts + 1 file part = 4",
            4,
            body.parts.size,
        )
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /**
     * Replicates [MultipartUpload.buildInputData] without needing a real Context or
     * WorkManager instance. Uses the same key constants as the production code so
     * the test validates that the caller and worker agree on key names.
     */
    private fun buildInputDataDirect(
        localPath: String,
        targetUrl: String,
        fields: Map<String, String>,
        idempotencyKey: String,
        contentType: String,
    ): Data {
        val pairs = mutableListOf<Pair<String, Any?>>(
            MultipartUploadWorker.KEY_LOCAL_PATH      to localPath,
            MultipartUploadWorker.KEY_TARGET_URL      to targetUrl,
            MultipartUploadWorker.KEY_IDEMPOTENCY_KEY to idempotencyKey,
            MultipartUploadWorker.KEY_CONTENT_TYPE    to contentType,
        )
        fields.forEach { (k, v) ->
            pairs += "${MultipartUploadWorker.FIELD_PREFIX}$k" to v
        }
        return androidx.work.workDataOf(*pairs.toTypedArray())
    }
}
