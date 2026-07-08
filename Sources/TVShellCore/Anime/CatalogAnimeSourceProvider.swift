import Foundation

public enum AnimeSourceCatalogError: Error, Equatable, LocalizedError, Sendable {
    case noPlayableAdapter
    case missingAdapter(String)

    public var errorDescription: String? {
        switch self {
        case .noPlayableAdapter:
            "沒有已啟用且可播放的動漫來源。請在動漫來源頁啟用 Bangumi + YouTube 或其他已接入 adapter 的來源。"
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

    private let catalog: AnimeSourceCatalogState
    private let registry: AnimeSourceRegistry
    private let playableAdapters: [(instance: AnimeSourceInstance, adapter: any AnimeMediaSourceAdapter)]

    public init(catalog: AnimeSourceCatalogState, registry: AnimeSourceRegistry) {
        self.catalog = catalog
        self.registry = registry
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
        var allResults: [AnimeSearchResult] = []
        for entry in playableAdapters {
            do {
                allResults.append(contentsOf: try await entry.adapter.search(query))
            } catch {
                continue
            }
        }

        let merged = mergeSearchResults(allResults)
        guard merged.isEmpty == false else {
            throw AnimeSourceCatalogError.noPlayableAdapter
        }
        return Array(merged.prefix(60))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        for entry in playableAdapters {
            let episodes = try await entry.adapter.episodes(for: result)
            if episodes.isEmpty == false {
                return episodes
            }
        }

        throw AnimeSourceCatalogError.noPlayableAdapter
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let adapter = registry.adapter(for: episode.identity.providerID) else {
            throw AnimeSourceCatalogError.missingAdapter(episode.identity.providerID)
        }
        return try await adapter.streams(for: episode)
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
