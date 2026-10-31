import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives in android/key.properties, which is gitignored along with
// the keystore it points at. A checkout without it can still build a debug APK; a
// *release* build stops instead, because one signed with the debug key installs
// happily on a fresh phone and is then refused as an update by every phone that
// already has the app - Android treats the signing key, not the package name, as
// the app's identity. The bottom of this file is where that is enforced.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

// Escape hatch for a machine that has to produce a throwaway APK and knows what it
// is giving up: -PreiptvAllowDebugSigning=true.
val allowDebugSigning =
    (project.findProperty("reiptvAllowDebugSigning") as String?)?.toBoolean() ?: false

android {
    namespace = "com.reiptv.re_iptv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.reiptv.re_iptv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The real key when it is there. Without it the debug key is configured
            // only so the build can be configured at all; assembling a release then
            // fails, unless -PreiptvAllowDebugSigning was passed.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// A release build with no key.properties is refused here rather than signed with the
// debug key. The release build type has to be configured either way, so the check
// waits for the task graph: nothing has been compiled yet, and only a task that would
// actually produce a release artefact can trip it, so `flutter run` and
// `flutter build apk --debug` keep working on a checkout with no key at all.
gradle.taskGraph.whenReady {
    val producesRelease = allTasks.any { task ->
        (task.name.startsWith("assemble") || task.name.startsWith("bundle")) &&
            task.name.endsWith("Release")
    }
    if (producesRelease && !keystorePropertiesFile.exists() && !allowDebugSigning) {
        throw GradleException(
            "android/key.properties is missing, so this release build has no key to sign with. " +
                "Copy app/android/key.properties.example to app/android/key.properties and fill " +
                "it in, as README - Release signing describes. Signing with the debug " +
                "key instead would give you an APK that installs on a fresh phone and is then " +
                "refused as an update by any phone that already has the app. Pass " +
                "-PreiptvAllowDebugSigning=true to do that deliberately.",
        )
    }
}
