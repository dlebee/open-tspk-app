plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Load keystore properties from ../open-tspk-app-ks/key.properties
// Or from CI/CD environment variables (for GitHub Actions)
val keystoreProperties = Properties()
val keystorePropertiesFile = file("../open-tspk-app-ks/key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // Fallback to environment variables (for CI/CD)
    keystoreProperties["storePassword"] = System.getenv("ANDROID_STORE_PASSWORD") ?: ""
    keystoreProperties["keyPassword"] = System.getenv("ANDROID_KEY_PASSWORD") ?: System.getenv("ANDROID_STORE_PASSWORD") ?: ""
    keystoreProperties["keyAlias"] = System.getenv("ANDROID_KEY_ALIAS") ?: "upload"
    keystoreProperties["storeFile"] = System.getenv("ANDROID_STORE_FILE") ?: "upload-keystore.jks"
}

android {
    namespace = "com.davidlebee.thygeson"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.davidlebee.thygeson"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Determine keystore file path
            val storeFileName = keystoreProperties["storeFile"] as String? ?: "thygeson-app.keystore"
            val keystoreFile = file("../open-tspk-app-ks/$storeFileName")
            
            // Configure signing if keystore exists and password is provided
            if (keystoreFile.exists() && keystoreProperties["storePassword"] as String? != null && keystoreProperties["storePassword"] as String != "") {
                keyAlias = keystoreProperties["keyAlias"] as String? ?: "upload"
                // If keyPassword is not set, use storePassword (common case)
                keyPassword = keystoreProperties.getProperty("keyPassword") 
                    ?: keystoreProperties["storePassword"] as String
                storeFile = keystoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use release signing if configured, otherwise debug (for contributors)
            if (signingConfigs.getByName("release").storeFile != null && 
                signingConfigs.getByName("release").storeFile?.exists() == true) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
