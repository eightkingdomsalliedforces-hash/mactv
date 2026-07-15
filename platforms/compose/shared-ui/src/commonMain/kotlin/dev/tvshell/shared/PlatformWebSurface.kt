package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

enum class WebRuntimeCommand {
    None,
    ScrollUp,
    ScrollDown,
    ScrollLeft,
    ScrollRight,
    Select,
    Back,
    PlayPause,
    Rewind,
    FastForward,
    VolumeUp,
    VolumeDown,
    Mute,
}

data class WebRuntimeSignal(
    val command: WebRuntimeCommand = WebRuntimeCommand.None,
    val sequence: Long = 0,
)

data class WebRuntimeState(
    val url: String,
    val signal: WebRuntimeSignal = WebRuntimeSignal(),
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): WebRuntimeState = when (command) {
        RemoteCommand.Home -> copy(pendingAction = "exit")
        RemoteCommand.Up -> signaled(WebRuntimeCommand.ScrollUp)
        RemoteCommand.Down -> signaled(WebRuntimeCommand.ScrollDown)
        RemoteCommand.Left -> signaled(WebRuntimeCommand.ScrollLeft)
        RemoteCommand.Right -> signaled(WebRuntimeCommand.ScrollRight)
        RemoteCommand.Select -> signaled(WebRuntimeCommand.Select)
        RemoteCommand.Back -> signaled(WebRuntimeCommand.Back)
        RemoteCommand.PlayPause -> signaled(WebRuntimeCommand.PlayPause)
        RemoteCommand.Rewind -> signaled(WebRuntimeCommand.Rewind)
        RemoteCommand.FastForward -> signaled(WebRuntimeCommand.FastForward)
        RemoteCommand.VolumeUp -> signaled(WebRuntimeCommand.VolumeUp)
        RemoteCommand.VolumeDown -> signaled(WebRuntimeCommand.VolumeDown)
        RemoteCommand.Mute -> signaled(WebRuntimeCommand.Mute)
        else -> this
    }

    fun clearAction(): WebRuntimeState = copy(pendingAction = null)

    private fun signaled(command: WebRuntimeCommand): WebRuntimeState =
        copy(signal = WebRuntimeSignal(command, signal.sequence + 1), pendingAction = null)
}

enum class NativePlayerAction {
    TogglePlayback,
    SeekBackward,
    SeekForward,
    VolumeUp,
    VolumeDown,
    ToggleMute,
}

fun WebRuntimeCommand.nativePlayerAction(): NativePlayerAction? = when (this) {
    WebRuntimeCommand.PlayPause, WebRuntimeCommand.Select -> NativePlayerAction.TogglePlayback
    WebRuntimeCommand.Rewind -> NativePlayerAction.SeekBackward
    WebRuntimeCommand.FastForward -> NativePlayerAction.SeekForward
    WebRuntimeCommand.VolumeUp -> NativePlayerAction.VolumeUp
    WebRuntimeCommand.VolumeDown -> NativePlayerAction.VolumeDown
    WebRuntimeCommand.Mute -> NativePlayerAction.ToggleMute
    else -> null
}

internal class RequestedURLPolicy(initialURL: String) {
    private var requestedURL = initialURL

    fun shouldLoad(nextURL: String): Boolean {
        if (requestedURL == nextURL) return false
        requestedURL = nextURL
        return true
    }
}

internal class OwnedValue<T> {
    private var owner: Any? = null
    var value: T? = null
        private set

    fun attach(owner: Any, value: T) {
        this.owner = owner
        this.value = value
    }

    fun detach(owner: Any): Boolean {
        if (this.owner !== owner) return false
        this.owner = null
        value = null
        return true
    }
}

internal object WebRemoteScripts {
    val pagePreparation: String = """
        (() => {
          document.documentElement.style.scrollbarWidth = 'none';
          const styleId = 'tvshell-remote-style';
          if (!document.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
              ::-webkit-scrollbar { display:none!important; width:0!important; height:0!important }
              .tvshell-remote-focus { outline:4px solid rgba(255,255,255,.96)!important; outline-offset:4px!important; border-radius:8px!important }
            `;
            (document.head || document.documentElement).appendChild(style);
          }

          const selector = 'a[href],button,input:not([type="hidden"]),select,textarea,[role="button"],[role="link"],[tabindex]:not([tabindex="-1"]),video';
          const visibleCandidates = () => [...document.querySelectorAll(selector)].filter(element => {
            const rect = element.getBoundingClientRect();
            const style = getComputedStyle(element);
            return !element.disabled && rect.width > 2 && rect.height > 2 &&
              rect.bottom >= 0 && rect.right >= 0 && rect.top <= innerHeight && rect.left <= innerWidth &&
              style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
          });
          const center = element => {
            const rect = element.getBoundingClientRect();
            return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
          };
          const markFocused = element => {
            document.querySelectorAll('.tvshell-remote-focus').forEach(item => item.classList.remove('tvshell-remote-focus'));
            element.classList.add('tvshell-remote-focus');
            element.focus({ preventScroll:true });
            element.scrollIntoView({ behavior:'smooth', block:'center', inline:'center' });
          };

          window.__tvshellRemoteMove = direction => {
            const items = visibleCandidates();
            if (!items.length) {
              const amount = direction === 'up' ? -320 : direction === 'down' ? 320 : 0;
              const horizontal = direction === 'left' ? -420 : direction === 'right' ? 420 : 0;
              window.scrollBy({ top:amount, left:horizontal, behavior:'smooth' });
              return false;
            }
            let current = document.activeElement;
            if (!items.includes(current)) {
              current = items.reduce((best, item) => {
                const point = center(item);
                const distance = Math.hypot(point.x - innerWidth / 2, point.y - innerHeight / 2);
                return !best || distance < best.distance ? { item, distance } : best;
              }, null).item;
              markFocused(current);
              return true;
            }
            const origin = center(current);
            let best = null;
            items.forEach(item => {
              if (item === current) return;
              const point = center(item);
              const dx = point.x - origin.x;
              const dy = point.y - origin.y;
              const forward = direction === 'left' ? -dx : direction === 'right' ? dx : direction === 'up' ? -dy : dy;
              if (forward <= 4) return;
              const cross = direction === 'left' || direction === 'right' ? Math.abs(dy) : Math.abs(dx);
              const score = forward + cross * 2.35;
              if (!best || score < best.score) best = { item, score };
            });
            if (best) {
              markFocused(best.item);
              return true;
            }
            const amount = direction === 'up' ? -320 : direction === 'down' ? 320 : 0;
            const horizontal = direction === 'left' ? -420 : direction === 'right' ? 420 : 0;
            window.scrollBy({ top:amount, left:horizontal, behavior:'smooth' });
            return false;
          };

          window.__tvshellRemoteSelect = () => {
            const active = document.activeElement;
            const target = active && active !== document.body && active !== document.documentElement
              ? active
              : document.elementFromPoint(innerWidth / 2, innerHeight / 2)?.closest(selector);
            if (!target) return false;
            if (target.tagName === 'VIDEO') {
              target.paused ? target.play() : target.pause();
            } else {
              target.click();
            }
            return true;
          };

          window.__tvshellVideo = action => {
            const video = document.querySelector('video');
            if (!video) return false;
            if (action === 'toggle') video.paused ? video.play() : video.pause();
            if (action === 'rewind') video.currentTime = Math.max(0, video.currentTime - 15);
            if (action === 'forward') video.currentTime = Math.min(video.duration || Infinity, video.currentTime + 15);
            if (action === 'volumeUp') video.volume = Math.min(1, video.volume + .1);
            if (action === 'volumeDown') video.volume = Math.max(0, video.volume - .1);
            if (action === 'mute') video.muted = !video.muted;
            return true;
          };

          const candidates = [...document.querySelectorAll('button,a,[role="button"]')];
          const age = candidates.find(element => /^(同意|我已滿|繼續觀看|進入)$/i.test((element.innerText || '').trim()));
          if (age && /15|年齡|未滿|限制級/.test(document.body.innerText || '')) age.click();
        })()
    """.trimIndent()

    fun command(command: WebRuntimeCommand): String = when (command) {
        WebRuntimeCommand.ScrollUp -> move("up", "top:-320")
        WebRuntimeCommand.ScrollDown -> move("down", "top:320")
        WebRuntimeCommand.ScrollLeft -> move("left", "left:-420")
        WebRuntimeCommand.ScrollRight -> move("right", "left:420")
        WebRuntimeCommand.Select -> "window.__tvshellRemoteSelect ? window.__tvshellRemoteSelect() : void 0"
        WebRuntimeCommand.PlayPause -> video("toggle")
        WebRuntimeCommand.Rewind -> video("rewind")
        WebRuntimeCommand.FastForward -> video("forward")
        WebRuntimeCommand.VolumeUp -> video("volumeUp")
        WebRuntimeCommand.VolumeDown -> video("volumeDown")
        WebRuntimeCommand.Mute -> video("mute")
        else -> "void 0"
    }

    private fun move(direction: String, fallback: String): String =
        "window.__tvshellRemoteMove ? window.__tvshellRemoteMove('$direction') : window.scrollBy({$fallback,behavior:'smooth'})"

    private fun video(action: String): String =
        "window.__tvshellVideo ? window.__tvshellVideo('$action') : void 0"
}

internal class RootFocusBootstrap {
    private var requested = false

    fun requestOnce(request: () -> Unit): Boolean {
        if (requested) return false
        request()
        requested = true
        return true
    }
}

@Composable
expect fun PlatformWebSurface(
    url: String,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier = Modifier,
)
