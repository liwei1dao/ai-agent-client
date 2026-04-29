import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// device_jieli 的 4 个 AAR (jl_bluetooth_rcsp / jl_audio_decode / jl_audio_v2 /
// jldecryption) 在子模块里是 compileOnly，宿主 app 必须 runtime implementation 才会
// 被打进 APK（参见 local_plugins/device_jieli/android/build.gradle 注释）。
repositories {
    flatDir {
        dirs("../../local_plugins/device_jieli/android/libs")
    }
}

android {
    namespace = "com.nicetoo.agents"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.nicetoo.agents"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 杰理 RCSP / 音频解码 / 解密 SDK；device_jieli 子模块只 compileOnly，
    // 宿主必须 implementation 才能在运行时找到 com.jieli.bluetooth.* 等类。
    implementation(":jl_bluetooth_rcsp_V4.2.0_beta2_40214_20251224@aar")
    implementation(":jl_audio_decode_V2.1.0_20012-release@aar")
    implementation(":jl_audio_v2_V1.0.0_9-release@aar")
    implementation(":jldecryption_v0.4-release@aar")
    // jieli SDK 内部依赖
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
