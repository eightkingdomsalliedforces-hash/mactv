import org.jetbrains.compose.desktop.application.dsl.TargetFormat

val javafxPlatform = when {
    System.getProperty("os.name").startsWith("Windows", ignoreCase = true) -> "win"
    System.getProperty("os.name").startsWith("Mac", ignoreCase = true) && System.getProperty("os.arch") == "aarch64" -> "mac-aarch64"
    System.getProperty("os.name").startsWith("Mac", ignoreCase = true) -> "mac"
    System.getProperty("os.arch") == "aarch64" -> "linux-aarch64"
    else -> "linux"
}

val jlibtorrentVersion = "2.0.12.9"
val tvShellBuildNumber = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull()?.coerceIn(1, 65_535) ?: 1
val tvShellPackageVersion = System.getenv("GITHUB_REF_NAME")
    ?.removePrefix("v")
    ?.takeIf { it.matches(Regex("\\d+\\.\\d+\\.\\d+")) }
    ?: if (System.getenv("GITHUB_RUN_NUMBER") != null) "1.0.$tvShellBuildNumber" else "1.0.0"
val jlibtorrentDesktopArtifact = when {
    System.getProperty("os.name").startsWith("Windows", ignoreCase = true) -> "jlibtorrent-windows"
    System.getProperty("os.name").startsWith("Mac", ignoreCase = true) && System.getProperty("os.arch") == "aarch64" -> "jlibtorrent-macosx-arm64"
    System.getProperty("os.name").startsWith("Mac", ignoreCase = true) -> "jlibtorrent-macosx-x86_64"
    System.getProperty("os.arch") == "aarch64" -> "jlibtorrent-linux-arm64"
    else -> "jlibtorrent-linux-x86_64"
}

plugins {
    kotlin("multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    androidLibrary {
        namespace = "dev.tvshell.shared"
        compileSdk = 36
        minSdk = 26
    }
    jvm("desktop")

    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.compose.runtime:runtime:1.11.1")
            implementation("org.jetbrains.compose.foundation:foundation:1.11.1")
            implementation("org.jetbrains.compose.material:material:1.11.1")
            implementation("org.jetbrains.compose.ui:ui:1.11.1")
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        val desktopMain by getting {
            dependencies {
                implementation(project(":torrent-runtime"))
                implementation("com.frostwire:$jlibtorrentDesktopArtifact:$jlibtorrentVersion")
                implementation(compose.desktop.currentOs)
                implementation("org.jsoup:jsoup:1.21.2")
                implementation("net.java.dev.jna:jna:5.19.1")
                implementation("org.openjfx:javafx-base:21.0.6:$javafxPlatform")
                implementation("org.openjfx:javafx-graphics:21.0.6:$javafxPlatform")
                implementation("org.openjfx:javafx-controls:21.0.6:$javafxPlatform")
                implementation("org.openjfx:javafx-media:21.0.6:$javafxPlatform")
                implementation("org.openjfx:javafx-web:21.0.6:$javafxPlatform")
                implementation("org.openjfx:javafx-swing:21.0.6:$javafxPlatform")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation(project(":torrent-runtime"))
                implementation("androidx.media3:media3-exoplayer:1.10.1")
                implementation("androidx.media3:media3-exoplayer-hls:1.10.1")
                implementation("androidx.media3:media3-exoplayer-dash:1.10.1")
                implementation("com.frostwire:jlibtorrent-android-arm:$jlibtorrentVersion")
                implementation("com.frostwire:jlibtorrent-android-arm64:$jlibtorrentVersion")
                implementation("com.frostwire:jlibtorrent-android-x86:$jlibtorrentVersion")
                implementation("com.frostwire:jlibtorrent-android-x86_64:$jlibtorrentVersion")
                implementation("org.jsoup:jsoup:1.21.2")
            }
        }
    }
}

compose.desktop {
    application {
        mainClass = "dev.tvshell.desktop.MainKt"
        nativeDistributions {
            appResourcesRootDir.set(rootProject.layout.projectDirectory.dir("package-resources"))
            targetFormats(TargetFormat.Msi, TargetFormat.Exe)
            packageName = "TVShell"
            packageVersion = tvShellPackageVersion
            description = "TVShell for Windows"
            vendor = "TVShell"
            windows {
                iconFile.set(project.file("../../../assets/icons/TVShell.ico"))
                menuGroup = "TVShell"
                upgradeUuid = "45aef48e-4a19-52e5-98e8-8376a35d5bd9"
            }
        }
    }
}
