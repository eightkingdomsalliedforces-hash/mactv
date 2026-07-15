package dev.tvshell.shared.anime

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import dev.tvshell.shared.OwnedValue
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicLong

class AndroidAnimeHTTPTransport : AnimeHTTPTransport {
    override suspend fun get(url: String, headers: Map<String, String>): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.instanceFollowRedirects = true
            headers.forEach(connection::setRequestProperty)
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}

class AndroidMediaPlayerAdapter(private val context: Context) : AnimePlayerAdapter {
    private val applicationContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val generation = AtomicLong()
    private var player: ExoPlayer? = null
    private val surfaceLease = OwnedValue<Surface>()
    private var currentCandidateKey: String? = null
    private var volume = 1f
    private var muted = false
    @Volatile private var playbackPositionSeconds = 0.0
    @Volatile private var playbackDurationSeconds = 0.0
    @Volatile private var playbackIsPlaying = false
    @Volatile private var playbackError: String? = null

    init {
        AndroidAnimePlaybackRegistry.register(this)
    }

    override fun load(candidate: AnimeStreamCandidate) {
        val candidateKey = candidate.url + "\n" + candidate.headers.toSortedMap()
        val token = generation.incrementAndGet()
        playbackPositionSeconds = 0.0
        playbackDurationSeconds = 0.0
        playbackIsPlaying = false
        playbackError = null
        mainHandler.post {
            if (generation.get() != token) return@post
            if (player != null && currentCandidateKey == candidateKey) {
                player?.let { current ->
                    current.playWhenReady = true
                    current.play()
                    startPositionUpdates(token, current)
                }
                return@post
            }
            player?.release()
            val requestHeaders = candidate.headers.filterKeys { key ->
                !key.equals("resolver", ignoreCase = true)
            }
            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(requestHeaders)
            val dataSourceFactory = DefaultDataSource.Factory(applicationContext, httpFactory)
            val next = ExoPlayer.Builder(applicationContext)
                .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
                .build()
            player = next
            currentCandidateKey = candidateKey
            surfaceLease.value?.let(next::setVideoSurface)
            next.volume = if (muted) 0f else volume
            next.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    if (generation.get() == token && player === next) playbackIsPlaying = isPlaying
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (generation.get() != token || player !== next) return
                    playbackDurationSeconds = next.duration.validMediaTimeSeconds()
                    if (playbackState == Player.STATE_ENDED) playbackIsPlaying = false
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (generation.get() == token && player === next) {
                        playbackError = "Media3 內建播放器錯誤：${error.errorCodeName} · ${error.message.orEmpty()}".trimEnd(' ', '·')
                        playbackIsPlaying = false
                    }
                }
            })
            runCatching {
                next.setMediaItem(MediaItem.fromUri(candidate.url))
                next.prepare()
                next.playWhenReady = true
                startPositionUpdates(token, next)
            }.onFailure { throwable ->
                if (generation.get() == token && player === next) {
                    playbackError = "Media3 內建播放器無法載入：${throwable.message ?: throwable::class.simpleName}"
                    playbackIsPlaying = false
                }
            }
        }
    }

    override fun play() {
        mainHandler.post {
            player?.playWhenReady = true
            player?.play()
        }
    }

    override fun pause() {
        mainHandler.post { player?.pause() }
    }

    override fun seekBy(seconds: Int) {
        mainHandler.post {
            player?.let { current ->
                val maximum = current.duration.takeIf { it != C.TIME_UNSET && it >= 0 } ?: Long.MAX_VALUE
                current.seekTo((current.currentPosition + seconds * 1_000L).coerceIn(0L, maximum))
            }
        }
    }

    fun adjustVolume(delta: Float) {
        mainHandler.post {
            volume = (volume + delta).coerceIn(0f, 1f)
            muted = false
            player?.volume = volume
        }
    }

    fun toggleMute() {
        mainHandler.post {
            muted = !muted
            player?.volume = if (muted) 0f else volume
        }
    }

    override fun release() {
        generation.incrementAndGet()
        playbackPositionSeconds = 0.0
        playbackDurationSeconds = 0.0
        playbackIsPlaying = false
        playbackError = null
        volume = 1f
        muted = false
        mainHandler.post {
            player?.release()
            player = null
            currentCandidateKey = null
        }
    }

    fun close() {
        release()
        AndroidAnimePlaybackRegistry.unregister(this)
    }

    fun attachSurface(owner: Any, value: Surface) {
        mainHandler.post {
            surfaceLease.attach(owner, value)
            player?.setVideoSurface(value)
        }
    }

    fun detachSurface(owner: Any, pauseIfOwned: Boolean = false) {
        mainHandler.post {
            if (!surfaceLease.detach(owner)) return@post
            if (pauseIfOwned) player?.pause()
            player?.clearVideoSurface()
        }
    }

    fun snapshot(): AnimePlaybackSnapshot = AnimePlaybackSnapshot(
        positionSeconds = playbackPositionSeconds,
        durationSeconds = playbackDurationSeconds,
        isPlaying = playbackIsPlaying,
        error = playbackError,
    )

    private fun startPositionUpdates(token: Long, expectedPlayer: ExoPlayer) {
        mainHandler.post(object : Runnable {
            override fun run() {
                if (generation.get() != token || player !== expectedPlayer) return
                playbackPositionSeconds = expectedPlayer.currentPosition.validMediaTimeSeconds()
                playbackDurationSeconds = expectedPlayer.duration.validMediaTimeSeconds()
                playbackIsPlaying = expectedPlayer.isPlaying
                mainHandler.postDelayed(this, 250L)
            }
        })
    }

    private fun Long.validMediaTimeSeconds(): Double = when {
        this == C.TIME_UNSET || this < 0L -> 0.0
        else -> this / 1_000.0
    }
}

object AndroidAnimePlaybackRegistry {
    @Volatile
    var player: AndroidMediaPlayerAdapter? = null
        private set

    fun register(value: AndroidMediaPlayerAdapter) {
        player = value
    }

    fun unregister(value: AndroidMediaPlayerAdapter) {
        if (player === value) player = null
    }
}

class AndroidTorrentCacheCleaner(private val root: File) {
    fun clean(maxBytes: Long, nowEpochSeconds: Long, expirationSeconds: Long): List<String> {
        val entries = root.listFiles()?.filter { it.isDirectory }?.map {
            TorrentCacheEntry(it.name, it.walkTopDown().filter(File::isFile).sumOf(File::length), it.lastModified() / 1_000)
        }.orEmpty()
        val ids = TorrentCachePolicy.idsToDelete(entries, maxBytes, nowEpochSeconds, expirationSeconds)
        ids.forEach { File(root, it).deleteRecursively() }
        return ids
    }
}
