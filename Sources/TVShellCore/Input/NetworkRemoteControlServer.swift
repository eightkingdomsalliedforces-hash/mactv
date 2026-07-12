import Darwin
import Foundation
import Network

public struct NetworkRemoteControlStatus: Equatable, Sendable {
    public var isRunning: Bool
    public var urlText: String
    public var message: String

    public init(isRunning: Bool, urlText: String, message: String) {
        self.isRunning = isRunning
        self.urlText = urlText
        self.message = message
    }
}

public final class NetworkRemoteControlServer: @unchecked Sendable {
    public static let shared = NetworkRemoteControlServer()
    public static let defaultPort: UInt16 = 8787

    private let queue = DispatchQueue(label: "com.tvshell.network-remote")
    private var listener: NWListener?
    private var onCommand: (@Sendable (RemoteCommand) -> Void)?
    private var currentStatus = NetworkRemoteControlStatus(
        isRunning: false,
        urlText: "http://localhost:\(NetworkRemoteControlServer.defaultPort)",
        message: "網路遙控器尚未啟動"
    )

    public init() {}

    public func start(
        port: UInt16 = NetworkRemoteControlServer.defaultPort,
        onCommand: @escaping @Sendable (RemoteCommand) -> Void
    ) -> NetworkRemoteControlStatus {
        self.onCommand = onCommand
        if listener != nil {
            return currentStatus
        }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            currentStatus = NetworkRemoteControlStatus(
                isRunning: false,
                urlText: "http://localhost:\(port)",
                message: "網路遙控器連接埠無效"
            )
            return currentStatus
        }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.updateStatus(for: state, port: port)
            }
            self.listener = listener
            currentStatus = NetworkRemoteControlStatus(
                isRunning: true,
                urlText: Self.remoteURLText(port: port),
                message: "同一 Wi-Fi 的 Android 手機可開啟此網址作為遙控器"
            )
            listener.start(queue: queue)
            return currentStatus
        } catch {
            currentStatus = NetworkRemoteControlStatus(
                isRunning: false,
                urlText: Self.remoteURLText(port: port),
                message: "網路遙控器啟動失敗：\(error.localizedDescription)"
            )
            return currentStatus
        }
    }

    public static func command(fromHTTPRequest request: String) -> RemoteCommand? {
        guard let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }

        let target = String(parts[1])
        if target.hasPrefix("/command/") {
            let name = String(target.dropFirst("/command/".count)).removingPercentEncoding ?? ""
            return RemoteCommand.networkRemoteCommand(named: name)
        }

        if target.hasPrefix("/command?"),
           let components = URLComponents(string: "http://tvshell.local\(target)") {
            let name = components.queryItems?.first { item in
                item.name == "name" || item.name == "command"
            }?.value
            return name.flatMap(RemoteCommand.networkRemoteCommand(named:))
        }

        return nil
    }

    public static var remotePageHTML: String {
        """
        <!doctype html>
        <html lang="zh-Hant">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <title>TVShell Remote</title>
          <style>
            :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; }
            body { margin: 0; min-height: 100vh; background: radial-gradient(circle at top, #27364f, #060912 62%); color: white; display: grid; place-items: center; }
            main { width: min(92vw, 560px); display: grid; gap: 18px; }
            h1 { margin: 0; font-size: clamp(34px, 8vw, 58px); letter-spacing: 0; }
            p { margin: 0; color: rgba(255,255,255,.72); font-size: 20px; line-height: 1.45; }
            .pad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; margin-top: 12px; }
            button {
              min-height: 86px; border: 1px solid rgba(255,255,255,.28); border-radius: 24px;
              background: rgba(255,255,255,.16); color: white; font-size: 26px; font-weight: 800;
              box-shadow: 0 18px 42px rgba(0,0,0,.24); backdrop-filter: blur(24px);
            }
            button:active { transform: scale(.96); background: rgba(255,255,255,.28); }
            .wide { grid-column: span 3; }
          </style>
        </head>
        <body>
          <main>
            <h1>TVShell Remote</h1>
            <p>Android TV 遙控器藍牙無法配對時，用同一 Wi-Fi 的手機打開這頁即可操作 TVShell。</p>
            <section class="pad">
              <span></span><button data-path="/command/up" onclick="send('up')">↑</button><span></span>
              <button onclick="send('left')">←</button><button onclick="send('ok')">OK</button><button onclick="send('right')">→</button>
              <span></span><button onclick="send('down')">↓</button><span></span>
              <button onclick="send('back')">Back</button><button onclick="send('home')">Home</button><button onclick="send('menu')">Menu</button>
              <button onclick="send('rewind')">⏪</button><button onclick="send('play')">Play</button><button onclick="send('fastForward')">⏩</button>
              <button onclick="send('volumeDown')">Vol -</button><button onclick="send('mute')">Mute</button><button onclick="send('volumeUp')">Vol +</button>
            </section>
          </main>
          <script>
            function send(name) {
              fetch('/command/' + encodeURIComponent(name), { method: 'POST', cache: 'no-store' }).catch(function() {});
            }
          </script>
        </body>
        </html>
        """
    }

    public static func remoteURLText(port: UInt16 = NetworkRemoteControlServer.defaultPort) -> String {
        "http://\(localIPAddress() ?? "localhost"):\(port)"
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, _, _ in
            guard let self,
                  let connection
            else {
                return
            }

            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if let command = Self.command(fromHTTPRequest: request) {
                onCommand?(command)
                send("OK", contentType: "text/plain; charset=utf-8", status: "200 OK", to: connection)
            } else {
                send(Self.remotePageHTML, contentType: "text/html; charset=utf-8", status: "200 OK", to: connection)
            }
        }
    }

    private func send(_ body: String, contentType: String, status: String, to connection: NWConnection) {
        let data = Self.httpResponse(body: body, contentType: contentType, status: status)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func httpResponse(body: String, contentType: String, status: String) -> Data {
        let bodyData = Data(body.utf8)
        var header = ""
        header += "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n\r\n"
        return Data(header.utf8) + bodyData
    }

    private func updateStatus(for state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            currentStatus = NetworkRemoteControlStatus(
                isRunning: true,
                urlText: Self.remoteURLText(port: port),
                message: "網路遙控器已啟動"
            )
        case let .failed(error):
            listener = nil
            currentStatus = NetworkRemoteControlStatus(
                isRunning: false,
                urlText: Self.remoteURLText(port: port),
                message: "網路遙控器失敗：\(error.localizedDescription)"
            )
        default:
            break
        }
    }

    private static func localIPAddress() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let length = host.firstIndex(of: 0) ?? host.count
                return String(decoding: host.prefix(length).map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
        }

        return nil
    }
}
