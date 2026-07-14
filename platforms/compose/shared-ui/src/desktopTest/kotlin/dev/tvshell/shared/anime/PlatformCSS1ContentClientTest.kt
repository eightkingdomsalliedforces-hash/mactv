package dev.tvshell.shared.anime

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import java.io.File
import kotlin.io.path.createTempDirectory
import dev.tvshell.shared.AnimeSourceSettings
import dev.tvshell.shared.ShellPreferences

class PlatformCSS1ContentClientTest {
    @Test
    fun fullWindowsShellUsesThePersistedCss1SubscriptionInsteadOfTheEmptyDefaultAdapter() {
        val service = DesktopAnimeService {
            ShellPreferences(animeSources = AnimeSourceSettings("https://example.com/windows-css1.json"))
        }

        assertEquals("https://example.com/windows-css1.json", service.css1SubscriptionURL)
        assertTrue(service.capabilities.css1)
        assertTrue(service.capabilities.danmaku)
        assertTrue(service.capabilities.internalPlayer)
    }

    @Test
    fun windowsMediaProxyRewritesHlsSegmentsAndEncryptionKeysThroughTheHeaderAwareEndpoint() {
        val rewritten = DesktopMediaPlaylistRewriter.rewrite(
            """#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin"
segments/001.ts
""",
            "https://media.example/show/master.m3u8",
        ) { "proxy://${it}" }

        assertTrue(rewritten.contains("proxy://https://media.example/show/keys/key.bin"))
        assertTrue(rewritten.contains("proxy://https://media.example/show/segments/001.ts"))
    }
    @Test
    fun windowsCredentialImportPersistsAValidatedCookieFile() {
        val root = createTempDirectory("tvshell-credentials-").toFile()
        try {
            val source = File(root, "cookies.txt").apply {
                writeText(""".bilibili.com	TRUE	/	TRUE	2147483647	SESSDATA	session
.bilibili.com	TRUE	/	FALSE	2147483647	bili_jct	csrf
.bilibili.com	TRUE	/	FALSE	2147483647	DedeUserID	123""")
            }
            val destination = File(root, "installed/credentials.txt")

            val credentials = platformInstallCredentials(source, destination)

            assertTrue(credentials.bilibiliCookie.contains("SESSDATA=session"))
            assertTrue(destination.isFile)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun dandanplaySignatureMatchesTheNativeMacImplementation() {
        assertEquals(
            "oykjtAeMjRLO9sAerNa9hMyQZqFdBcWneI/ED4BerSQ=",
            platformSHA256Base64("app1231735660800/api/v2/comment/123450001secret456"),
        )
    }

    @Test
    fun cssSelectorsReadOnlyTheConfiguredSearchAndEpisodeAnchors() {
        val client = PlatformCSS1ContentClient()
        val html = """
            <main><div class="result"><a href="/show/1"><span>葬送的芙莉蓮</span></a></div>
            <a href="/metadata">豆瓣評分</a>
            <div class="playlist"><a href="/play/1">第 1 集</a><a href="/play/2">第 2 集</a></div></main>
        """.trimIndent()

        assertEquals(
            listOf(CSS1Anchor("葬送的芙莉蓮", "https://source.example/show/1")),
            client.anchors(html, ".result a", "https://source.example/search"),
        )
        val block = client.blocks(html, ".playlist").single()
        assertEquals(listOf(1, 2), client.anchors(block, "a", "https://source.example/show/1").map {
            it.title.filter(Char::isDigit).toInt()
        })
    }
}
