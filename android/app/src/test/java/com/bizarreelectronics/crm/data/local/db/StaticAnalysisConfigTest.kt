package com.bizarreelectronics.crm.data.local.db

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * §31.7 — Static analysis: detekt + Android Lint + R8 obfuscation verify.
 *
 * This JVM test asserts that the static-analysis configuration artefacts
 * required by §31.7 are present and correctly configured:
 *
 *   1. `proguard-rules.pro` exists and contains required R8 keep rules for DTO
 *      classes, Room entities, Hilt ViewModels, and OkHttp/Gson.
 *   2. `lint-rules` module contains the custom [CrmIssueRegistry] service-loader
 *      file so the registry is discovered by the Lint runner at build time.
 *   3. Custom lint issues are registered (GlobalScope, RetrofitOutsideRemote,
 *      StatefulObjectSingleton).
 *
 * These checks are *file-content* assertions rather than running the actual tools —
 * running detekt/Lint as part of unit tests would require the full AGP toolchain.
 * The goal is to make regressions (e.g. accidentally deleting a keep rule) visible
 * in the JVM test suite before they surface as runtime crashes in production.
 *
 * ActionPlan §31.7 — Static analysis: detekt + Android Lint + R8 obfuscation verify.
 */
class StaticAnalysisConfigTest {

    // -------------------------------------------------------------------------
    // Locate project root relative to the test working directory
    // -------------------------------------------------------------------------

    /**
     * Walks up the filesystem from the current working directory until it finds a
     * directory that contains both `app/` and `lint-rules/` sub-directories,
     * which uniquely identifies the `android/` root of this project.
     */
    private fun findAndroidRoot(): File {
        var candidate = File(System.getProperty("user.dir"))
        repeat(10) {
            if (File(candidate, "app").isDirectory && File(candidate, "lint-rules").isDirectory) {
                return candidate
            }
            candidate = candidate.parentFile ?: return@repeat
        }
        // Fallback: try the gradle project dir property (set by AGP during test runs)
        val fromProperty = System.getProperty("user.dir")
        if (fromProperty != null) {
            val f = File(fromProperty)
            if (File(f, "app").isDirectory) return f
        }
        throw IllegalStateException(
            "Cannot locate android/ root from working dir: ${System.getProperty("user.dir")}. " +
                "Expected directory containing both app/ and lint-rules/.",
        )
    }

    // -------------------------------------------------------------------------
    // 1. proguard-rules.pro — R8 keep rules
    // -------------------------------------------------------------------------

    @Test
    fun `proguard-rules pro exists`() {
        val root = findAndroidRoot()
        val proguard = File(root, "app/proguard-rules.pro")
        assertTrue("proguard-rules.pro must exist at app/proguard-rules.pro", proguard.exists())
    }

    @Test
    fun `proguard-rules pro keeps DTO classes`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep data.remote.dto classes to prevent Gson serialisation breakage",
            content.contains("data.remote.dto"),
        )
    }

    @Test
    fun `proguard-rules pro keeps Room entity classes`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep data.local.db.entities to prevent Room cursor mapping failures",
            content.contains("data.local.db.entities"),
        )
    }

    @Test
    fun `proguard-rules pro keeps Hilt ViewModel constructors`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep Hilt @HiltViewModel constructors",
            content.contains("HiltViewModel"),
        )
    }

    @Test
    fun `proguard-rules pro keeps Retrofit annotations`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep Retrofit HTTP annotation-methods for interface generation",
            content.contains("retrofit2.http"),
        )
    }

    @Test
    fun `proguard-rules pro keeps Gson`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep Gson classes",
            content.contains("com.google.gson"),
        )
    }

    @Test
    fun `proguard-rules pro keeps Tink for EncryptedSharedPreferences`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        val content = proguard.readText()
        assertTrue(
            "proguard-rules.pro must keep Tink classes (required by EncryptedSharedPreferences)",
            content.contains("com.google.crypto.tink"),
        )
    }

    // -------------------------------------------------------------------------
    // 2. lint-rules service-loader registration
    // -------------------------------------------------------------------------

    @Test
    fun `lint-rules module contains IssueRegistry service-loader file`() {
        val root = findAndroidRoot()
        val serviceFile = File(
            root,
            "lint-rules/src/main/resources/META-INF/services/com.android.tools.lint.client.api.IssueRegistry",
        )
        assertTrue(
            "META-INF/services/com.android.tools.lint.client.api.IssueRegistry must exist " +
                "so the custom lint rules are discovered by the lint runner. " +
                "Expected: ${serviceFile.absolutePath}",
            serviceFile.exists(),
        )
    }

    @Test
    fun `lint IssueRegistry service file references CrmIssueRegistry`() {
        val root = findAndroidRoot()
        val serviceFile = File(
            root,
            "lint-rules/src/main/resources/META-INF/services/com.android.tools.lint.client.api.IssueRegistry",
        )
        if (!serviceFile.exists()) return  // Already caught by the existence test above.
        val content = serviceFile.readText()
        assertTrue(
            "Service file must reference CrmIssueRegistry",
            content.contains("CrmIssueRegistry"),
        )
    }

    // -------------------------------------------------------------------------
    // 3. CrmIssueRegistry source registers the three required issues
    // -------------------------------------------------------------------------

    @Test
    fun `CrmIssueRegistry source registers GlobalScopeLaunchDetector`() {
        val root = findAndroidRoot()
        val registry = File(
            root,
            "lint-rules/src/main/java/com/bizarreelectronics/crm/lint/CrmIssueRegistry.kt",
        )
        assertTrue("CrmIssueRegistry.kt must exist", registry.exists())
        val content = registry.readText()
        assertTrue(
            "CrmIssueRegistry must register GlobalScopeLaunchDetector",
            content.contains("GlobalScopeLaunchDetector"),
        )
    }

    @Test
    fun `CrmIssueRegistry source registers RetrofitOutsideRemoteDetector`() {
        val root = findAndroidRoot()
        val registry = File(
            root,
            "lint-rules/src/main/java/com/bizarreelectronics/crm/lint/CrmIssueRegistry.kt",
        )
        if (!registry.exists()) return
        val content = registry.readText()
        assertTrue(
            "CrmIssueRegistry must register RetrofitOutsideRemoteDetector (Firebase telemetry + sovereignty guard)",
            content.contains("RetrofitOutsideRemoteDetector"),
        )
    }

    @Test
    fun `CrmIssueRegistry source registers StatefulObjectSingletonDetector`() {
        val root = findAndroidRoot()
        val registry = File(
            root,
            "lint-rules/src/main/java/com/bizarreelectronics/crm/lint/CrmIssueRegistry.kt",
        )
        if (!registry.exists()) return
        val content = registry.readText()
        assertTrue(
            "CrmIssueRegistry must register StatefulObjectSingletonDetector",
            content.contains("StatefulObjectSingletonDetector"),
        )
    }

    // -------------------------------------------------------------------------
    // 4. Firebase-banned-module guard is present in app build.gradle.kts
    // -------------------------------------------------------------------------

    @Test
    fun `app build gradle kts contains firebase egress guard`() {
        val root = findAndroidRoot()
        val buildFile = File(root, "app/build.gradle.kts")
        assertTrue("app/build.gradle.kts must exist", buildFile.exists())
        val content = buildFile.readText()
        assertTrue(
            "build.gradle.kts must contain firebase-crashlytics in the ban-list (§32.1 sovereignty)",
            content.contains("firebase-crashlytics"),
        )
        assertTrue(
            "build.gradle.kts must contain firebase-analytics in the ban-list (§32.1 sovereignty)",
            content.contains("firebase-analytics"),
        )
        assertTrue(
            "build.gradle.kts must throw GradleException on banned firebase modules",
            content.contains("GradleException"),
        )
    }

    // -------------------------------------------------------------------------
    // 5. minifyEnabled (R8) is true in the release build type
    // -------------------------------------------------------------------------

    @Test
    fun `release build type has minifyEnabled true`() {
        val root = findAndroidRoot()
        val buildFile = File(root, "app/build.gradle.kts")
        if (!buildFile.exists()) return
        val content = buildFile.readText()
        // We look for the release block containing isMinifyEnabled = true.
        // A simple heuristic: the string "isMinifyEnabled = true" must appear
        // (there must not only be "isMinifyEnabled = false" which is debug).
        assertTrue(
            "Release build must have isMinifyEnabled = true for R8 obfuscation",
            content.contains("isMinifyEnabled = true"),
        )
    }

    // -------------------------------------------------------------------------
    // 6. shrinkResources is true alongside R8 in release
    // -------------------------------------------------------------------------

    @Test
    fun `release build type has isShrinkResources true`() {
        val root = findAndroidRoot()
        val buildFile = File(root, "app/build.gradle.kts")
        if (!buildFile.exists()) return
        val content = buildFile.readText()
        assertTrue(
            "Release build must have isShrinkResources = true to strip unused resources",
            content.contains("isShrinkResources = true"),
        )
    }

    // -------------------------------------------------------------------------
    // 7. proguard-rules.pro does NOT silently keep everything (anti-pattern guard)
    // -------------------------------------------------------------------------

    @Test
    fun `proguard-rules pro does not use keep-all wildcard that defeats obfuscation`() {
        val proguard = File(findAndroidRoot(), "app/proguard-rules.pro")
        if (!proguard.exists()) return
        val content = proguard.readText()
        // "-keep class * { *; }" with no package qualifier defeats R8 entirely.
        assertFalse(
            "proguard-rules.pro must not have a bare '-keep class * { *; }' that defeats R8 obfuscation",
            content.contains(Regex("""-keep\s+class\s+\*\s*\{\s*\*\s*;\s*\}""")),
        )
    }
}
