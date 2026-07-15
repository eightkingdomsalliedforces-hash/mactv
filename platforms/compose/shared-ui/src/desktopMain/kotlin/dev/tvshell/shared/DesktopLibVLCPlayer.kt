package dev.tvshell.shared

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.NativeLibrary
import com.sun.jna.Pointer
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.AnimePlaybackSnapshot
import java.awt.BorderLayout
import java.awt.Canvas
import java.awt.Color
import java.awt.EventQueue
import java.awt.event.HierarchyEvent
import java.io.Closeable
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import javax.swing.JPanel

internal object DesktopLibVLCLocator {
    fun locate(
        osName: String = System.getProperty("os.name").orEmpty(),
        explicitDirectory: File? = System.getenv("TVSHELL_VLC_DIR")?.takeIf(String::isNotBlank)?.let(::File),
        resourcesDirectory: File? = System.getProperty("compose.application.resources.dir")?.takeIf(String::isNotBlank)?.let(::File),
        executableDirectory: File? = ProcessHandle.current().info().command().orElse(null)?.let(::File)?.parentFile,
        programFilesDirectory: File? = System.getenv("ProgramFiles")?.takeIf(String::isNotBlank)?.let(::File),
    ): File? {
        if (!osName.startsWith("Windows", ignoreCase = true)) return null
        return listOfNotNull(
            explicitDirectory,
            resourcesDirectory?.let { File(it, "vlc") },
            executableDirectory?.let { File(it, "vlc") },
            executableDirectory?.let { File(it, "resources/vlc") },
            programFilesDirectory?.let { File(it, "VideoLAN/VLC") },
        ).distinctBy { runCatching { it.canonicalPath }.getOrDefault(it.absolutePath) }
            .firstOrNull(::isCompleteRuntime)
    }

    private fun isCompleteRuntime(directory: File): Boolean =
        File(directory, "libvlc.dll").isFile &&
            File(directory, "libvlccore.dll").isFile &&
            File(directory, "plugins").isDirectory
}

internal class DesktopLibVLCPlayer private constructor(
    private val runtime: DesktopLibVLCRuntime,
) : Closeable {
    private val canvas = Canvas().apply { background = Color.BLACK }
    val container = JPanel(BorderLayout()).apply {
        background = Color.BLACK
        add(canvas, BorderLayout.CENTER)
    }
    private val closed = AtomicBoolean(false)
    private val playbackError = AtomicReference<String?>(null)
    @Volatile private var pendingCandidate: AnimeStreamCandidate? = null

    init {
        canvas.addHierarchyListener { event ->
            if (event.changeFlags and HierarchyEvent.DISPLAYABILITY_CHANGED.toLong() != 0L && canvas.isDisplayable) {
                EventQueue.invokeLater { playPendingCandidate() }
            }
        }
    }

    fun load(candidate: AnimeStreamCandidate) {
        playbackError.set(null)
        pendingCandidate = candidate
        EventQueue.invokeLater { playPendingCandidate() }
    }

    fun dispatch(command: WebRuntimeCommand) {
        if (closed.get()) return
        EventQueue.invokeLater {
            if (closed.get()) return@invokeLater
            when (command.nativePlayerAction()) {
                NativePlayerAction.TogglePlayback -> runtime.togglePlayback()
                NativePlayerAction.SeekBackward -> runtime.seekBy(-15)
                NativePlayerAction.SeekForward -> runtime.seekBy(15)
                NativePlayerAction.VolumeUp -> runtime.adjustVolume(10)
                NativePlayerAction.VolumeDown -> runtime.adjustVolume(-10)
                NativePlayerAction.ToggleMute -> runtime.toggleMute()
                null -> Unit
            }
        }
    }

    private fun playPendingCandidate() {
        if (closed.get() || !canvas.isDisplayable) return
        val candidate = pendingCandidate ?: return
        pendingCandidate = null
        runCatching { runtime.play(candidate, Native.getComponentPointer(canvas)) }
            .onFailure { playbackError.set(it.message ?: "LibVLC 無法開始播放") }
    }

    fun snapshot(): AnimePlaybackSnapshot = runtime.snapshot().let { snapshot ->
        snapshot.copy(error = playbackError.get() ?: snapshot.error)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        pendingCandidate = null
        EventQueue.invokeLater(runtime::close)
    }

    companion object {
        fun createOrNull(onFailure: (String) -> Unit = {}): DesktopLibVLCPlayer? {
            val directory = DesktopLibVLCLocator.locate() ?: return null
            return runCatching { DesktopLibVLCPlayer(DesktopLibVLCRuntime.open(directory)) }
                .onFailure { onFailure(it.message ?: "LibVLC 初始化失敗") }
                .getOrNull()
        }
    }
}

internal class DesktopLibVLCRuntime internal constructor(
    private val api: LibVLCNative,
    private val instance: Pointer,
    private val mediaPlayer: Pointer,
) : Closeable {
    private val nativeLock = Any()
    private var closed = false

    fun play(candidate: AnimeStreamCandidate, windowHandle: Pointer) = synchronized(nativeLock) {
        check(!closed) { "LibVLC 內建播放器已關閉" }
        api.libvlc_media_player_set_hwnd(mediaPlayer, windowHandle)
        val media = api.libvlc_media_new_location(instance, candidate.url)
            ?: error("LibVLC 無法建立播放來源")
        try {
            candidate.headers["Referer"]?.takeIf(String::isNotBlank)?.let {
                api.libvlc_media_add_option(media, ":http-referrer=$it")
            }
            candidate.headers["User-Agent"]?.takeIf(String::isNotBlank)?.let {
                api.libvlc_media_add_option(media, ":http-user-agent=$it")
            }
            api.libvlc_media_player_set_media(mediaPlayer, media)
        } finally {
            api.libvlc_media_release(media)
        }
        check(api.libvlc_media_player_play(mediaPlayer) == 0) { "LibVLC 無法開始播放" }
    }

    fun togglePlayback() = synchronized(nativeLock) {
        if (closed) return@synchronized
        api.libvlc_media_player_set_pause(mediaPlayer, if (api.libvlc_media_player_is_playing(mediaPlayer) != 0) 1 else 0)
    }

    fun seekBy(seconds: Int) = synchronized(nativeLock) {
        if (closed) return@synchronized
        val current = api.libvlc_media_player_get_time(mediaPlayer).coerceAtLeast(0L)
        api.libvlc_media_player_set_time(mediaPlayer, (current + seconds * 1_000L).coerceAtLeast(0L))
    }

    fun adjustVolume(delta: Int) = synchronized(nativeLock) {
        if (closed) return@synchronized
        val current = api.libvlc_audio_get_volume(mediaPlayer).takeIf { it >= 0 } ?: 100
        api.libvlc_audio_set_volume(mediaPlayer, (current + delta).coerceIn(0, 125))
    }

    fun toggleMute() = synchronized(nativeLock) {
        if (closed) return@synchronized
        api.libvlc_audio_set_mute(mediaPlayer, if (api.libvlc_audio_get_mute(mediaPlayer) == 0) 1 else 0)
    }

    fun snapshot(): AnimePlaybackSnapshot = synchronized(nativeLock) {
        if (closed) return@synchronized AnimePlaybackSnapshot(error = "LibVLC 內建播放器已關閉")
        runCatching {
            val state = api.libvlc_media_player_get_state(mediaPlayer)
            AnimePlaybackSnapshot(
                positionSeconds = api.libvlc_media_player_get_time(mediaPlayer).coerceAtLeast(0L) / 1_000.0,
                durationSeconds = api.libvlc_media_player_get_length(mediaPlayer).coerceAtLeast(0L) / 1_000.0,
                isPlaying = state == LIBVLC_PLAYING || api.libvlc_media_player_is_playing(mediaPlayer) != 0,
                error = "LibVLC 無法解碼或讀取此播放源".takeIf { state == LIBVLC_ERROR },
            )
        }.getOrElse { throwable ->
            AnimePlaybackSnapshot(error = throwable.message ?: "LibVLC 狀態讀取失敗")
        }
    }

    override fun close(): Unit = synchronized(nativeLock) {
        if (closed) return@synchronized
        closed = true
        runCatching { api.libvlc_media_player_stop(mediaPlayer) }
        runCatching { api.libvlc_media_player_release(mediaPlayer) }
        runCatching { api.libvlc_release(instance) }
        Unit
    }

    companion object {
        private const val LIBVLC_PLAYING = 3
        private const val LIBVLC_ERROR = 7

        fun open(directory: File): DesktopLibVLCRuntime {
            NativeLibrary.addSearchPath("libvlc", directory.absolutePath)
            val api = Native.load("libvlc", LibVLCNative::class.java)
            val args = arrayOf(
                "--no-video-title-show",
                "--quiet",
                "--plugin-path=${File(directory, "plugins").absolutePath}",
            )
            val instance = api.libvlc_new(args.size, args) ?: error("LibVLC 初始化失敗")
            val player = api.libvlc_media_player_new(instance)
            if (player == null) {
                api.libvlc_release(instance)
                error("LibVLC 無法建立內建播放器")
            }
            return DesktopLibVLCRuntime(api, instance, player)
        }

        fun probeVersion(directory: File): String {
            NativeLibrary.addSearchPath("libvlc", directory.absolutePath)
            return Native.load("libvlc", LibVLCNative::class.java).libvlc_get_version().orEmpty()
        }
    }
}

internal interface LibVLCNative : Library {
    fun libvlc_get_version(): String?
    fun libvlc_new(argc: Int, argv: Array<String>): Pointer?
    fun libvlc_release(instance: Pointer)
    fun libvlc_media_new_location(instance: Pointer, mrl: String): Pointer?
    fun libvlc_media_add_option(media: Pointer, option: String)
    fun libvlc_media_release(media: Pointer)
    fun libvlc_media_player_new(instance: Pointer): Pointer?
    fun libvlc_media_player_release(mediaPlayer: Pointer)
    fun libvlc_media_player_set_hwnd(mediaPlayer: Pointer, drawable: Pointer)
    fun libvlc_media_player_set_media(mediaPlayer: Pointer, media: Pointer)
    fun libvlc_media_player_play(mediaPlayer: Pointer): Int
    fun libvlc_media_player_set_pause(mediaPlayer: Pointer, pause: Int)
    fun libvlc_media_player_is_playing(mediaPlayer: Pointer): Int
    fun libvlc_media_player_get_time(mediaPlayer: Pointer): Long
    fun libvlc_media_player_get_length(mediaPlayer: Pointer): Long
    fun libvlc_media_player_get_state(mediaPlayer: Pointer): Int
    fun libvlc_media_player_set_time(mediaPlayer: Pointer, time: Long): Int
    fun libvlc_audio_get_volume(mediaPlayer: Pointer): Int
    fun libvlc_audio_set_volume(mediaPlayer: Pointer, volume: Int): Int
    fun libvlc_audio_get_mute(mediaPlayer: Pointer): Int
    fun libvlc_audio_set_mute(mediaPlayer: Pointer, muted: Int)
    fun libvlc_media_player_stop(mediaPlayer: Pointer)
}
