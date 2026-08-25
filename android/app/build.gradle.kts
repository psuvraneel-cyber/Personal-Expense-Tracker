import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ─── Secure Release Signing Configuration Resolution ─────────────────────────
// Resolves credentials from (in priority order):
// 1. Local key.properties (android/app/key.properties or android/key.properties)
// 2. System Environment Variables (ANDROID_KEYSTORE_PATH / KEYSTORE_PATH, etc.)
// 3. Project Gradle Properties (-P command line options)

val keystoreProperties = Properties()
val keyPropertiesLocations = listOf(
    rootProject.file("app/key.properties"),
    rootProject.file("key.properties")
)
val foundKeyFile = keyPropertiesLocations.firstOrNull { it.exists() }
if (foundKeyFile != null) {
    keystoreProperties.load(FileInputStream(foundKeyFile))
}

fun resolveSigningProperty(propName: String, vararg envVarNames: String): String? {
    // 1. Check loaded key.properties
    if (keystoreProperties.containsKey(propName)) {
        val value = keystoreProperties.getProperty(propName)?.trim()
        if (!value.isNullOrEmpty()) return value
    }
    // 2. Check System Environment Variables
    for (envName in envVarNames) {
        val envVal = System.getenv(envName)?.trim()
        if (!envVal.isNullOrEmpty()) return envVal
    }
    // 3. Check Gradle project properties (-P)
    if (project.hasProperty(propName)) {
        val gradleVal = project.property(propName)?.toString()?.trim()
        if (!gradleVal.isNullOrEmpty()) return gradleVal
    }
    return null
}

val resolvedStoreFilePath = resolveSigningProperty("storeFile", "ANDROID_KEYSTORE_PATH", "KEYSTORE_PATH")
val resolvedStorePassword = resolveSigningProperty("storePassword", "ANDROID_KEYSTORE_PASSWORD", "KEYSTORE_PASSWORD")
val resolvedKeyAlias = resolveSigningProperty("keyAlias", "ANDROID_KEY_ALIAS", "KEY_ALIAS")
val resolvedKeyPassword = resolveSigningProperty("keyPassword", "ANDROID_KEY_PASSWORD", "KEY_PASSWORD")

val isReleaseSigningConfigured = !resolvedStoreFilePath.isNullOrEmpty() &&
        !resolvedStorePassword.isNullOrEmpty() &&
        !resolvedKeyAlias.isNullOrEmpty() &&
        !resolvedKeyPassword.isNullOrEmpty()

android {
    namespace = "com.pet.tracker.pet"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.pet.tracker.pet"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (isReleaseSigningConfigured) {
            create("release") {
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
                storeFile = file(resolvedStoreFilePath!!)
                storePassword = resolvedStorePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            if (isReleaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                val requestedTasks = gradle.startParameter.taskNames.map { it.lowercase() }
                val isReleaseBuildRequested = requestedTasks.any { 
                    it.contains("release") || it.contains("bundle")
                }

                if (isReleaseBuildRequested) {
                    throw GradleException(
                        """
                        |
                        |================================================================================
                        | RELEASE BUILD SECURITY ERROR: Missing Android Release Signing Credentials
                        |================================================================================
                        | Production release builds require signing credentials to guarantee APK identity.
                        | None were configured.
                        |
                        | Please configure release credentials using one of the following methods:
                        |
                        | 1. Local key.properties file (at 'android/app/key.properties' or 'android/key.properties'):
                        |    storeFile=<path-to-keystore>
                        |    storePassword=<store-password>
                        |    keyAlias=<key-alias>
                        |    keyPassword=<key-password>
                        |    (See android/key.properties.example for reference template)
                        |
                        | 2. Environment Variables (CI/CD pipelines):
                        |    ANDROID_KEYSTORE_PATH (or KEYSTORE_PATH)
                        |    ANDROID_KEYSTORE_PASSWORD (or KEYSTORE_PASSWORD)
                        |    ANDROID_KEY_ALIAS (or KEY_ALIAS)
                        |    ANDROID_KEY_PASSWORD (or KEY_PASSWORD)
                        |
                        | 3. Gradle Command-Line Properties (-P):
                        |    ./gradlew assembleRelease -PstoreFile=... -PstorePassword=... -PkeyAlias=... -PkeyPassword=...
                        |================================================================================
                        """.trimMargin()
                    )
                } else {
                    signingConfig = signingConfigs.getByName("debug")
                }
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.annotation:annotation:1.7.0")
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.11.0")
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.2.1")
    testImplementation("org.robolectric:robolectric:4.11.1")
    testImplementation("androidx.test:core:1.5.0")
}

flutter {
    source = "../.."
}
