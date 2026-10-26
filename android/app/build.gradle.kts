import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (push) is optional. The google-services plugin fails the build when
// google-services.json has no client for this applicationId, so it is applied only
// when the file matches. Without it the app runs fine and push is simply off
// (calls are then found by polling). See PLAY_STORE.md for the Firebase TODO.
val appId = "com.badeel.servepos.waiter"

// Local test build: flutter build apk --release --dart-define=LOCAL_TEST=true -PlocalTest=true
// Installs beside the real app (".test" id, "ServePOS Waiter TEST" label) and may talk plain
// http to a server on the office network. Never upload this build to Google Play.
val localTest = project.hasProperty("localTest")
val googleServices = file("google-services.json")
if (googleServices.exists() && googleServices.readText().contains("\"$appId\"")) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "WARNING: android/app/google-services.json has no Android client for $appId. " +
            "Building WITHOUT Firebase: push notifications are disabled."
    )
}

// Release signing: android/key.properties (never committed). See key.properties.example.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    logger.warn(
        "WARNING: android/key.properties not found. The release build will be signed with the " +
            "DEBUG key and cannot be uploaded to Google Play. Copy key.properties.example to " +
            "key.properties and fill in the upload keystore details."
    )
}

android {
    namespace = "com.badeel.servepos.waiter"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = appId
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (localTest) {
            applicationIdSuffix = ".test"
            versionNameSuffix = "-test"
        }
        manifestPlaceholders["appLabel"] = if (localTest) "ServePOS Waiter TEST" else "ServePOS Waiter"
        manifestPlaceholders["netConfig"] = if (localTest) "@xml/network_security_config_local_test" else "@xml/network_security_config"
        manifestPlaceholders["cleartext"] = if (localTest) "true" else "false"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
