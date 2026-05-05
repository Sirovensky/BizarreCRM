package com.bizarreelectronics.crm.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.HttpException
import retrofit2.Response
import java.io.IOException

/**
 * §31.1 — unit coverage for §1.6 AppError taxonomy + factory.
 */
class AppErrorTest {

    @Test fun `IOException maps to Network branch`() {
        val err = AppError.from(IOException("boom"))
        assertTrue("expected Network branch but got ${err::class.simpleName}", err is AppError.Network)
        assertTrue(err.suggestedActions.any { it is AppErrorAction.Retry })
    }

    @Test fun `HTTP 401 maps to Auth SessionExpired`() {
        val err = AppError.from(http(401))
        assertTrue(err is AppError.Auth)
        assertEquals(AppError.AuthReason.SessionExpired, (err as AppError.Auth).reason)
        assertTrue(err.suggestedActions.any { it is AppErrorAction.SignIn })
    }

    @Test fun `HTTP 403 maps to Auth PermissionDenied without SignIn action`() {
        val err = AppError.from(http(403))
        assertTrue(err is AppError.Auth)
        assertEquals(AppError.AuthReason.PermissionDenied, (err as AppError.Auth).reason)
        assertTrue(err.suggestedActions.none { it is AppErrorAction.SignIn })
    }

    @Test fun `HTTP 404 maps to NotFound`() {
        val err = AppError.from(http(404))
        assertTrue(err is AppError.NotFound)
    }

    @Test fun `HTTP 409 maps to Conflict with Reload action`() {
        val err = AppError.from(http(409))
        assertTrue(err is AppError.Conflict)
        assertTrue(err.suggestedActions.any { it is AppErrorAction.Reload })
    }

    @Test fun `5xx surfaces server message on Server branch`() {
        val err = AppError.from(http(500))
        assertTrue(err is AppError.Server)
        assertEquals(500, (err as AppError.Server).status)
    }

    @Test fun `unknown exception surfaces as Unknown`() {
        val err = AppError.from(IllegalStateException("nope"))
        assertTrue(err is AppError.Unknown)
        assertNotNull((err as AppError.Unknown).cause)
    }

    @Test fun `every branch exposes a non-blank title`() {
        listOf(
            AppError.Network(null),
            AppError.Server(500, "boom", null),
            AppError.Auth(AppError.AuthReason.SessionExpired),
            AppError.Validation(emptyList()),
            AppError.NotFound("ticket", "12"),
            AppError.Conflict(null),
            AppError.Storage("disk full"),
            AppError.Hardware("camera", "blocked"),
            AppError.Cancelled,
            AppError.Unknown(null),
        ).forEach { err ->
            assertTrue("${err::class.simpleName} title was blank", err.title.isNotBlank())
        }
    }

    private fun http(code: Int): HttpException {
        // Build a minimal Response.error so HttpException has the code we need.
        val body = "".toResponseBody(null)
        return HttpException(Response.error<Any>(code, body))
    }
}
