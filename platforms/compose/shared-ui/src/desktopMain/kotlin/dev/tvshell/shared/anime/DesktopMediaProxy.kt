package dev.tvshell.shared.anime

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object DesktopMediaPlaylistRewriter {
    fun rewrite(payload: String, baseURL: String, proxy: (String) -> String): String = payload.lineSequence().joinToString("\n") { line ->
        when {
            line.isBlank() -> line
            line.startsWith("#") -> Regex("URI=\"([^\"]+)\"").replace(line) { match ->
                val resolved = URI(baseURL).resolve(match.groupValues[1]).toString()
                "URI=\"${proxy(resolved)}\""
            }
            else -> proxy(URI(baseURL).resolve(line.trim()).toString())
        }
    }
}

object DesktopMediaProxy {
    private data class Session(val headers: Map<String, String>)
    private val sessions = ConcurrentHashMap<String, Session>()
    private val server: HttpServer by lazy {
        HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0).apply {
            createContext("/media", ::handle)
            executor = Executors.newCachedThreadPool { runnable ->
                Thread(runnable, "TVShell-media-proxy").apply { isDaemon = true }
            }
            start()
        }
    }

    fun playbackURL(candidate: AnimeStreamCandidate): String {
        val token = UUID.randomUUID().toString()
        sessions[token] = Session(candidate.headers.filterKeys { it !in setOf("resolver", "source") })
        return endpoint(token, candidate.url)
    }

    private fun endpoint(token: String, target: String): String =
        "http://127.0.0.1:${server.address.port}/media/$token?url=${URLEncoder.encode(target, StandardCharsets.UTF_8)}"

    private fun handle(exchange: HttpExchange) {
        val token = exchange.requestURI.path.substringAfterLast('/')
        val session = sessions[token]
        val encoded = exchange.requestURI.rawQuery?.substringAfter("url=", "")
        if (session == null || encoded.isNullOrBlank()) {
            exchange.sendResponseHeaders(404, -1)
            exchange.close()
            return
        }
        val target = URLDecoder.decode(encoded, StandardCharsets.UTF_8)
        val connection = URI(target).toURL().openConnection() as HttpURLConnection
        try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 10_000
            connection.readTimeout = 20_000
            session.headers.forEach(connection::setRequestProperty)
            exchange.requestHeaders.getFirst("Range")?.let { connection.setRequestProperty("Range", it) }
            val status = connection.responseCode
            val input = if (status in 200..299) connection.inputStream else connection.errorStream
            if (input == null) {
                exchange.sendResponseHeaders(status, -1)
                return
            }
            val contentType = connection.contentType.orEmpty()
            exchange.responseHeaders.set("Content-Type", contentType.ifBlank { "application/octet-stream" })
            connection.getHeaderField("Content-Range")?.let { exchange.responseHeaders.set("Content-Range", it) }
            connection.getHeaderField("Accept-Ranges")?.let { exchange.responseHeaders.set("Accept-Ranges", it) }
            if (contentType.contains("mpegurl", ignoreCase = true) || target.substringBefore('?').endsWith(".m3u8", ignoreCase = true)) {
                val playlist = input.bufferedReader().use { it.readText() }
                val rewritten = DesktopMediaPlaylistRewriter.rewrite(playlist, target) { endpoint(token, it) }
                    .toByteArray(StandardCharsets.UTF_8)
                exchange.sendResponseHeaders(status, rewritten.size.toLong())
                exchange.responseBody.use { it.write(rewritten) }
            } else {
                val length = connection.getHeaderFieldLong("Content-Length", -1)
                exchange.sendResponseHeaders(status, if (length >= 0) length else 0)
                input.use { source -> exchange.responseBody.use(source::copyTo) }
            }
        } catch (_: Exception) {
            runCatching { exchange.sendResponseHeaders(502, -1) }
        } finally {
            connection.disconnect()
            exchange.close()
        }
    }
}
