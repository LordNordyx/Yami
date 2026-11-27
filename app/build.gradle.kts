plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.lordnordyx.yami"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.lordnordyx.yami"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    // Stable signing so updates install over the previous version. CI writes the
    // keystore from the YAMI_KEYSTORE_B64 secret; without it, builds use the debug key.
    val ksFile = System.getenv("YAMI_KEYSTORE_FILE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (ksFile != null) create("yami") {
            storeFile = ksFile
            storePassword = System.getenv("YAMI_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("YAMI_KEY_ALIAS") ?: "yami"
            keyPassword = System.getenv("YAMI_KEY_PASSWORD") ?: System.getenv("YAMI_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        debug {
            if (ksFile != null) signingConfig = signingConfigs.getByName("yami")
        }
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (ksFile != null) "yami" else "debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }

    lint {
        // SDL's upstream Java (HIDAPI/BLE) trips MissingPermission; don't block builds on it.
        abortOnError = false
        checkReleaseBuilds = false
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
}
