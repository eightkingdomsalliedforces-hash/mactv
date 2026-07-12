import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

dependencies {
    implementation(project(":shared-ui"))
    implementation(compose.desktop.currentOs)
}

compose.desktop {
    application {
        mainClass = "dev.tvshell.anime.desktop.MainKt"
        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Exe)
            packageName = "TVShell Anime"
            packageVersion = "1.0.0"
            description = "TVShell Anime for Windows"
            vendor = "TVShell"
            windows {
                iconFile.set(project.file("../../assets/icons/TVShell-Anime.ico"))
                menuGroup = "TVShell"
                upgradeUuid = "0475a205-1fbd-51f3-979b-b3be88f4491a"
            }
        }
    }
}
