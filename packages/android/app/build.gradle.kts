import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.bizarreelectronics.crm"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.bizarreelectronics.crm"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Default server URL — users can override with custom host in the app
        buildConfigField("String", "SERVER_URL", "\"https://bizarrecrm.com\"")
    }

    // Release signing config — keystore is read from a properties file outside
    // the project tree (~/.android-keystores/bizarrecrm-release.properties).
    // Falls back to debug signing if the file is missing, so CI / fresh clones
    // can still build.
    val releaseKeystorePropsFile = file(System.getProperty("user.home") + "/.android-keystores/bizarrecrm-release.properties")
    val releaseKeystoreProps = Properties()
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
            buildConfigField("String", "SERVER_URL", "\"https://bizarrecrm.com\"")
        }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "SERVER_URL", "\"https://bizarrecrm.com\"")
            // Use the release signing config if the keystore properties file exists,
            // otherwise fall back to the default debug signing config.
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
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    // Core Android
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.10.0")

    // Compose + Material 3
    implementation(platform("androidx.compose:compose-bom:2025.03.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.8.6")

    // Room (SQLite)
    implementation("androidx.room:room-runtime:2.7.0")
    implementation("androidx.room:room-ktx:2.7.0")
    ksp("androidx.room:room-compiler:2.7.0")

    // SQLCipher — encrypts customer PII at rest. Wired into Room via
    // SupportFactory in di/DatabaseModule.kt. The passphrase is a per-install
    // random 32 bytes persisted in EncryptedSharedPreferences (see
    // data/local/prefs/DatabasePassphrase.kt).
    implementation("net.zetetic:sqlcipher-android:4.6.1")
    implementation("androidx.sqlite:sqlite-ktx:2.4.0")

    // Hilt (Dependency Injection)
    implementation("com.google.dagger:hilt-android:2.53")
    ksp("com.google.dagger:hilt-compiler:2.53")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")
    implementation("androidx.hilt:hilt-work:1.2.0")
    ksp("androidx.hilt:hilt-compiler:1.2.0")

    // Retrofit + OkHttp (Networking)
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-gson:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // WorkManager (Background Sync)
    implementation("androidx.work:work-runtime-ktx:2.10.0")

    // CameraX (Photo capture)
    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")

    // ML Kit (Barcode scanning)
    implementation("com.google.mlkit:barcode-scanning:17.3.0")

    // Firebase (Push notifications)
    implementation(platform("com.google.firebase:firebase-bom:33.8.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")

    // Image loading
    implementation("io.coil-kt.coil3:coil-compose:3.1.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.1.0")

    // Charts
    implementation("com.patrykandpatrick.vico:compose-m3:2.0.1")

    // Security (encrypted prefs)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Biometric quick-unlock (used by ui/auth/BiometricAuth.kt).
    // The 1.2.0-alpha pre-release is required for BIOMETRIC_STRONG +
    // DEVICE_CREDENTIAL fallback; 1.1.0 stable does not expose the combined
    // authenticator flag used by BiometricAuth.canAuthenticate / showPrompt.
    implementation("androidx.biometric:biometric:1.2.0-alpha05")

    // Gson
    implementation("com.google.code.gson:gson:2.11.0")

    // Splash screen
    implementation("androidx.core:core-splashscreen:1.0.1")

    // Pull to refresh
    implementation("androidx.compose.material3:material3")

    // DataStore (for simple prefs)
    implementation("androidx.datastore:datastore-preferences:1.1.2")

    // Testing
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
