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

    // v1.8.1 (hotfix CI) — bloc `splits.abi` retiré. Cause : Flutter 3.41+
    // pose `ndk.abiFilters` (3 ABIs) automatiquement quand le CI fait
    // `flutter build apk --debug` (sans `--split-per-abi`), ce qui rentre
    // en conflit avec `splits.abi.include(...)` configuré ici :
    //   `Conflicting configuration : 'armeabi-v7a,arm64-v8a,x86_64' in ndk
    //    abiFilters cannot be present when splits abi filters are set`.
    // Hotfix portfolio-aligné avec AI Tech `e7a05d4`, PDF Tech `f4f2b35`
    // et RFT v2.13.1. Pour générer les 3 splits ABI release, passer le
    // flag explicite : `flutter build apk --release --split-per-abi`.

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
