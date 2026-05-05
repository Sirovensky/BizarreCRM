import java.util.Properties

fun quoteBuildConfig(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

fun readRepoEnv(): Properties {
    val props = Properties()
    // rootProject.projectDir = bizarre-crm/android/. .env lives one level up
    // at bizarre-crm/.env. (Older layouts had android at bizarre-crm/packages/
    // android/ which needed parentFile.parentFile; that path was stale after
    // the move and silently fell back to BASE_DOMAIN=localhost.)
    val repoEnv = rootProject.projectDir.parentFile.resolve(".env")
    if (repoEnv.exists()) {
        repoEnv.inputStream().use { props.load(it) }
    }
    return props
}

fun normalizeBaseDomain(raw: String): String =
    raw.trim()
        .removeSurrounding("\"")
        .removeSurrounding("'")
        .removePrefix("https://")
        .removePrefix("http://")
        .substringBefore("/")
        .trim()
        .ifBlank { "bizarrecrm.com" }

val repoEnv = readRepoEnv()
val configuredBaseDomain = normalizeBaseDomain(
    providers.gradleProperty("BASE_DOMAIN").orNull
        ?: System.getenv("BASE_DOMAIN")
        ?: repoEnv.getProperty("BASE_DOMAIN")
        ?: "bizarrecrm.com"
)
val configuredServerUrl = "https://$configuredBaseDomain"

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt.android)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.bizarreelectronics.crm"
    // compileSdk 36 — bumped per plan §1.6 L210. targetSdk remains 35 until
    // instrumented-test coverage is verified on API 36 emulators.
    compileSdk = 36

    defaultConfig {
        applicationId = "com.bizarreelectronics.crm"
        minSdk = 26
        targetSdk = 35
        // §33.2 — versionCode = Unix epoch seconds / 60 (monotonic, Play-safe).
        // Evaluated at configuration time so the same value stamps every variant
        // in a single invocation. The formula guarantees strict monotonicity:
        // two builds a minute apart always produce a higher code.
        // Override via -PversionCode=<n> in CI to use the build-runner's sequence
        // number instead (e.g. GitHub Actions: -PversionCode=${{ github.run_number }}).
        versionCode = providers.gradleProperty("versionCode").orNull?.toIntOrNull()
            ?: (System.currentTimeMillis() / 1000L / 60L).toInt()
        versionName = "0.5.0"

        // Optional ABI filter via -PtargetAbi=arm64-v8a (or comma-separated
        // list). Used to produce smaller per-arch APKs when distributing a
        // build outside Play (Play handles per-ABI splits server-side). Off
        // by default — universal APK with all four ABIs is shipped otherwise.
        providers.gradleProperty("targetAbi").orNull?.let { raw ->
            ndk {
                abiFilters += raw.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            }
        }

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Default server URL - users can override with custom host in the app.
        // BASE_DOMAIN comes from Gradle -PBASE_DOMAIN, environment, or repo .env.
        buildConfigField("String", "BASE_DOMAIN", quoteBuildConfig(configuredBaseDomain))
        buildConfigField("String", "SERVER_URL", quoteBuildConfig(configuredServerUrl))

        // M3 Expressive theme feature flag. Default true across all build types.
        // Ops can flip to "false" in a hotfix if a whole-app expressive
        // regression hits production without requiring a full rebuild cycle —
        // MaterialExpressiveTheme collapses back to MaterialTheme cleanly.
        buildConfigField("boolean", "USE_EXPRESSIVE_THEME", "true")
    }

    // Release signing config — keystore is read from a properties file outside
    // the project tree (~/.android-keystores/bizarrecrm-release.properties).
    // Fails the build (fail-closed) when that file is missing and a release
    // variant is being assembled. Debug builds are unaffected.
    val releaseKeystorePropsFile = file(System.getProperty("user.home") + "/.android-keystores/bizarrecrm-release.properties")
    val releaseKeystoreProps = Properties()

    val isReleaseBuild = gradle.startParameter.taskNames.any { task ->
        task.contains(":assembleRelease", ignoreCase = true) ||
        task.contains(":bundleRelease", ignoreCase = true) ||
        task.equals("assembleRelease", ignoreCase = true) ||
        task.equals("bundleRelease", ignoreCase = true)
    }

    if (isReleaseBuild && !releaseKeystorePropsFile.exists()) {
        throw GradleException(
            "Release signing requires ~/.android-keystores/bizarrecrm-release.properties — build aborted.\n" +
            "Expected path: ${releaseKeystorePropsFile.absolutePath}\n" +
            "Create the file with storeFile, storePassword, keyAlias, and keyPassword properties."
        )
    }

    if (releaseKeystorePropsFile.exists()) {
        releaseKeystorePropsFile.inputStream().use { releaseKeystoreProps.load(it) }
    }

    signingConfigs {
        create("release") {
            if (releaseKeystorePropsFile.exists()) {
                storeFile = file(releaseKeystoreProps.getProperty("storeFile"))
                storePassword = releaseKeystoreProps.getProperty("storePassword")
                keyAlias = releaseKeystoreProps.getProperty("keyAlias")
                keyPassword = releaseKeystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            buildConfigField("String", "SERVER_URL", quoteBuildConfig(configuredServerUrl))
        }
        release {
            isMinifyEnabled = true
            // §29.3 — R8 resource shrinking: strips unused drawables, layouts,
            // and string resources after code shrinking so they don't bloat the APK.
            // Must be paired with isMinifyEnabled = true (already set above).
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "SERVER_URL", quoteBuildConfig(configuredServerUrl))
            // signingConfig is only applied when the keystore file exists.
            // If it is missing and this is a release build, the GradleException
            // above has already aborted the build before reaching here.
            if (releaseKeystorePropsFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Android 16+ requires 16 KB page-size alignment for all native libs.
    // useLegacyPackaging = false → AGP emits uncompressed .so files aligned
    // on 16 KB boundaries so Android 16 / Pixel 6 Pro stops warning
    // "this app isn't 16 KB compatible".
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    // §33.4 — AAB split delivery: split the bundle by ABI, screen density, and
    // language so Play only delivers the slices relevant to each device.
    // Reduces download size by ~40% on typical mid-range phones compared with
    // a fat APK. Language splits are especially valuable for ML Kit model bundles.
    bundle {
        abi {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        language {
            enableSplit = true
        }
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    // Core Android
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    // §1.6: ProcessLifecycleOwner for app foreground/background hooks.
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.activity.compose)

    // Compose + Material 3
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material3.adaptive.navigation.suite)
    implementation(libs.androidx.compose.material.icons.extended)

    // §22 L2235 — material3-adaptive: NavigableListDetailPaneScaffold + NavigableSupportingPaneScaffold
    implementation(libs.material3.adaptive)
    implementation(libs.material3.adaptive.layout)
    implementation(libs.material3.adaptive.navigation)

    // §22 L2280 — androidx.window: WindowInfoTracker for foldable posture detection
    implementation(libs.androidx.window)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // Navigation
    implementation(libs.androidx.navigation.compose)

    // Room (SQLite)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    // SQLCipher — encrypts customer PII at rest. Wired into Room via
    // SupportFactory in di/DatabaseModule.kt. The passphrase is a per-install
    // random 32 bytes persisted in EncryptedSharedPreferences (see
    // data/local/prefs/DatabasePassphrase.kt).
    implementation(libs.sqlcipher.android)
    implementation(libs.androidx.sqlite.ktx)

    // Hilt (Dependency Injection)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.androidx.hilt.navigation.compose)
    implementation(libs.androidx.hilt.work)
    ksp(libs.androidx.hilt.compiler)

    // Retrofit + OkHttp (Networking)
    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.gson)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging.interceptor)

    // WorkManager (Background Sync)
    implementation(libs.androidx.work.runtime.ktx)

    // §29 — JankStats: lightweight frame-timing collector. Records janky
    // frames (>16ms over the deadline) without an external profiler so
    // perf regressions surface in CrashReporter breadcrumbs.
    implementation(libs.androidx.metrics.performance)

    // CameraX (Photo capture + live barcode/document scanning — §17.1/17.2/17.3)
    implementation(libs.androidx.camera.core)
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.view)

    // ML Kit (Barcode scanning — §17.2 L1870-L1874)
    implementation(libs.mlkit.barcode.scanning)

    // GMS Document Scanner (§17.3 L1877-L1878 — waivers, warranty cards, receipts, IDs)
    implementation(libs.gms.document.scanner)

    // ML Kit (Text recognition — on-device receipt OCR, no Firebase)
    implementation(libs.mlkit.text.recognition)

    // Firebase (Push notifications)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging.ktx)

    // Image loading
    implementation(libs.coil3.compose)
    implementation(libs.coil3.network.okhttp)

    // Charts
    implementation(libs.vico.compose.m3)

    // Security (encrypted prefs)
    implementation(libs.androidx.security.crypto)

    // Biometric quick-unlock (used by ui/auth/BiometricAuth.kt).
    // The 1.2.0-alpha pre-release is required for BIOMETRIC_STRONG +
    // DEVICE_CREDENTIAL fallback; 1.1.0 stable does not expose the combined
    // authenticator flag used by BiometricAuth.canAuthenticate / showPrompt.
    implementation(libs.androidx.biometric)

    // Gson
    implementation(libs.gson)

    // Splash screen
    implementation(libs.androidx.core.splashscreen)

    // Pull to refresh
    implementation(libs.androidx.compose.material3)

    // DataStore (for simple prefs)
    implementation(libs.androidx.datastore.preferences)

    // Timber (structured logging, RedactorTree wraps this)
    implementation(libs.timber)

    // ZXing — pure-JVM QR encoder used by QrCodeGenerator to render 2FA enroll QR
    // codes on-device without a network round-trip. No Android view dependency.
    implementation(libs.zxing.core)

    // SMS Retriever — reads the incoming OTP SMS without READ_SMS permission.
    // Used by SmsRetrieverHelper + SmsOtpBroadcastReceiver to autofill the
    // TwoFaVerifyStep field (§2.4 L302).
    implementation(libs.play.services.auth.api.phone)

    // §1.6 / §24 Glance — Compose-based home-screen widgets (plan:L225, plan:L2316).
    // glance-appwidget provides GlanceAppWidget + GlanceAppWidgetReceiver.
    // glance-material3 provides GlanceMaterialTheme + M3 colour token bindings.
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)

    // §2.20 L441 — Chrome Custom Tabs for SSO / SAML / OIDC browser-based auth.
    // androidx.browser 1.8.0 ships CustomTabsIntent + CustomTabColorSchemeParams.
    implementation(libs.androidx.browser)

    // §2.22 / §2.23 L463-L481 — Credential Manager: passkeys + hardware-key (FIDO2).
    // Requires minSdk 26 (already set); CredentialManager APIs are API-28-gated in code.
    // credentials-play-services-auth bridges to Google Play Services FIDO on devices
    // that use the Play Services FIDO2 stack (API 28–33 on some OEMs).
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    // Note: the catalog alias `androidx-credentials-play-services-auth` maps to
    // libs.androidx.credentials.play.services.auth in the Kotlin DSL accessor.

    // §28 L2532 — Play Integrity API (device attestation, non-blocking on non-GMS)
    implementation(libs.play.integrity)

    // Phase 4 — BlockChyp Android SDK decision:
    // BlockChyp does not publish a standalone Android AAR on Maven Central.
    // The Java SDK (com.blockchyp:blockchyp-java) is a pure-Java library that
    // technically works on Android but pulls in a large set of transitive deps
    // (Apache HttpClient, Bouncy Castle) that conflict with OkHttp + the
    // Android TLS stack and add 3+ MB to the APK. The server side already has
    // the full SDK (packages/server/src/services/blockchyp.ts). The Android
    // app is a thin client that proxies all terminal calls through the CRM
    // server via BlockChypApi (Retrofit) + BlockChypClient. No SDK dep needed.

    // §51.4 — zip4j: AES-256 encrypted ZIP for optional password protection of
    // exported data archives. Pure-Java; no native code; no network egress.
    // Password is never transmitted — encryption happens locally before the
    // file is written to the SAF URI the user chose.
    implementation(libs.zip4j)

    // §20.12 — LeakCanary: debug-only heap-leak detector. Automatically no-op on
    // release builds (LeakCanary ships a release no-op artifact automatically;
    // debugImplementation ensures it is only included in debug APKs).
    debugImplementation(libs.leakcanary.android)

    // §1.6 Custom lint rules — stateful object singleton + GlobalScope.launch ban (plan:L224)
    lintChecks(project(":lint-rules"))

    // Paging 3 — cursor-based pagination + RemoteMediator (plan:L632-L635)
    implementation(libs.androidx.paging.runtime)
    implementation(libs.androidx.paging.compose)
    implementation(libs.androidx.room.paging)

    // Testing — unit test baseline
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    // BOM must be re-declared for androidTest scope — it does not inherit from
    // the implementation BOM. Without this the ui-test-junit4 version is blank.
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)

    // §1.6 Hilt @TestInstallIn scaffold (plan:L223)
    // hilt-android-testing provides @HiltAndroidTest, HiltAndroidRule, @TestInstallIn.
    testImplementation(libs.hilt.android.testing)
    kspTest(libs.hilt.android.compiler.test)
    // androidx.test runner — required by HiltAndroidRule for component injection.
    testImplementation(libs.androidx.test.runner)
    // InstantTaskExecutorRule for LiveData assertions in unit tests.
    testImplementation(libs.androidx.arch.core.testing)
    // TestDispatcher / runTest for deterministic coroutine testing.
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.androidx.paging.testing)
}

// §32.1 — data-sovereignty Gradle guard rail.
//
// FCM is the only Firebase module we permit (opaque push transport). Any
// other Firebase dependency pulls in Google-side telemetry we explicitly
// do not want (Crashlytics / Analytics / Performance / Remote Config /
// App Check). Fail the build loudly if a rogue module slips in, so a
// future dependency-upgrade script can't silently widen our egress.
val forbiddenFirebaseModules = setOf(
    "firebase-crashlytics",
    "firebase-crashlytics-ktx",
    "firebase-crashlytics-ndk",
    "firebase-analytics",
    "firebase-analytics-ktx",
    "firebase-perf",
    "firebase-perf-ktx",
    "firebase-config",
    "firebase-config-ktx",
    "firebase-appcheck",
    "firebase-appcheck-playintegrity",
)
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "com.google.firebase" && requested.name in forbiddenFirebaseModules) {
            throw GradleException(
                "§32.1 violation — ${requested.group}:${requested.name} is banned. " +
                "Only firebase-messaging is permitted (opaque push transport). " +
                "Remove the dependency or add an explicit exception here.",
            )
        }
    }
}
