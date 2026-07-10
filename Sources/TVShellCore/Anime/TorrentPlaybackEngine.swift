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

public struct TorrentTaskStatus: Equatable, Sendable {
    public var peerCount: Int
    public var trackerURL: String?
    public var completedPieces: Int
    public var totalPieces: Int
    public var downloadSpeedBytesPerSecond: UInt64
    public var etaSeconds: Int?
    public var errorMessage: String?

    public init(
        peerCount: Int,
        trackerURL: String? = nil,
        completedPieces: Int,
        totalPieces: Int,
        downloadSpeedBytesPerSecond: UInt64,
        etaSeconds: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.peerCount = max(peerCount, 0)
        self.trackerURL = trackerURL
        self.completedPieces = max(completedPieces, 0)
        self.totalPieces = max(totalPieces, 0)
        self.downloadSpeedBytesPerSecond = downloadSpeedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.errorMessage = errorMessage
    }
}

public enum Aria2RPCStatusDecoder {
    public static func decode(_ data: Data) throws -> TorrentTaskStatus {
        let response = try JSONDecoder().decode(Aria2RPCStatusResponse.self, from: data)
        let status = response.result
        let totalLength = UInt64(status.totalLength) ?? 0
        let completedLength = UInt64(status.completedLength) ?? 0
        let speed = UInt64(status.downloadSpeed) ?? 0
        let bitfield = status.bitfield ?? ""
        let totalPieces = bitfield.count * 4
        let completedPieces = bitfield.reduce(into: 0) { count, character in
            count += character.hexDigitValue?.nonzeroBitCount ?? 0
        }
        let remaining = totalLength > completedLength ? totalLength - completedLength : 0
        let eta = speed > 0 && remaining > 0 ? Int(remaining / speed) : nil
        let tracker = status.bittorrent?.announceList?.joined().first
        let error = status.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TorrentTaskStatus(
            peerCount: Int(status.connections) ?? Int(status.numSeeders ?? "") ?? 0,
            trackerURL: tracker,
            completedPieces: completedPieces,
            totalPieces: totalPieces,
            downloadSpeedBytesPerSecond: speed,
            etaSeconds: eta,
            errorMessage: error?.isEmpty == false ? error : nil
        )
    }
}

private struct Aria2RPCStatusResponse: Decodable {
    var result: Aria2RPCStatusResult
}

private struct Aria2RPCStatusResult: Decodable {
    var connections: String
    var numSeeders: String?
    var bitfield: String?
    var totalLength: String
    var completedLength: String
    var downloadSpeed: String
    var errorMessage: String?
    var bittorrent: Aria2RPCBitTorrent?
}

private struct Aria2RPCBitTorrent: Decodable {
    var announceList: [[String]]?
}

public struct TorrentDownloadProgress: Equatable, Sendable {
    public var downloadedBytes: UInt64
    public var selectedFileBytes: UInt64?
    public var largestPlayableFileName: String?
    public var failureMessage: String?

    public init(downloadedBytes: UInt64, selectedFileBytes: UInt64? = nil, largestPlayableFileName: String? = nil, failureMessage: String? = nil) {
        self.downloadedBytes = downloadedBytes
        self.selectedFileBytes = selectedFileBytes
        self.largestPlayableFileName = largestPlayableFileName
        self.failureMessage = failureMessage
    }

    public var megabytesText: String {
        let megabytes = Double(downloadedBytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }

    public var statusText: String {
        if let failureMessage, failureMessage.isEmpty == false { return "BT 任務錯誤：\(failureMessage)" }
        if let largestPlayableFileName {
            let selectedText = selectedFileBytes.map { TorrentDownloadProgress.megabytesText(for: $0) } ?? "0.0 MB"
            return "總下載 \(megabytesText) · 目前檔案緩衝 \(selectedText) · \(largestPlayableFileName)"
        }
        return "正在連接 peers / 取得 metadata / 緩衝 · 已下載 \(megabytesText)"
    }

    private static func megabytesText(for bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }
}

public struct TorrentCachedDownload: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var downloadedBytes: UInt64

    public init(id: String, title: String, subtitle: String, downloadedBytes: UInt64) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.downloadedBytes = downloadedBytes
    }

    public var megabytesText: String {
        let megabytes = Double(downloadedBytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }
}

public protocol TorrentPlaybackEngine: Sendable {
    func downloadDirectory(for stream: AnimeStreamCandidate) -> URL
    func startStreaming(
        _ stream: AnimeStreamCandidate,
        episodeNumber: Int?,
        onProgress: (@Sendable (TorrentDownloadProgress) -> Void)?
    ) async throws -> URL
    func rememberDownload(for stream: AnimeStreamCandidate, title: String, subtitle: String) throws
    func cachedDownloads() -> [TorrentCachedDownload]
    func deleteDownload(for stream: AnimeStreamCandidate) throws
    func deleteDownload(id: String) throws
}

public struct Aria2TorrentPlaybackEngine: TorrentPlaybackEngine {
    public var cacheRoot: URL
    public var executablePath: String?
    public var readinessMinimumBytes: UInt64
    public var pollLimit: Int
    public var pollIntervalNanoseconds: UInt64

    public init(
        cacheRoot: URL? = nil,
        executablePath: String? = nil,
        readinessMinimumBytes: UInt64 = 48 * 1_048_576,
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

    public func rememberDownload(for stream: AnimeStreamCandidate, title: String, subtitle: String) throws {
        let directory = downloadDirectory(for: stream)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = TorrentDownloadManifest(title: title, subtitle: subtitle)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL(in: directory), options: Data.WritingOptions.atomic)
    }

    public func cachedDownloads() -> [TorrentCachedDownload] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory -> TorrentCachedDownload? in
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else {
                return nil
            }
            let manifest = downloadManifest(in: directory)
            let fallbackTitle = "BT 快取 \(directory.lastPathComponent.prefix(6))"
            return TorrentCachedDownload(
                id: directory.lastPathComponent,
                title: manifest?.title ?? fallbackTitle,
                subtitle: manifest?.subtitle ?? directory.path,
                downloadedBytes: downloadedBytes(in: directory)
            )
        }
        .sorted { left, right in
            if left.title == right.title {
                return left.subtitle < right.subtitle
            }
            return left.title < right.title
        }
    }

    public func downloadProgress(in directory: URL, episodeNumber: Int? = nil) -> TorrentDownloadProgress {
        let playableFiles = playableFiles(in: directory)
        let displayedFile = episodeNumber
            .flatMap { preferredPlayableFile(in: directory, episodeNumber: $0) }
            ?? playableFiles.first
        return TorrentDownloadProgress(
            downloadedBytes: downloadedBytes(in: directory),
            selectedFileBytes: displayedFile.map { fileBufferedBytes($0) },
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
        TorrentProcessRegistry.shared.terminate(id: stableIdentifier(for: stream.url.absoluteString))
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    public func deleteDownload(id: String) throws {
        TorrentProcessRegistry.shared.terminate(id: id)
        let directory = cacheRoot.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    private var playableExtensions: Set<String> {
        ["mp4", "m4v", "mov", "mkv", "webm", "avi", "ts", "m2ts"]
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent(".tvshell-download.json")
    }

    private func downloadManifest(in directory: URL) -> TorrentDownloadManifest? {
        guard let data = try? Data(contentsOf: manifestURL(in: directory)) else {
            return nil
        }
        return try? JSONDecoder().decode(TorrentDownloadManifest.self, from: data)
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
        if TorrentProcessRegistry.shared.isRunning(id: processID) || isAria2AlreadyRunning(in: directory) {
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
            if TorrentProcessRegistry.shared.hasTerminated(id: processID) {
                let output = TorrentProcessRegistry.shared.lastErrorOutput(id: processID)
                onProgress?(TorrentDownloadProgress(
                    downloadedBytes: progress.downloadedBytes,
                    selectedFileBytes: progress.selectedFileBytes,
                    largestPlayableFileName: progress.largestPlayableFileName,
                    failureMessage: output.isEmpty ? "aria2c 已結束，沒有可播放的緩衝檔。" : output
                ))
                throw TorrentPlaybackError.launchFailed(output.isEmpty ? "aria2c 已結束但沒有可播放的緩衝檔。" : output)
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
            return partial + fileBufferedBytes(url)
        }
    }

    private func isAria2AlreadyRunning(in directory: URL) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        let commands = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return commands
            .split(whereSeparator: \.isNewline)
            .contains { command in
                command.contains("aria2c") && command.contains("--dir=\(directory.path)")
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
            isReadyForPlayback(url)
        }
    }

    public func isReadyForPlayback(_ url: URL) -> Bool {
        guard hasAria2Sidecar(for: url) == false else {
            return false
        }
        return fileBufferedBytes(url) >= readinessMinimumBytes
    }

    public func fileBufferedBytes(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        let allocated = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize
        let logicalSize = values?.fileSize ?? 0
        return UInt64(max(0, allocated ?? logicalSize))
    }

    public func hasAria2Sidecar(for url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path + ".aria2")
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

private struct TorrentDownloadManifest: Codable {
    var title: String
    var subtitle: String
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

    func terminate(id: String) {
        lock.lock()
        let process = processes[id]
        processes[id] = nil
        terminatedProcesses.remove(id)
        errorOutputs[id] = nil
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
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
