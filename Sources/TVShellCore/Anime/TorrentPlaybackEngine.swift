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
        episodeNumber: Int? = nil,
        onProgress: (@Sendable (TorrentDownloadProgress) -> Void)? = nil
    ) async throws -> URL {
        guard let executable = resolvedExecutablePath() else {
            throw TorrentPlaybackError.aria2Unavailable
        }

        let directory = downloadDirectory(for: stream)
        let processID = stableIdentifier(for: stream.url.absoluteString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try launchAria2(executable: executable, stream: stream, directory: directory)
        return try await waitForPlayableFile(in: directory, episodeNumber: episodeNumber, processID: processID, onProgress: onProgress)
    }

    public func downloadProgress(in directory: URL, episodeNumber: Int? = nil) -> TorrentDownloadProgress {
        let playableFiles = playableFiles(in: directory)
        let displayedFile = episodeNumber
            .flatMap { preferredPlayableFile(in: directory, episodeNumber: $0) }
            ?? playableFiles.first
        return TorrentDownloadProgress(
            downloadedBytes: downloadedBytes(in: directory),
            largestPlayableFileName: displayedFile?.lastPathComponent
        )
    }

    public func preferredPlayableFile(in directory: URL, episodeNumber: Int) -> URL? {
        let files = playableFiles(in: directory)
        guard files.isEmpty == false else {
            return nil
        }
        let padded = String(format: "%02d", episodeNumber)
        let plain = "\(episodeNumber)"
        let patterns = [
            "第\(padded)話", "第\(plain)話",
            "第\(padded)集", "第\(plain)集",
            "[\(padded)]", "[\(plain)]",
            "EP\(padded)", "EP\(plain)",
            "E\(padded)", "E\(plain)",
            "- \(padded)", "- \(plain)",
            "_\(padded)", "_\(plain)"
        ]
        return files.first { file in
            let name = file.deletingPathExtension().lastPathComponent
            return patterns.contains { pattern in
                name.localizedCaseInsensitiveContains(pattern)
            }
        }
    }

    public func deleteDownload(for stream: AnimeStreamCandidate) throws {
        let directory = downloadDirectory(for: stream)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
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
        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(for: stream, downloadDirectory: directory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { process in
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            TorrentProcessRegistry.shared.recordTermination(
                id: processID,
                exitCode: process.terminationStatus,
                output: [stderr, stdout]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: "\n")
            )
        }

        do {
            try process.run()
            TorrentProcessRegistry.shared.remember(process, id: processID)
        } catch {
            throw TorrentPlaybackError.launchFailed(error.localizedDescription)
        }
    }

    private func waitForPlayableFile(
        in directory: URL,
        episodeNumber: Int?,
        processID: String,
        onProgress: (@Sendable (TorrentDownloadProgress) -> Void)?
    ) async throws -> URL {
        for _ in 0..<pollLimit {
            let progress = downloadProgress(in: directory, episodeNumber: episodeNumber)
            onProgress?(progress)
            if let file = readyPlayableFile(in: directory, episodeNumber: episodeNumber) {
                return file
            }
            if TorrentProcessRegistry.shared.hasTerminated(id: processID),
               progress.downloadedBytes == 0 {
                let output = TorrentProcessRegistry.shared.lastErrorOutput(id: processID)
                throw TorrentPlaybackError.launchFailed(output.isEmpty ? "aria2c 已結束但沒有下載任何資料。" : output)
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

    private func readyPlayableFile(in directory: URL, episodeNumber: Int?) -> URL? {
        let candidates: [URL]
        if let episodeNumber,
           let preferred = preferredPlayableFile(in: directory, episodeNumber: episodeNumber) {
            candidates = [preferred]
        } else {
            candidates = playableFiles(in: directory)
        }
        return candidates.first { url in
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
    private var terminatedProcesses: Set<String> = []
    private var errorOutputs: [String: String] = [:]

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
        if process.isRunning {
            terminatedProcesses.remove(id)
            errorOutputs[id] = nil
        }
        lock.unlock()
    }

    func recordTermination(id: String, exitCode: Int32, output: String) {
        lock.lock()
        processes[id] = nil
        terminatedProcesses.insert(id)
        let fallback = "aria2c 已結束，exit code \(exitCode)。"
        errorOutputs[id] = output.isEmpty ? fallback : "\(fallback)\n\(output)"
        lock.unlock()
    }

    func hasTerminated(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminatedProcesses.contains(id)
    }

    func lastErrorOutput(id: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return errorOutputs[id] ?? ""
    }
}
