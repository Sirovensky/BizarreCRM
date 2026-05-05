pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "BizarreCRM"
include(":app")
include(":lint-rules")
// §29.8 — Macrobenchmark module scaffold.
// Disabled by default in normal builds; CI enables it via -Pmacrobenchmark=true.
// Uncomment the line below once the module's build.gradle.kts is finalized and
// a physical/virtual device is available in CI.
// include(":macrobenchmark")
