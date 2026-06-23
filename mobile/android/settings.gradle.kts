import java.util.Properties

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.10.0"
}

val localProperties = Properties().apply {
    val file = file("local.properties")
    if (file.exists()) load(file.inputStream())
}

val gprUser = localProperties.getProperty("gpr.user")
    ?: System.getenv("GITHUB_USER")
    ?: ""
val gprKey = localProperties.getProperty("gpr.key")
    ?: System.getenv("GITHUB_TOKEN")
    ?: ""

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        mavenLocal()
        maven {
            name = "GitHubPackagesTrustWallet"
            url = uri("https://maven.pkg.github.com/trustwallet/wallet-core")
            credentials {
                username = gprUser
                password = gprKey
            }
            content {
                includeGroup("com.trustwallet")
            }
        }
    }
}

if (gprUser.isBlank() || gprKey.isBlank()) {
    logger.warn(
        """
        
        Trust Wallet Core requires GitHub Packages credentials.
        Run:  ./scripts/setup-trustwallet.sh YOUR_GITHUB_USERNAME YOUR_TOKEN
        Or add gpr.user and gpr.key to local.properties (see local.properties.example).
        
        """.trimIndent()
    )
}

rootProject.name = "Mesh Wallet"
include(":app")
