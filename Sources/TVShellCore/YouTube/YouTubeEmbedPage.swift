import Foundation

public struct YouTubeEmbedPage: Equatable, Sendable {
    public let videoID: String
    public let origin: URL

    public init(videoID: String, origin: URL = URL(string: "https://mactv.local")!) {
        self.videoID = videoID
        self.origin = origin
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
          </style>
        </head>
        <body>
          <iframe
            id="playerFrame"
            type="text/html"
            src="https://www.youtube.com/embed/\(videoID)?enablejsapi=1&autoplay=1&controls=1&playsinline=1&rel=0&origin=\(originValue)"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen
            referrerpolicy="strict-origin-when-cross-origin"
            frameborder="0"></iframe>

          <div id="fallback">
            <div class="title">無法播放這部影片</div>
            <div class="code" id="errorCode">嵌入播放被 YouTube 或影片擁有者限制</div>
            <a href="\(watchValue)">前往 YouTube 觀看影片</a>
          </div>

          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var isPlaying = false;
            function showFallback(code) {
              document.getElementById('playerFrame').style.display = 'none';
              document.getElementById('fallback').style.display = 'flex';
              document.getElementById('errorCode').textContent = '錯誤代碼：' + code + '。可改用 YouTube 原頁觀看。';
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('playerFrame', {
                events: {
                  onReady: function(event) { event.target.playVideo(); },
                  onStateChange: function(event) { isPlaying = event.data === YT.PlayerState.PLAYING; },
                  onError: function(event) { showFallback(event.data); }
                }
              });
            }
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
