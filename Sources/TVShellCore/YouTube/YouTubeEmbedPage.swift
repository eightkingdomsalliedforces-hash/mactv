import Foundation

public struct YouTubeEmbedPage: Equatable, Sendable {
    public let videoID: String
    public let origin: URL
    public let startSeconds: Double

    public init(
        videoID: String,
        origin: URL = URL(string: "https://tvshell.local")!,
        startSeconds: Double = 0
    ) {
        self.videoID = videoID
        self.origin = origin
        self.startSeconds = max(0, startSeconds)
    }

    public var baseURL: URL {
        origin
    }

    public var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    public var html: String {
        let originValue = origin.absoluteString.addingPercentEncoding(withAllowedCharacters: .tvShellQueryValueAllowed) ?? origin.absoluteString
        let watchValue = watchURL.absoluteString
        let startValue = Int(startSeconds.rounded(.down))
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <style>
            html, body, #player, #playerFrame { margin: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
            body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; color: white; }
            #fallback {
              display: none;
              position: fixed;
              inset: 0;
              align-items: center;
              justify-content: center;
              flex-direction: column;
              gap: 22px;
              background: #111;
              text-align: center;
            }
            #fallback .code { opacity: 0.72; font-size: 26px; }
            #fallback .title { font-size: 42px; font-weight: 800; }
            #fallback a {
              color: white;
              font-size: 30px;
              font-weight: 700;
              text-decoration: underline;
            }
            #telemetry {
              position: fixed;
              width: 1px;
              height: 1px;
              opacity: 0;
              pointer-events: none;
            }
          </style>
        </head>
        <body>
          <iframe
            id="playerFrame"
            type="text/html"
            src="https://www.youtube.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=0&playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&cc_load_policy=1&cc_lang_pref=zh-Hant&start=\(startValue)&origin=\(originValue)"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen
            referrerpolicy="strict-origin-when-cross-origin"
            frameborder="0"></iframe>

          <div id="fallback">
            <div class="title">無法播放這部影片</div>
            <div class="code" id="errorCode">嵌入播放被 YouTube 或影片擁有者限制</div>
            <a href="\(watchValue)">前往 YouTube 觀看影片</a>
          </div>
          <div id="telemetry"></div>

          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var isPlaying = false;
            var lastState = {};
            function showFallback(code) {
              document.getElementById('playerFrame').style.display = 'none';
              document.getElementById('fallback').style.display = 'flex';
              document.getElementById('errorCode').textContent = '錯誤代碼：' + code + '。可改用 YouTube 原頁觀看。';
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('playerFrame', {
                events: {
                  onReady: function(event) {
                    if (\(startValue) > 0) event.target.seekTo(\(startValue), true);
                    event.target.playVideo();
                  },
                  onStateChange: function(event) { isPlaying = event.data === YT.PlayerState.PLAYING; },
                  onError: function(event) { showFallback(event.data); }
                }
              });
            }
            function tvShellYouTubeState() {
              if (!player || !player.getCurrentTime) return lastState;
              lastState = {
                currentTime: player.getCurrentTime(),
                duration: player.getDuration ? player.getDuration() : 0,
                isPlaying: isPlaying,
                volume: player.getVolume ? player.getVolume() : 100
              };
              document.getElementById('telemetry').textContent = JSON.stringify(lastState);
              return lastState;
            }
            setInterval(tvShellYouTubeState, 500);
            window.tvShellYouTubeCommand = function(command) {
              if (!player || !player.getCurrentTime) return;
              if (command === 'playPause') {
                if (isPlaying) player.pauseVideo(); else player.playVideo();
              }
              if (command === 'seekBack') {
                player.seekTo(Math.max(0, player.getCurrentTime() - 10), true);
              }
              if (command === 'seekForward') {
                player.seekTo(player.getCurrentTime() + 10, true);
              }
              if (command === 'restart') {
                player.seekTo(0, true);
                player.playVideo();
                isPlaying = true;
              }
              if (command === 'volumeUp' && player.setVolume) {
                player.setVolume(Math.min(100, player.getVolume() + 8));
              }
              if (command === 'volumeDown' && player.setVolume) {
                player.setVolume(Math.max(0, player.getVolume() - 8));
              }
              return tvShellYouTubeState();
            }
          </script>
        </body>
        </html>
        """
    }
}

private extension CharacterSet {
    static let tvShellQueryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
