import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Signature release : en build local (aucune variable d'env), on retombe sur
// la clé debug pour que `flutter run --release` fonctionne. En CI, le
// workflow release.yml fournit la vraie clé de production via les variables
// d'environnement YELE_KEYSTORE_* (secrets GitHub : la clé n'est jamais
// dans le dépôt ; l'empreinte publique du certificat est consignée dans
// credentials/keystore-fingerprint.txt pour vérifier l'APK signé).
val yeleKeystorePath = System.getenv("YELE_KEYSTORE_PATH")
val yeleKeystorePass = System.getenv("YELE_KEYSTORE_PASSWORD")
val yeleKeyAlias = System.getenv("YELE_KEY_ALIAS")
val yeleSignFromEnv = !yeleKeystorePath.isNullOrBlank() && File(yeleKeystorePath).exists()

android {
    namespace = "com.yele.mobilefront"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.yele.mobilefront"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (yeleSignFromEnv) {
            create("yeleRelease") {
                storeFile = file(yeleKeystorePath!!)
                storePassword = yeleKeystorePass
                keyAlias = yeleKeyAlias
                keyPassword = yeleKeystorePass
            }
        }
    }

    buildTypes {
        release {
            // Signature : clé de production si fournie par l'environnement
            // (CI), sinon clé debug en local (comportement Flutter par défaut).
            signingConfig = if (yeleSignFromEnv) {
                signingConfigs.getByName("yeleRelease")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8 : retire le code Java/Kotlin non atteint et renomme le reste.
            // Les règles de conservation sont dans proguard-rules.pro — les
            // plugins (WebView, geolocator…) passent par la réflexion et
            // seraient supprimés à tort sans elles.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
