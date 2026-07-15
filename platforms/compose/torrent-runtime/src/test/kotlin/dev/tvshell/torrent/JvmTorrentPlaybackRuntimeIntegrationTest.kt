package dev.tvshell.torrent

import com.frostwire.jlibtorrent.TorrentBuilder
import com.frostwire.jlibtorrent.TorrentHandle
import com.frostwire.jlibtorrent.TorrentInfo
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class JvmTorrentPlaybackRuntimeIntegrationTest {
    @Test
    fun verifiedNativePiecesBecomeASeekablePrivatePlayerStream() {
        val root = File(System.getProperty("java.io.tmpdir"), "tvshell-torrent-e2e-${System.nanoTime()}")
        val sourceDirectory = File(root, "source").apply { mkdirs() }
        val cacheRoot = File(root, "cache").apply { mkdirs() }
        val source = File(sourceDirectory, "episode.mp4")
        val payload = ByteArray(384 * 1024) { index -> ((index * 31 + 17) and 0xff).toByte() }
        source.writeBytes(payload)

        val info = TorrentInfo(
            TorrentBuilder()
                .path(source)
                .pieceSize(16 * 1024)
                .creator("TVShell test")
                .generate()
                .entry()
                .bencode(),
        )
        val taskID = "0123456789abcdef0123456789abcdef01234567"
        File(cacheRoot, taskID).apply { mkdirs() }
            .resolve("metadata.torrent")
            .writeBytes(info.bencode())

        val events = LinkedBlockingQueue<RuntimeTorrentEvent>()
        var runtime: JvmTorrentPlaybackRuntime? = null
        try {
            runtime = JvmTorrentPlaybackRuntime(
                cacheRoot = cacheRoot,
                listener = events::offer,
                metadataTimeoutSeconds = 2,
                selectionTimeoutSeconds = 2,
                readyHeadBytes = 64 * 1024,
                priorityHeadBytes = 64 * 1024,
                priorityTailBytes = 16 * 1024,
                inactivityTimeoutSeconds = 10,
                onHandleReady = { handle -> injectVerifiedPieces(handle, info, payload) },
            )
            runtime.start(
                generation = 1,
                taskID = taskID,
                magnet = info.makeMagnetUri(),
                title = "測試動畫",
                subtitle = "第 1 集",
            )

            val metadata = awaitEvent<RuntimeTorrentEvent.Metadata>(events)
            assertEquals(listOf("episode.mp4"), metadata.files.map(RuntimeTorrentFile::path))
            runtime.select(1, metadata.files.single().index)

            val ready = awaitEvent<RuntimeTorrentEvent.Ready>(events, timeoutSeconds = 15)
            assertTrue(ready.url.startsWith("http://127.0.0.1:"))
            assertEquals("episode.mp4", ready.selectedPath)

            val requestedStart = 123_457
            val requestedEndInclusive = 147_892
            val connection = URI(ready.url).toURL().openConnection() as HttpURLConnection
            connection.setRequestProperty("Range", "bytes=$requestedStart-$requestedEndInclusive")
            connection.connectTimeout = 2_000
            connection.readTimeout = 5_000
            assertEquals(206, connection.responseCode)
            assertEquals(
                "bytes $requestedStart-$requestedEndInclusive/${payload.size}",
                connection.getHeaderField("Content-Range"),
            )
            assertContentEquals(
                payload.copyOfRange(requestedStart, requestedEndInclusive + 1),
                connection.inputStream.use { it.readBytes() },
            )
            connection.disconnect()
        } finally {
            runtime?.close()
            root.deleteRecursively()
        }
    }

    @Test
    fun reopeningTheSameBackgroundMagnetTransfersOwnershipWithoutRemovingTheNewHandle() {
        val root = File(System.getProperty("java.io.tmpdir"), "tvshell-torrent-reopen-${System.nanoTime()}")
        val sourceDirectory = File(root, "source").apply { mkdirs() }
        val cacheRoot = File(root, "cache").apply { mkdirs() }
        val source = File(sourceDirectory, "episode.mkv")
        val payload = ByteArray(384 * 1024) { index -> ((index * 17 + 29) and 0xff).toByte() }
        source.writeBytes(payload)
        val info = TorrentInfo(
            TorrentBuilder().path(source).pieceSize(16 * 1024).creator("TVShell reopen test")
                .generate().entry().bencode(),
        )
        val taskID = "123456789abcdef0123456789abcdef012345678"
        File(cacheRoot, taskID).apply { mkdirs() }.resolve("metadata.torrent").writeBytes(info.bencode())
        val events = LinkedBlockingQueue<RuntimeTorrentEvent>()
        val handleStarts = AtomicInteger(0)
        var runtime: JvmTorrentPlaybackRuntime? = null

        try {
            runtime = JvmTorrentPlaybackRuntime(
                cacheRoot = cacheRoot,
                listener = events::offer,
                selectionTimeoutSeconds = 2,
                readyHeadBytes = 64 * 1024,
                priorityHeadBytes = 64 * 1024,
                priorityTailBytes = 16 * 1024,
                inactivityTimeoutSeconds = 10,
                onHandleReady = { handle ->
                    if (handleStarts.incrementAndGet() == 1) {
                        repeat(4) { piece -> injectPiece(handle, info, payload, piece) }
                        injectPiece(handle, info, payload, info.numPieces() - 1)
                    } else {
                        injectVerifiedPieces(handle, info, payload)
                    }
                },
            )
            runtime.start(1, taskID, info.makeMagnetUri(), "測試動畫", "第 1 集")
            runtime.select(1, awaitEvent<RuntimeTorrentEvent.Metadata>(events).files.single().index)
            awaitEvent<RuntimeTorrentEvent.Ready>(events)
            runtime.keepInBackground(1)

            runtime.start(2, taskID, info.makeMagnetUri(), "測試動畫", "第 1 集")
            val secondMetadata = awaitEvent<RuntimeTorrentEvent.Metadata>(events)
            assertEquals(2, secondMetadata.generation)
            runtime.select(2, secondMetadata.files.single().index)
            val secondReady = awaitEvent<RuntimeTorrentEvent.Ready>(events, timeoutSeconds = 15)
            assertEquals(2, secondReady.generation)
            assertEquals(2, handleStarts.get())

            val start = 200_000
            val end = 220_000
            val connection = URI(secondReady.url).toURL().openConnection() as HttpURLConnection
            connection.setRequestProperty("Range", "bytes=$start-$end")
            assertEquals(206, connection.responseCode)
            assertContentEquals(payload.copyOfRange(start, end + 1), connection.inputStream.use { it.readBytes() })
            connection.disconnect()
        } finally {
            runtime?.close()
            root.deleteRecursively()
        }
    }

    private fun injectVerifiedPieces(handle: TorrentHandle, info: TorrentInfo, payload: ByteArray) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (System.nanoTime() < deadline) {
            repeat(info.numPieces()) { piece ->
                if (!handle.havePiece(piece)) injectPiece(handle, info, payload, piece)
            }
            if ((0 until info.numPieces()).all(handle::havePiece)) return
            Thread.sleep(50)
        }
        check((0 until info.numPieces()).all(handle::havePiece)) {
            "Native test injection did not verify every piece within 30 seconds"
        }
    }

    private fun injectPiece(handle: TorrentHandle, info: TorrentInfo, payload: ByteArray, piece: Int) {
        val start = piece * info.pieceLength()
        val size = info.pieceSize(piece)
        handle.addPiece(piece, payload.copyOfRange(start, start + size))
    }

    private inline fun <reified T : RuntimeTorrentEvent> awaitEvent(
        events: LinkedBlockingQueue<RuntimeTorrentEvent>,
        timeoutSeconds: Long = 5,
    ): T {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(timeoutSeconds)
        while (System.nanoTime() < deadline) {
            val remaining = deadline - System.nanoTime()
            val event = events.poll(remaining.coerceAtLeast(1), TimeUnit.NANOSECONDS) ?: break
            if (event is RuntimeTorrentEvent.Failed) error(event.reason)
            if (event is T) return event
        }
        error("Timed out waiting for ${T::class.simpleName}")
    }
}
