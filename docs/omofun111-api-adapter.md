# omofun111 授權 API 接入

這個專案只接入你有授權的 API 或明確允許的資料來源。若你手上有 omofun111 的 API、token、合作文件或測試環境，可以用下面兩種方式接入。

## 需要向 API 確認的欄位

最少需要三個 endpoint：

1. 搜尋作品：輸入 `keyword`，回傳作品 `id`、名稱、封面、簡介。
2. 取得選集：輸入作品 `id`，回傳每集 `id`、集數、標題。
3. 取得播放源：輸入集數 `id`，回傳可播放 URL、畫質、必要 headers。

如果 API 有分線路，請保留 line id，例如 `omofun111-main`、`omofun111-backup`，這樣可以對到 MacTV 的動漫來源管理頁。

## 快速接入：selector JSON

如果對方給你的其實是 HTML 頁面授權解析規則，可以先用 `TVSHELL_SELECTOR_SOURCES_JSON` 接入：

```bash
export TVSHELL_SELECTOR_SOURCES_JSON='[
  {
    "id": "omofun111-authorized",
    "displayName": "omofun111 授權",
    "searchURLTemplate": "https://你的授權網域/search?keyword={keyword}",
    "resultPattern": "<a href=\"([^\"]+)\" data-id=\"([^\"]+)\">([^<]+)</a>",
    "episodePattern": "<a href=\"([^\"]+)\">第([0-9]+)集([^<]*)</a>",
    "streamPattern": "source src=\"([^\"]+)\"",
    "userAgent": "TVShell/0.1 omofun111-authorized"
  }
]'
swift run TVShell
```

這種方式適合測試，但不適合需要簽名、token、分頁、JSON 巢狀欄位或多線路的正式 API。

## 正式接入：API adapter

正式做法是在 `Sources/TVShellCore/Anime` 新增一個 `Omofun111AnimeSourceProvider`，實作 `AnimeMediaSourceAdapter`：

```swift
public struct Omofun111AnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id = "omofun111"
    public let displayName = "omofun111"
    public let resolverKind: AnimeResolverKind = .http

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        // 呼叫授權搜尋 API，轉成 AnimeSearchResult
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        // 呼叫選集 API，轉成 AnimeEpisode
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        // 呼叫播放源 API，轉成 AnimeStreamCandidate
    }
}
```

拿到 API 文件後，請先確認：

- base URL
- token 放在 header 還是 query
- 搜尋、選集、播放源 JSON 範例
- 播放 URL 是否需要 Referer、User-Agent 或簽名
- 是否限制地區、裝置、過期時間
- 是否允許內嵌播放器直接播放

有這些資料後，就能把它接進 `AnimeSourceProviderFactory.provider(...)` 的 adapters 陣列，並把 `AnimeSourceCatalog` 裡的 `omofun111` health 從 `needsAdapter` 改成 `available`。
