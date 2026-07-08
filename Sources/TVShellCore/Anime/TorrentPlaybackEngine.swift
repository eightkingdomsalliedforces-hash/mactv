import Foundation

public enum TorrentPlaybackError: LocalizedError, Equatable {
    case aria2Unavailable
    case launchFailed(String)
    case noPlayableFile(URL)

    public var errorDescription: String? {
        switch self {
        case .aria2Unavailable:
            "找不到 aria2c。請先安裝：brew install aria2，或設定 TVSHELL_ARIA2C_PATH。"
        case let .launchFailed(message):
            "BT 引擎啟動失敗：\(message)"
        case let .noPlayableFile(directory):
            "BT 已開始下載，但尚未找到可播放影片檔：\(directory.path)"
        }
    }
}

public struct TorrentDownloadProgress: Equatable, Sendable {
    public var downloadedBytes: UInt64
    public var largestPlayableFileName: String?

    public init(downloadedBytes: UInt64, largestPlayableFileName: String? = nil) {
        self.downloadedBytes = downloadedBytes
        self.largestPlayableFileName = largestPlayableFileName
    }

    public var megabytesText: String {
        let megabytes = Double(downloadedBytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }

    public var statusText: String {
        if let largestPlayableFileName {
            return "已下載 \(megabytesText) · \(largestPlayableFileName)"
        }
        return "正在連接 peers / 取得 metadata · 已下載 \(megabytesText)"
    }
}

public struct Aria2TorrentPlaybackEngine: Sendable {
    public var cacheRoot: URL
    public var executablePath: String?
    public var readinessMinimumBytes: UInt64
    public var pollLimit: Int
    public var pollIntervalNanoseconds: UInt64

    public init(
        cacheRoot: URL? = nil,
        executablePath: String? = nil,
        readinessMinimumBytes: UInt64 = 1_048_576,
        pollLimit: Int = 120,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.cacheRoot = cacheRoot ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVShell/Torrents", isDirectory: true)
        self.executablePath = executablePath
        self.readinessMinimumBytes = readinessMinimumBytes
        self.pollLimit = pollLimit
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    public func downloadDirectory(for stream: AnimeStreamCandidate) -> URL {
        cacheRoot.appendingPathComponent(stableIdentifier(for: stream.url.absoluteString), isDirectory: true)
    }

    public func arguments(for stream: AnimeStreamCandidate, downloadDirectory: URL) -> [String] {
        [
            "--dir=\(downloadDirectory.path)",
            "--continue=true",
            "--file-allocation=none",
            "--bt-save-metadata=true",
            "--bt-load-saved-metadata=true",
            "--bt-enable-lpd=true",
            "--enable-dht=true",
            "--enable-peer-exchange=true",
            "--summary-interval=0",
            "--seed-time=0",
            "--bt-prioritize-piece=head=32M,tail=8M",
            stream.url.absoluteString
        ]
    }

    public func playableFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  playableExtensions.contains(url.pathExtension.lowercased())
            else {
                return nil
            }
            return url
        }
        .sorted { left, right in
            let leftSize = (try? left.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let rightSize = (try? right.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if leftSize == rightSize {
                return left.lastPathComponent < right.lastPathComponent
            }
            return leftSize > rightSize
        }
    }

    public func startStreaming(
        _ stream: AnimeStreamCandidate,
        onProgress: (@Sendable (TorrentDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        guard let executable = resolvedExecutablePath() else {
            throw TorrentPlaybackError.aria2Unavailable
        }

        let directory = downloadDirectory(for: stream)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try launchAria2(executable: executable, stream: stream, directory: directory)
        return try await waitForPlayableFile(in: directory, onProgress: onProgress)
    }

    public func downloadProgress(in directory: URL) -> TorrentDownloadProgress {
        let playableFiles = playableFiles(in: directory)
        let largestFile = playableFiles.first
        return TorrentDownloadProgress(
            downloadedBytes: downloadedBytes(in: directory),
            largestPlayableFileName: largestFile?.lastPathComponent
        )
    }

    private var playableExtensions: Set<String> {
        ["mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "m2ts"]
    }

    private func resolvedExecutablePath() -> String? {
        if let executablePath, FileManager.default.isExecutableFile(atPath: executablePath) {
            return executablePath
        }
        if let environmentPath = ProcessInfo.processInfo.environment["TVSHELL_ARIA2C_PATH"],
           FileManager.default.isExecutableFile(atPath: environmentPath) {
            return environmentPath
        }
        let candidates = [
            "/opt/homebrew/bin/aria2c",
            "/usr/local/bin/aria2c",
            "/usr/bin/aria2c"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func launchAria2(executable: String, stream: AnimeStreamCandidate, directory: URL) throws {
        let processID = stableIdentifier(for: stream.url.absoluteString)
        if TorrentProcessRegistry.shared.isRunning(id: processID) {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(for: stream, downloadDirectory: directory)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            TorrentProcessRegistry.shared.remember(process, id: processID)
        } catch {
            throw TorrentPlaybackError.launchFailed(error.localizedDescription)
        }
    }

    private func waitForPlayableFile(
        in directory: URL,
        onProgress: (@Sendable (TorrentDownloadProgress) -> Void)?
    ) async throws -> URL {
        for _ in 0..<pollLimit {
            onProgress?(downloadProgress(in: directory))
            if let file = readyPlayableFile(in: directory) {
                return file
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw TorrentPlaybackError.noPlayableFile(directory)
    }

    private func downloadedBytes(in directory: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(UInt64(0)) { partial, item in
            guard let url = item as? URL,
                  url.pathExtension.lowercased() != "aria2"
            else {
                return partial
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + UInt64(max(0, size))
        }
    }

    private func readyPlayableFile(in directory: URL) -> URL? {
        playableFiles(in: directory).first { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return UInt64(max(0, size)) >= readinessMinimumBytes
        }
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

private final class TorrentProcessRegistry: @unchecked Sendable {
    static let shared = TorrentProcessRegistry()

    private let lock = NSLock()
    private var processes: [String: Process] = [:]

    func isRunning(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let process = processes[id], process.isRunning {
            return true
        }
        processes[id] = nil
        return false
    }

    func remember(_ process: Process, id: String) {
        lock.lock()
        processes[id] = process
        lock.unlock()
    }
}
