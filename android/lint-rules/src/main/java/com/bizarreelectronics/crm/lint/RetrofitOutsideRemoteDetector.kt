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
 * Bans direct imports of Retrofit / OkHttp / ApiClient classes outside the
 * `data/remote/` package tree.
 *
 * ## Rationale (ActionPlan §20.1)
 *
 * The repository pattern mandates that all network calls go through
 * `data/remote/` — ViewModels and domain layers must never hold a Retrofit
 * interface reference directly.  This rule enforces that at compile-time
 * without requiring code review to catch violations.
 *
 * ## Banned import prefixes
 *
 * | Prefix                  | Why                              |
 * |-------------------------|----------------------------------|
 * | `retrofit2.`            | Retrofit service interfaces      |
 * | `okhttp3.OkHttpClient`  | Raw HTTP client                  |
 * | `com.bizarreelectronics.crm.data.remote.RetrofitClient` | Internal wrapper — VMs must use repositories |
 *
 * ## Allowed packages
 *
 * Any file whose package starts with:
 * - `com.bizarreelectronics.crm.data.remote`  — network layer (retrofit services, interceptors)
 * - `com.bizarreelectronics.crm.di`           — Hilt modules that provide the client
 *
 * ## Suppression
 *
 * Add `// ok:retrofit-outside-remote` on the same line as the import statement
 * in the rare legitimate case (e.g. a test double that must hold the real type).
 */
class RetrofitOutsideRemoteDetector : Detector(), Detector.UastScanner {

    companion object {
        val ISSUE: Issue = Issue.create(
            id = "RetrofitOutsideRemote",
            briefDescription = "Retrofit/OkHttp/ApiClient import outside `data/remote/`",
            explanation = """
                Retrofit service interfaces, OkHttpClient, and RetrofitClient must only be \
                imported within `data/remote/` or `di/` packages. ViewModels and repositories \
                must call server APIs through typed repository methods that return `Flow` or \
                `suspend fun`, never by holding a raw Retrofit interface.

                This enforces the offline-first repository pattern: all network access is \
                funnelled through the repository layer so offline fallbacks, optimistic UI, \
                and sync-queue writes are consistently applied.

                To suppress in a genuine test double: add `// ok:retrofit-outside-remote` \
                to the same line as the offending import.
            """,
            category = Category.CORRECTNESS,
            priority = 8,
            severity = Severity.ERROR,
            implementation = Implementation(
                RetrofitOutsideRemoteDetector::class.java,
                Scope.JAVA_FILE_SCOPE,
            ),
        )

        private val BANNED_IMPORT_PREFIXES = listOf(
            "retrofit2.",
            "okhttp3.OkHttpClient",
            "com.bizarreelectronics.crm.data.remote.RetrofitClient",
        )

        private val ALLOWED_PACKAGE_PREFIXES = listOf(
            "com.bizarreelectronics.crm.data.remote",
            "com.bizarreelectronics.crm.di",
        )

        private const val SUPPRESS_COMMENT = "ok:retrofit-outside-remote"
    }

    override fun getApplicableUastTypes(): List<Class<out UElement>> =
        listOf(UImportStatement::class.java)

    override fun createUastHandler(context: JavaContext): UElementHandler =
        object : UElementHandler() {
            override fun visitImportStatement(node: UImportStatement) {
                val importFqn = node.importReference?.asSourceString() ?: return

                // Only flag imports that match a banned prefix.
                val isBanned = BANNED_IMPORT_PREFIXES.any { importFqn.startsWith(it) }
                if (!isBanned) return

                // Allow within data/remote and di packages.
                val packageName = context.psiFile?.let { f ->
                    (f as? com.intellij.psi.PsiJavaFile)?.packageName
                        ?: run {
                            // For Kotlin files, derive the package from the file's package directive.
                            f.name // fallback — won't match an allowed prefix, so we continue below
                        }
                } ?: ""

                // Use the file's containing directory path as a reliable signal.
                val filePath = context.file.path.replace('\\', '/')
                val isInAllowedPackage = ALLOWED_PACKAGE_PREFIXES.any { prefix ->
                    // Convert the package prefix to a path fragment.
                    val pathFragment = prefix.replace('.', '/')
                    filePath.contains(pathFragment)
                }
                if (isInAllowedPackage) return

                // Inline suppression comment on the import line.
                val sourcePsi = node.sourcePsi ?: return
                val document = context.psiFile?.viewProvider?.document
                if (document != null) {
                    val lineNumber = document.getLineNumber(sourcePsi.textOffset)
                    val lineStart = document.getLineStartOffset(lineNumber)
                    val lineEnd = document.getLineEndOffset(lineNumber)
                    val lineText = document.getText().substring(lineStart, lineEnd)
                    if (lineText.contains(SUPPRESS_COMMENT)) return
                }

                context.report(
                    issue = ISSUE,
                    location = context.getLocation(node),
                    message = "`$importFqn` must not be imported outside `data/remote/` or `di/`. " +
                        "Call APIs through a repository that returns `Flow` / `suspend fun`. " +
                        "See `RetrofitOutsideRemoteDetector` for suppression instructions.",
                )
            }
        }
}
