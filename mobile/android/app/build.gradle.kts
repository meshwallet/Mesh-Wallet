plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.mesh.wallet"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mesh.wallet"
        minSdk = 26
        targetSdk = 35
        versionCode = 18
        versionName = "1.1.7"

        buildConfigField("String", "TRONGRID_BASE_URL", "\"https://api.trongrid.io\"")
        buildConfigField("String", "USDT_CONTRACT", "\"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t\"")
        buildConfigField("String", "RELAY_URL", "\"https://mesh-sponsorship-relay.meshwallet.workers.dev\"")
        buildConfigField("String", "RELAY_AUTH", "\"\"")
        buildConfigField("String", "FEE_TREASURY", "\"TWorKRZ5B1awmuHcmprsbTvGJrSSzEbdmd\"")
        buildConfigField("String", "SEND_ROUTER", "\"TTDAmwJuKWkhjBjkEt3RGej22z1aJagLYK\"")
        buildConfigField("String", "TRONGRID_API_KEYS", "\"\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")

    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")

    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    implementation("com.trustwallet:wallet-core:4.6.9")

    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("androidx.compose.material3:material3:1.3.1")

    implementation("androidx.camera:camera-camera2:1.4.1")
    implementation("androidx.camera:camera-lifecycle:1.4.1")
    implementation("androidx.camera:camera-view:1.4.1")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("com.google.zxing:core:3.5.3")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
