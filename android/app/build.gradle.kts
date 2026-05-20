import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) load(FileInputStream(file))
}

android {
    namespace = "com.filestech.health_tech"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        // Genere BuildConfig.DEBUG pour gater les Log.w cote Kotlin :
        // sans cela, AGP 8+ ne genere plus BuildConfig par defaut.
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications: AlarmManager APIs use
        // java.time / Instant which need core library desugaring on API < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.filestech.health_tech"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("fr", "en")
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        getByName("debug") {
            applicationIdSuffix = ".debug"
            isDebuggable = true
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            // v1.7.1 (H3 audit) — passé à `false` pour aligner Health Tech sur
            // la doctrine portfolio Files Tech (Pass / Notes / PDF / RFT / SMS
            // Tech sont tous à `false`). Un APK universel embarque les 3 .so
            // SQLCipher (~30 Mo cumulés inutiles) et gonfle la release. Les
            // 3 splits ABI restent générés via `flutter build apk --release
            // --split-per-abi`. Sur F-Droid (cible future), le build from
            // source compilera son universel à part — ne pas confondre le
            // canal F-Droid (universel via build infra) avec le canal GH
            // Releases (3 splits per-arch).
            isUniversalApk = false
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // BiometricPrompt + CryptoObject — used to wrap the VEK with a
    // Keystore key bound to user authentication. Required by
    // BiometricBridge.kt.
    implementation("androidx.biometric:biometric:1.1.0")

    // Core library desugaring runtime — pairs with the
    // `isCoreLibraryDesugaringEnabled = true` flag above so that
    // flutter_local_notifications can use java.time APIs on API < 26.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
