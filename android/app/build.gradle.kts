plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

// Keystore dir: ../open-tspk-app-ks from project root (same as CI where workflow uses ../open-tspk-app-ks)
// rootProject.projectDir = android/ -> parentFile = project root -> parentFile = repo parent -> resolve("open-tspk-app-ks")
val keystoreDir = rootProject.projectDir.parentFile.parentFile.resolve("open-tspk-app-ks")

// Load keystore properties from keystore dir, or from CI/CD environment variables (for GitHub Actions)
val keystoreProperties = Properties()
val keystorePropertiesFile = keystoreDir.resolve("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    // Fallback to environment variables (for CI/CD)
    keystoreProperties["storePassword"] = System.getenv("ANDROID_STORE_PASSWORD") ?: ""
    keystoreProperties["keyPassword"] = System.getenv("ANDROID_KEY_PASSWORD") ?: System.getenv("ANDROID_STORE_PASSWORD") ?: ""
    keystoreProperties["keyAlias"] = System.getenv("ANDROID_KEY_ALIAS") ?: "upload"
    keystoreProperties["storeFile"] = System.getenv("ANDROID_STORE_FILE") ?: "thygeson-app.keystore"
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
            // Determine keystore file path (same keystoreDir as key.properties)
            val storeFileName = keystoreProperties["storeFile"] as String? ?: "thygeson-app.keystore"
            val keystoreFile = keystoreDir.resolve(storeFileName)
            
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
            // Disable minification to prevent ProGuard/R8 issues with flutter_local_notifications
            // The plugin uses reflection which requires generic type information that gets stripped
            isMinifyEnabled = false
            isShrinkResources = false
            
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
