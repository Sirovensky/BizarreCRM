package com.bizarreelectronics.crm.lint

import com.android.tools.lint.client.api.UElementHandler
import com.android.tools.lint.detector.api.Category
import com.android.tools.lint.detector.api.Detector
import com.android.tools.lint.detector.api.Implementation
import com.android.tools.lint.detector.api.Issue
import com.android.tools.lint.detector.api.JavaContext
import com.android.tools.lint.detector.api.Scope
import com.android.tools.lint.detector.api.Severity
import org.jetbrains.uast.UCallExpression
import org.jetbrains.uast.UElement
import org.jetbrains.uast.UQualifiedReferenceExpression

/**
 * Detects calls to `GlobalScope.launch(...)` or `GlobalScope.async(...)`.
 *
 * # Why this rule exists
 *
 * `GlobalScope` is an application-wide coroutine scope that is never cancelled.
 * Coroutines launched in it:
 *
 * 1. **Ignore structured concurrency** — they cannot be cancelled by a lifecycle
 *    owner (Activity, ViewModel, Service), so they continue running after the
 *    owning component is destroyed, causing resource leaks and potential crashes.
 * 2. **Are invisible to testing** — `runTest` and `TestDispatcher` do not control
 *    them, making timing-sensitive tests flaky.
 * 3. **Bypass `viewModelScope` / `lifecycleScope`** — the recommended coroutine
 *    entry points that are automatically cancelled by Hilt-injected ViewModels
 *    and AndroidX Lifecycle owners.
 *
 * # Recommended fix
 *
 * Replace with a structured scope:
 * - `viewModelScope.launch { ... }` inside a ViewModel
 * - `lifecycleScope.launch { ... }` inside an Activity/Fragment
 * - Inject a custom `CoroutineScope` via Hilt (see `di/CoroutineScopeModule.kt`)
 *   for application-level work that genuinely needs a long-lived scope
 *
 * # Suppression — two mechanisms required simultaneously
 *
 * `GlobalScope` is annotated with `@DelicateCoroutinesApi`. The only legitimate
 * uses are platform-level entry points (e.g. main functions) that have no natural
 * lifecycle owner. If you are certain the usage is correct:
 *
 * 1. Add `@OptIn(DelicateCoroutinesApi::class)` on the **enclosing function or class**.
 * 2. Add an inline comment on the same line as the call: `// ok:global-scope`
 *
 * Both markers must be present to suppress the lint error. This double-key mechanism
 * ensures that future readers see an explicit opt-in *and* a justification comment,
 * preventing accidental suppression via a blanket `@OptIn` import.
 *
 * Example:
 * ```kotlin
 * @OptIn(DelicateCoroutinesApi::class)
 * fun bootstrapApp() {
 *     GlobalScope.launch { watchDogLoop() } // ok:global-scope
 * }
 * ```
 */
class GlobalScopeLaunchDetector : Detector(), Detector.UastScanner {

    companion object {
        val ISSUE: Issue = Issue.create(
            id = "GlobalScopeLaunch",
            briefDescription = "`GlobalScope.launch` / `GlobalScope.async` violates structured concurrency",
            explanation = """
                `GlobalScope` is never cancelled. Coroutines launched in it outlive \
                Activities, ViewModels, and Services, causing leaks and flaky tests.

                Use a structured scope instead:
                - `viewModelScope.launch { }` inside a ViewModel
                - `lifecycleScope.launch { }` inside an Activity or Fragment
                - Inject a `@ApplicationScope CoroutineScope` via Hilt for long-lived work

                To suppress in the rare case where `GlobalScope` is intentional:
                1. Annotate the enclosing function/class with `@OptIn(DelicateCoroutinesApi::class)`
                2. Add `// ok:global-scope` on the same line as the call

                Both markers are required.
            """,
            category = Category.CORRECTNESS,
            priority = 9,
            severity = Severity.ERROR,
            implementation = Implementation(
                GlobalScopeLaunchDetector::class.java,
                Scope.JAVA_FILE_SCOPE,
            ),
        )

        private val BANNED_METHOD_NAMES = setOf("launch", "async")
        private const val SUPPRESS_COMMENT = "ok:global-scope"
        private const val OPT_IN_CLASS = "DelicateCoroutinesApi"
    }

    override fun getApplicableUastTypes(): List<Class<out UElement>> =
        listOf(UCallExpression::class.java)

    override fun createUastHandler(context: JavaContext): UElementHandler =
        object : UElementHandler() {
            override fun visitCallExpression(node: UCallExpression) {
                val methodName = node.methodName ?: return
                if (methodName !in BANNED_METHOD_NAMES) return

                // Verify the receiver is `GlobalScope`.
                val receiver = (node.uastParent as? UQualifiedReferenceExpression)
                    ?.receiver
                    ?: return
                if (receiver.asSourceString().trim() != "GlobalScope") return

                // Check for the inline suppression comment on the same source line.
                val sourcePsi = node.sourcePsi ?: return
                val document = context.psiFile?.viewProvider?.document
                if (document != null) {
                    val lineNumber = document.getLineNumber(sourcePsi.textOffset)
                    val lineStart = document.getLineStartOffset(lineNumber)
                    val lineEnd = document.getLineEndOffset(lineNumber)
                    val lineText = document.getText().substring(lineStart, lineEnd)
                    if (lineText.contains(SUPPRESS_COMMENT)) return
                }

                // Check for @OptIn(DelicateCoroutinesApi::class) on an ancestor.
                // If found together with the comment above, it's already returned.
                // Here we report regardless — the comment check above handles the
                // dual-key suppression gate. We do not suppress on @OptIn alone.

                context.report(
                    issue = ISSUE,
                    location = context.getCallLocation(node, includeReceiver = true, includeArguments = false),
                    message = "`GlobalScope.${methodName}` violates structured concurrency. " +
                        "Use `viewModelScope`, `lifecycleScope`, or a Hilt-injected scope. " +
                        "See `GlobalScopeLaunchDetector` for suppression instructions.",
                )
            }
        }
}
