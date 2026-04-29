package com.bizarreelectronics.crm.lint

import com.android.tools.lint.client.api.UElementHandler
import com.android.tools.lint.detector.api.Category
import com.android.tools.lint.detector.api.Detector
import com.android.tools.lint.detector.api.Implementation
import com.android.tools.lint.detector.api.Issue
import com.android.tools.lint.detector.api.JavaContext
import com.android.tools.lint.detector.api.Scope
import com.android.tools.lint.detector.api.Severity
import org.jetbrains.uast.UElement
import org.jetbrains.uast.UImportStatement

/**
 * Lint rule: Retrofit / OkHttp imports are only permitted inside the
 * `data/remote` package family (i.e. any source file whose fully-qualified
 * class name contains `.data.remote.`).
 *
 * # Why this rule exists
 *
 * §1.6 sovereignty — all outbound network calls must go through `RetrofitClient`
 * and the typed Retrofit API interfaces in `data/remote/api/`. Direct use of
 * Retrofit or OkHttp outside that package bypasses:
 *   - the `DynamicBaseUrlInterceptor` (tenant-URL rewrite + HMAC validation)
 *   - the `AuthInterceptor` (JWT attachment + token refresh)
 *   - the `RedactingHttpLogger` (PII scrub before logcat)
 *   - cert-pinning on release builds
 *   - the no-third-party-egress invariant (§32.1)
 *
 * Any legitimate use of low-level OkHttp that cannot go through Retrofit
 * (e.g. the BlockChyp local-terminal socket) must live in `data/remote/` or
 * be explicitly suppressed with a justification comment.
 *
 * # Suppression
 *
 * ```kotlin
 * @SuppressLint("RetrofitOutsideRemote")
 * class MySpecialCase { ... }  // ok:direct-http — reason here
 * ```
 */
class RetrofitOutsideRemoteDetector : Detector(), Detector.UastScanner {

    companion object {
        val ISSUE: Issue = Issue.create(
            id = "RetrofitOutsideRemote",
            briefDescription = "Retrofit / OkHttp import outside `data/remote` package",
            explanation = """
                Retrofit and OkHttp imports are only allowed inside the
                `data/remote` package (and its sub-packages).

                Direct use elsewhere bypasses the tenant-URL interceptor,
                auth interceptor, PII-scrubbing logger, cert-pinning, and
                the sovereignty rule (§1.6) that prohibits data egress to
                any host other than the configured tenant server.

                Move the network call into a Retrofit API interface under
                `data/remote/api/` or, for non-REST sockets, co-locate the
                code in `data/remote/`.

                Suppress only when unavoidable (e.g. hardware SDKs with their
                own HTTP stack) using `@SuppressLint("RetrofitOutsideRemote")`
                with an explanatory comment.
            """,
            category = Category.SECURITY,
            priority = 10,
            severity = Severity.ERROR,
            implementation = Implementation(
                RetrofitOutsideRemoteDetector::class.java,
                Scope.JAVA_FILE_SCOPE,
            ),
        )

        /** Import prefixes that are banned outside `data.remote`. */
        private val BANNED_PREFIXES: List<String> = listOf(
            "retrofit2.",
            "okhttp3.",
            "okio.",
            "com.google.firebase.crashlytics.",
            "com.google.firebase.analytics.",
            "com.google.firebase.perf.",
            "com.google.firebase.remoteconfig.",
            "io.sentry.",
        )

        /**
         * The path segment that marks a file as being inside the data/remote
         * layer. Path comparison is used (not package reflection) to avoid
         * relying on PSI type dispatch that varies across IDE / Lint versions.
         */
        private const val ALLOWED_PATH_SEGMENT = "/data/remote/"
    }

    override fun getApplicableUastTypes(): List<Class<out UElement>> =
        listOf(UImportStatement::class.java)

    override fun createUastHandler(context: JavaContext): UElementHandler =
        object : UElementHandler() {
            override fun visitImportStatement(node: UImportStatement) {
                val importedFqn = node.importReference?.asSourceString() ?: return

                // Is it a banned import?
                val banned = BANNED_PREFIXES.any { importedFqn.startsWith(it) }
                if (!banned) return

                // Derive the source-set-relative path using the canonical file
                // separator so the check works on both POSIX and Windows CI.
                val filePath = context.file.path.replace('\\', '/')

                // Allow anything under data/remote (all sub-packages included).
                if (ALLOWED_PATH_SEGMENT in filePath) return

                // Allow test source sets — lint normally skips them, but be
                // defensive so test utilities that mock Retrofit don't fail.
                if ("/test/" in filePath || "/androidTest/" in filePath) return

                context.report(
                    issue = ISSUE,
                    location = context.getLocation(node),
                    message = "`$importedFqn` must only be imported inside `data/remote/`. " +
                        "Use a Retrofit API interface or co-locate the code in `data/remote/`. " +
                        "See `RetrofitOutsideRemoteDetector` KDoc for suppression instructions.",
                )
            }
        }
}
