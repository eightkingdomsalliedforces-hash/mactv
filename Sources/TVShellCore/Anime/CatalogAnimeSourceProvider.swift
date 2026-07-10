import Foundation

public enum AnimeSourceCatalogError: Error, Equatable, LocalizedError, Sendable {
    case noPlayableAdapter
    case missingAdapter(String)

    public var errorDescription: String? {
        switch self {
        case .noPlayableAdapter:
            "沒有已啟用且可播放的動漫來源。請在動漫來源頁啟用來源。"
        case let .missingAdapter(id):
            "來源尚未接入解析 adapter：\(id)"
        }
    }
}

public struct AnimeSourceRegistry: Sendable {
    private let adaptersByID: [String: any AnimeMediaSourceAdapter]

    public init(adapters: [any AnimeMediaSourceAdapter]) {
        adaptersByID = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
    }

    public func adapter(for sourceID: String) -> (any AnimeMediaSourceAdapter)? {
        adaptersByID[sourceID]
    }
}

public struct CatalogAnimeSourceProvider: AnimeSourceProvider {
    public let id = "catalog"

    private let registry: AnimeSourceRegistry
    private let playableAdapters: [(instance: AnimeSourceInstance, adapter: any AnimeMediaSourceAdapter)]
    private let sourceResolutionTimeoutNanoseconds: UInt64
    private let episodeCache = CatalogEpisodeCache()

    public init(
        catalog: AnimeSourceCatalogState,
        registry: AnimeSourceRegistry,
        sourceResolutionTimeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.registry = registry
        self.sourceResolutionTimeoutNanoseconds = max(sourceResolutionTimeoutNanoseconds, 1_000_000)
        playableAdapters = catalog.enabledInstances.compactMap { instance in
            guard instance.definition.health.canAttemptPlayback,
                  let adapter = registry.adapter(for: instance.id)
            else {
                return nil
            }
            return (instance, adapter)
        }
    }

    public var displayName: String {
        guard playableAdapters.isEmpty == false else {
            return "動漫來源"
        }
        return playableAdapters
            .map { entry in
                let line = entry.instance.selectedLine?.title ?? "預設"
                return "\(entry.adapter.displayName) / \(line)"
            }
            .joined(separator: "、")
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let allResults = await withTaskGroup(of: SourceSearchResults.self) { group in
            for (index, entry) in playableAdapters.enumerated() {
                group.addTask {
                    SourceSearchResults(
                        sourceIndex: index,
                        results: await resolveSearch(
                            for: entry,
                            query: query,
                            timeoutNanoseconds: sourceResolutionTimeoutNanoseconds
                        )
                    )
                }
            }

            var sourceResults: [SourceSearchResults] = []
            for await entry in group { sourceResults.append(entry) }
            return sourceResults
                .sorted { $0.sourceIndex < $1.sourceIndex }
                .flatMap(\.results)
        }

        let merged = mergeSearchResults(allResults)
        guard merged.isEmpty == false else {
            throw AnimeSourceCatalogError.noPlayableAdapter
        }
        return Array(merged.prefix(60))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        let resolved = await withTaskGroup(of: [CatalogEpisodeEntry].self) { group in
            for entry in playableAdapters {
                group.addTask {
                    await resolveEpisodes(for: entry, matching: result, timeoutNanoseconds: sourceResolutionTimeoutNanoseconds)
                }
            }

            var entries: [CatalogEpisodeEntry] = []
            for await sourceEntries in group {
                entries.append(contentsOf: sourceEntries)
            }
            return entries
        }
        guard resolved.isEmpty == false else {
            throw AnimeSourceCatalogError.noPlayableAdapter
        }

        let grouped = Dictionary(grouping: resolved, by: { $0.episode.number })
        let episodes = grouped.keys.sorted().compactMap { number -> AnimeEpisode? in
            guard let entries = grouped[number]?.sorted(by: isPreferredEpisode) else {
                return nil
            }
            var episode = entries[0].episode
            episode.id = "catalog-\(number)-\(entries[0].adapterID)-\(entries[0].episode.id)"
            episodeCache.remember(entries, for: episode.id)
            return episode
        }
        guard episodes.isEmpty == false else {
            throw AnimeSourceCatalogError.noPlayableAdapter
        }
        return episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        if let entries = episodeCache.entries(for: episode.id) {
            var candidates: [AnimeStreamCandidate] = []
            for entry in entries {
                guard let adapter = registry.adapter(for: entry.adapterID) else {
                    continue
                }
                guard let streams = try? await adapter.streams(for: entry.episode) else {
                    continue
                }
                candidates.append(contentsOf: streams)
            }
            let ranked = candidates.sorted(by: isPreferredStream)
            guard ranked.isEmpty == false else {
                throw AnimeSourceCatalogError.noPlayableAdapter
            }
            return ranked
        }

        guard let adapter = registry.adapter(for: episode.identity.providerID) else {
            throw AnimeSourceCatalogError.missingAdapter(episode.identity.providerID)
        }
        return try await adapter.streams(for: episode)
    }
}

private struct CatalogEpisodeEntry: Sendable {
    var adapterID: String
    var resolverKind: AnimeResolverKind
    var episode: AnimeEpisode
}

private struct SourceSearchResults: Sendable {
    var sourceIndex: Int
    var results: [AnimeSearchResult]
}

private final class CatalogEpisodeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entriesByEpisodeID: [String: [CatalogEpisodeEntry]] = [:]

    func remember(_ entries: [CatalogEpisodeEntry], for episodeID: String) {
        lock.lock()
        entriesByEpisodeID[episodeID] = entries
        lock.unlock()
    }

    func entries(for episodeID: String) -> [CatalogEpisodeEntry]? {
        lock.lock()
        defer { lock.unlock() }
        return entriesByEpisodeID[episodeID]
    }
}

private func resolveEpisodes(
    for entry: (instance: AnimeSourceInstance, adapter: any AnimeMediaSourceAdapter),
    matching result: AnimeSearchResult,
    timeoutNanoseconds: UInt64
) async -> [CatalogEpisodeEntry] {
    await withTaskGroup(of: [AnimeEpisode].self) { group in
        group.addTask {
            do {
                let candidates = try await entry.adapter.search(AnimeSearchQuery(keyword: result.title))
                guard let match = bestMatchingResult(for: result, in: candidates) else {
                    return []
                }
                return try await entry.adapter.episodes(for: match)
            } catch {
                return []
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return []
        }

        let episodes = await group.next() ?? []
        group.cancelAll()
        return episodes.map { episode in
            CatalogEpisodeEntry(adapterID: entry.adapter.id, resolverKind: entry.adapter.resolverKind, episode: episode)
        }
    }
}

private func resolveSearch(
    for entry: (instance: AnimeSourceInstance, adapter: any AnimeMediaSourceAdapter),
    query: AnimeSearchQuery,
    timeoutNanoseconds: UInt64
) async -> [AnimeSearchResult] {
    await withTaskGroup(of: [AnimeSearchResult].self) { group in
        group.addTask {
            (try? await entry.adapter.search(query)) ?? []
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return []
        }

        let results = await group.next() ?? []
        group.cancelAll()
        return results
    }
}

private func bestMatchingResult(for result: AnimeSearchResult, in candidates: [AnimeSearchResult]) -> AnimeSearchResult? {
    candidates.max { left, right in
        matchScore(for: left, title: result.title) < matchScore(for: right, title: result.title)
    }.flatMap { matchScore(for: $0, title: result.title) > 0 ? $0 : nil }
}

private func matchScore(for candidate: AnimeSearchResult, title: String) -> Int {
    let candidateTitle = normalizedAnimeTitle(candidate.title)
    let requestedTitle = normalizedAnimeTitle(title)
    guard candidateTitle.isEmpty == false, requestedTitle.isEmpty == false else {
        return 0
    }
    if candidateTitle == requestedTitle { return 3 }
    if candidateTitle.contains(requestedTitle) || requestedTitle.contains(candidateTitle) { return 2 }
    return 0
}

private func isPreferredEpisode(_ left: CatalogEpisodeEntry, _ right: CatalogEpisodeEntry) -> Bool {
    let leftPriority = episodeSourcePriority(left)
    let rightPriority = episodeSourcePriority(right)
    if leftPriority == rightPriority {
        return left.adapterID < right.adapterID
    }
    return leftPriority > rightPriority
}

private func episodeSourcePriority(_ entry: CatalogEpisodeEntry) -> Int {
    if entry.adapterID.localizedCaseInsensitiveContains("css") { return 3 }
    switch entry.resolverKind {
    case .torrent: return 1
    case .http, .youtube, .webView: return 2
    }
}

private func isPreferredStream(_ left: AnimeStreamCandidate, _ right: AnimeStreamCandidate) -> Bool {
    let leftPriority = streamSourcePriority(left) + left.priority
    let rightPriority = streamSourcePriority(right) + right.priority
    if leftPriority == rightPriority {
        return left.quality > right.quality
    }
    return leftPriority > rightPriority
}

private func streamSourcePriority(_ stream: AnimeStreamCandidate) -> Int {
    switch stream.headers["resolver"] {
    case "web-selector": return 300
    case "torrent": return 100
    default: return 200
    }
}

private func mergeSearchResults(_ results: [AnimeSearchResult]) -> [AnimeSearchResult] {
    var mergedByTitle: [String: AnimeSearchResult] = [:]
    var order: [String] = []

    for result in results {
        let key = normalizedAnimeTitle(result.title)
        guard key.isEmpty == false else {
            continue
        }
        if let existing = mergedByTitle[key] {
            mergedByTitle[key] = betterSearchResult(existing, result)
        } else {
            mergedByTitle[key] = result
            order.append(key)
        }
    }

    return order.compactMap { mergedByTitle[$0] }
}

private func betterSearchResult(_ left: AnimeSearchResult, _ right: AnimeSearchResult) -> AnimeSearchResult {
    if (right.coverURL != nil) != (left.coverURL != nil) {
        return right.coverURL != nil ? right : left
    }
    let leftDistance = episodeCountDistance(for: left)
    let rightDistance = episodeCountDistance(for: right)
    if leftDistance != rightDistance {
        return rightDistance < leftDistance ? right : left
    }
    let leftEpisodes = left.episodeCount ?? left.episodes.count
    let rightEpisodes = right.episodeCount ?? right.episodes.count
    if leftEpisodes != rightEpisodes {
        return rightEpisodes > leftEpisodes ? right : left
    }
    if (right.score ?? 0) != (left.score ?? 0) {
        return (right.score ?? 0) > (left.score ?? 0) ? right : left
    }
    return left
}

private func episodeCountDistance(for result: AnimeSearchResult) -> Int {
    guard let expected = result.episodeCount, expected > 0 else {
        return 0
    }
    return abs(result.episodes.count - expected)
}

private func normalizedAnimeTitle(_ title: String) -> String {
    title
        .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension AnimeSourceHealth {
    var canAttemptPlayback: Bool {
        switch self {
        case .available:
            true
        case .loading, .failed, .needsCloudflare, .needsCaptcha, .needsAdapter, .disabled:
            false
        }
    }
}
