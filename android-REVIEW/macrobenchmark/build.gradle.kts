// §29.8 — Macrobenchmark module (scaffold — NOT included in normal CI builds).
//
// To enable:
//   1. Uncomment `include(":macrobenchmark")` in settings.gradle.kts.
//   2. Connect a physical device or start an API-29+ AVD (Macrobenchmark
//      does not support the emulator for timing measurements on all hosts).
//   3. Run:  ./gradlew :macrobenchmark:connectedAndroidTest \
//              -Pandroid.testInstrumentationRunnerArguments.class=\
//              com.bizarreelectronics.crm.macrobenchmark.StartupBenchmark
//
// Benchmark results are written to
//   macrobenchmark/build/outputs/connected_android_test_additional_output/
// and to a JSON file consumable by the Macrobenchmark CI workflow step.
//
// BaselineProfileGenerator (separate class in this module) produces a
// baseline-prof.txt that can be copied to app/src/main/ and committed.
//
// NOTE: This module requires AGP 8.2+ and a physical device or API-34 AVD.
// The ":app" build variant used must be "release" or a dedicated benchmark
// variant with minification enabled (so ART AOT compilation is exercised).

plugins {
    alias(libs.plugins.android.test)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.bizarreelectronics.crm.macrobenchmark"
    compileSdk = 36

    defaultConfig {
        minSdk = 29   // Macrobenchmark requires API 29+
        targetSdk = 35
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Target the :app module for profiling.
        testInstrumentationRunnerArguments["androidx.benchmark.suppressErrors"] = "EMULATOR,LOW-BATTERY,UNLOCKED"
    }

    buildTypes {
        create("benchmark") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
        }
    }

    targetProjectPath = ":app"
    experimentalProperties["android.experimental.self-instrumenting"] = true
}

androidComponents {
    beforeVariants(selector().all()) { variantBuilder ->
        // Only build the "benchmark" variant for this module.
        variantBuilder.enable = variantBuilder.buildType == "benchmark"
    }
}

dependencies {
    implementation(libs.androidx.benchmark.macro.junit4)
    implementation(libs.androidx.test.ext.junit)
    implementation(libs.androidx.test.runner)
}
