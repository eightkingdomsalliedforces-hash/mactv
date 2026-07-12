# TVShell

TVShell 是一個跑在 macOS 上、以 Apple TV / tvOS 大螢幕體驗為目標的 SwiftUI 應用殼。它提供可用遙控器操作的 App Launcher、內建瀏覽器、YouTube、Bilibili、影片播放器、動漫入口、設定、App 管理、動漫來源管理與遙控器學習頁。

核心目標不是做普通桌面 App，而是做一個適合電視、投影機、外接螢幕、4K / 超大螢幕觀看的「TV Mode」介面：大卡片、大焦點框、液態玻璃質感、順滑轉場、方向鍵與遙控器優先。

## 目前狀態

已完成：

- macOS SwiftPM 專案，可直接 build / run。
- tvOS 風格主畫面 Launcher。
- 大螢幕 UI scale：自動、100%、125%、150%、200%。
- 液態玻璃視覺元件與焦點放大動畫。
- 鍵盤 / 遙控器按鍵統一成 `RemoteCommand`。
- Android TV 常見按鍵邏輯：方向、OK、返回、Home、Menu、播放暫停、音量。
- 內建 WebView runtime，支援網頁縮放與虛擬滑鼠模式。
- 注音虛擬鍵盤候選表已接入新酷音 `libchewing-data` 精簡資料，基本字與常用詞覆蓋更完整。
- 可啟動 native macOS App，例如 Safari。
- 可選擇本機影片檔案作為「影片」App 來源。
- YouTube 作為獨立 App，使用 YouTube Data API 搜尋影片，再用內嵌播放器播放。
- Bilibili 作為獨立 App，參考 blbl 的 PGC 資料流，使用原生大螢幕 UI 搜尋番劇與一般影片、顯示詳情、選集/分 P，並解析 `pgc/player/web/playurl` 或 `x/player/playurl` 播放公開可看的內容。
- 動漫入口：先顯示作品封面與名稱，點進去後顯示選集，再播放。
- Bangumi 搜尋作品資料。
- 彈彈play開放彈幕網路接入，用於解析彈幕。
- 動漫來源管理頁，能顯示來源可用、待接入 adapter、需要 Cloudflare / 驗證碼等狀態。
- Selector-based 授權來源 adapter 基礎能力，可用 JSON 接入明確授權、可公開抓取的來源。

尚未完成或需要外部資料：

- 部分動畫網站來源需要正式授權 API、官方文件、或使用者提供合法 selector config，否則不會直接解析。
- 不會繞過 Cloudflare、驗證碼、DRM、登入牆或網站保護機制。
- YouTube 影片若上傳者禁止 iframe 嵌入，App 不能強制播放，只能改開 YouTube 原頁。
- Bilibili 仍受 B 站 API、登入、會員、地區與版權限制影響；App 不繞過限制，只會顯示 API 回傳錯誤或早停提示。
- API key / Cookie 可寫入 `credentials.json` 保存，不需要每次輸入。

## 系統需求

- macOS 14 或更新版本
- Swift 6 toolchain
- 建議 1080p、2K、4K 或更大螢幕
- 若要控制其他 macOS App，請在系統設定中授權輔助使用權限

## 快速開始

在專案根目錄執行：

```bash
swift run TVShell
```

建置 release 版本：

```bash
swift build -c release --product TVShell
```

執行檢查：

```bash
swift run TVShellChecks
```

## GitHub Release

GitHub Actions 會在 push / PR 時自動執行檢查與 release build。每次 push 到 `main` 並建置成功後，workflow 會自動建立或更新 `latest` GitHub Release，並上傳 `TVShell` zip。

若要發布固定版本，建立並推送 `v*` tag：

```bash
git tag v0.1.0
git push origin v0.1.0
```

workflow 會打包 `TVShell` release binary；`main` 會更新 `latest` release，`v*` tag 會發布到對應版本的 GitHub Release。

## 內建播放器

動漫播放會依格式自動選擇播放核心：

- `mp4`、`m4v`、`mov`、`m3u8` 等 AVFoundation 原生格式會走 `AVPlayer`。
- `mkv`、`avi`、`webm`、`flv`、`wmv`、`ts`、`m2ts` 會走內建 VLC 播放 surface，不再交給 macOS 外部 App，避免誤開 Baidu Netdisk 或其他程式。

內建 VLC surface 會動態載入 `VLCKit.framework`。GitHub Release 會在建置時從 VideoLAN 的 `Packaging/VLCKit.json` 取得最新版 macOS VLCKit binary，並自動放在：

```text
TVShell.app/Contents/Frameworks/VLCKit.framework
```

若本機開發版尚未打包 framework，但已安裝全域 `/Library/Frameworks/VLCKit.framework` 或 VLC.app 內含 VLCKit，也會作為 fallback。遙控器的播放/暫停、OK、左右快轉/倒退會同步控制 VLC surface。

### 播放與正版來源遙控

- 動畫、YouTube、Bilibili 播放時，方向鍵上／下調整音量；左右快轉／倒退。
- 播放 HUD 在遙控操作時顯示，三秒沒有操作後自動隱藏；右上角狀態時鐘在播放期間隱藏。
- 動畫首頁第一排按上進入頂部分頁，左右切換、OK 進入；官方 YouTube 結果會跟隨焦點捲動。
- 官方 YouTube 使用 TVShell 原生結果與詳情頁，播放保留 YouTube 官方 embed、廣告與限制。
- 動畫瘋使用持久官方 WebView。OK／播放鍵控制播放、左右操作官方播放器、上下調音量、Menu 送出全螢幕快捷鍵。可見的年齡確認會以一般按鈕點擊一次。
- TVShell 不跳過動畫瘋廣告、不提取串流、不偽造會員權限，也不直接修改官方播放器時間。

### Bing 每日圖片與彈幕控制

- 壁紙選項包含 Bing 每日圖片；圖片與署名會快取，離線或更新失敗時保留最後成功圖片。
- 長按 Menu 開啟控制中心，可調整彈幕顯示、大小、速度、透明度與密度。
- 控制中心的彈幕變更立即套用並寫入設定，動畫與 Bilibili 播放共用同一份設定。

VLCKit 由 VideoLAN 發布，採用 `LGPL-2.1-or-later`。Release app 會在 `Contents/Resources/ThirdPartyNotices.txt` 保留來源與授權資訊。來源：[`VideoLAN VLCKit`](https://code.videolan.org/videolan/VLCKit)。

## API、登入與 credentials.json

App 啟動時會自動在使用者 home 目錄建立範例檔。也可以進入「設定」頁，把焦點移到「憑證檔案」並按 OK 重載：

```text
~/credentials.json
```

可以直接編輯這個檔案：

```json
{
  "bilibili" : {
    "cookie" : "SESSDATA=...; bili_jct=...;"
  },
  "dandanplay" : {
    "appID" : "",
    "appSecret" : ""
  },
  "youtube" : {
    "apiKey" : "你的 YouTube Data API key"
  }
}
```

保存後回到「設定」頁，在「憑證檔案」按 OK 重載即可。沒有 credentials 檔案時，App 仍會讀取環境變數作為 fallback。

### YouTube

YouTube App 使用 YouTube Data API v3 搜尋影片。建議寫入 `credentials.json` 的 `youtube.apiKey`。也可以使用環境變數：

```bash
export TVSHELL_YOUTUBE_API_KEY="你的 YouTube Data API key"
swift run TVShell
```

官方文件：

- [YouTube Data API v3](https://developers.google.com/youtube/v3/docs)
- [Search: list](https://developers.google.com/youtube/v3/docs/search/list)

### Bangumi

動漫作品搜尋使用 Bangumi API：

- [Bangumi API](https://bangumi.github.io/api/)

目前使用 `/v0/search/subjects` 搜尋動畫條目，取得作品名稱、簡介、集數與封面圖。

### 彈彈play開放彈幕網路

彈幕使用「彈彈play開放彈幕網路」接入，官網為 [www.dandanplay.com](https://www.dandanplay.com/)。

### Bilibili

Bilibili App 會搜尋番劇與一般影片：

- 番劇搜尋：`x/web-interface/search/type?search_type=media_bangumi`
- 一般影片搜尋：`x/web-interface/search/type?search_type=video`
- 一般影片詳情：`x/web-interface/view`
- 播放地址：`pgc/player/web/playurl` 或 `x/player/playurl`

如果內容需要登入、會員、地區權限或被版權限制，請把登入後瀏覽器中的 Bilibili Cookie 寫入 `credentials.json` 的 `bilibili.cookie`。播放若在幾秒內結束，播放器會顯示早停提示，而不是停在黑畫面。

需要設定 AppId 與 AppSecret：

```bash
export TVSHELL_DANDANPLAY_APP_ID="你的 AppId"
export TVSHELL_DANDANPLAY_APP_SECRET="你的 AppSecret"
swift run TVShell
```

官方文件：

- [彈彈play開放彈幕網路](https://doc.dandanplay.com/open/)

## 遙控器按鍵

所有輸入會先轉成同一套 `RemoteCommand`，再交給 Launcher、設定頁、WebView、影片播放器或動漫播放器處理。

| 功能 | 鍵盤 | Android TV / HID 常見鍵 |
| --- | --- | --- |
| 上下左右 | 方向鍵 | D-pad |
| 確認 | Enter / Return | OK / Select |
| 返回 | Esc | Back |
| Home | Command + H | Home |
| Menu | Command + M | Menu / Options / 三條線 |
| 播放暫停 | Space | Play / Pause |
| 快轉 | 媒體快轉鍵 | Fast Forward |
| 倒退 | 媒體倒退鍵 | Rewind |
| 音量 | 系統音量鍵 | Volume Up / Down / Mute |

如果遙控器按下後輸出注音或文字，通常代表 macOS 目前在中文輸入法中，該按鍵被當成文字輸入。請切到英文輸入法後再測，或到「遙控器」頁面觀察收到的按鍵。

Android TV 原廠遙控器有些只會和對應電視盒配對，macOS 藍牙可能看不到或無法完成配對。這種情況 App 收不到任何 HID 事件，無法靠按鍵映射修復。TVShell 會在啟動時開啟 Wi-Fi 網路遙控器，可到「遙控器」頁面查看網址，例如：

```text
http://你的-Mac-IP:8787
```

用同一 Wi-Fi 的 Android 手機瀏覽器打開後，就能操作方向、OK、Back、Home、Menu、播放/暫停與音量。第一次使用時 macOS 可能會詢問是否允許本機網路連線，請允許。

## 內建 App

預設 App 由 `Sources/TVShellCore/Launcher/SeedApps.swift` 定義：

- YouTube
- Bilibili
- Apple 網站
- 瀏覽器
- Safari
- 影片
- 動畫
- 動漫來源
- 遙控器
- 設定
- 管理

App 管理頁可以控制 App 是否顯示。後續可擴充新增、刪除、排序、圖示、自訂啟動路徑、自訂網址與控制模式。

## 動漫來源

目前動漫架構分成三層：

1. 作品資料：Bangumi 搜尋作品、取得封面與名稱。
2. 播放候選：YouTube Data API、Mikan/動漫花園 RSS、Jellyfin/Emby 或合法來源 adapter 提供影片候選。
3. 彈幕：彈彈play開放彈幕網路依作品與集數解析彈幕。

來源 adapter 需要符合以下其中一種方式：

- 來源提供官方 API。
- 使用者擁有授權，並提供 API 文件或可用 token。
- 使用者提供合法 selector JSON，來源頁面不需要繞過 Cloudflare、驗證碼、DRM 或登入限制。

omofun111 如果你有授權 API 或 token，請看 [`docs/omofun111-api-adapter.md`](docs/omofun111-api-adapter.md)。裡面列了需要的 endpoint、JSON 欄位、selector 快速接入方式，以及正式 API adapter 要實作的位置。未接入或需要 Cloudflare/驗證碼/待修復的來源不會出現在預設來源清單。

內建來源：

- `Bangumi + YouTube`：Bangumi 作品資料搭配 YouTube Data API 搜尋授權影片，預設啟用。
- `Mikan Project`：RSS/BT 搜尋來源，預設不自動啟用。可在動漫來源頁啟用；會解析磁力/種子候選並交給 BT 邊下邊播流程。
- `動漫花園`：RSS/BT 搜尋來源，預設不自動啟用；同樣提供 torrent 候選。
- `ani-subs BT 訂閱`：讀取 animeko 相容 `bt1.json` 影音源訂閱，預設不自動啟用。舊設定檔若缺少此來源，啟動時會自動補回。
- `ani-subs CSS1`：讀取 animeko 相容 `css1.json` web-selector 來源，預設不自動啟用。已支援搜尋頁、選集頁、播放頁中的 mp4/m3u8/flv/mkv URL 解析；需要 Cloudflare、驗證碼、登入或 DRM 的站點會自動略過。單一 CSS1 來源若 timeout 或解析失敗，會自動寫入 `~/Library/Application Support/TVShell/css1-disabled-sources.json` 停用，下次不再載入；要重新嘗試可刪除此檔案。舊版 `MacTV` 資料會在首次啟動安全複製到 TVShell，舊目錄不會自動刪除。
- `Jellyfin`：自有媒體庫來源。設定環境變數後會自動註冊並可啟用：

```bash
export TVSHELL_JELLYFIN_BASE_URL="https://你的-jellyfin"
export TVSHELL_JELLYFIN_API_KEY="你的 API key"
export TVSHELL_JELLYFIN_USER_ID="可選 user id"
```

- `Emby`：自有媒體庫來源。設定方式：

```bash
export TVSHELL_EMBY_BASE_URL="https://你的-emby"
export TVSHELL_EMBY_API_KEY="你的 API key"
export TVSHELL_EMBY_USER_ID="可選 user id"
```

可以透過 `TVSHELL_SELECTOR_SOURCES_JSON` 加入 selector 來源，例如：

```bash
export TVSHELL_SELECTOR_SOURCES_JSON='[
  {
    "id": "example-source",
    "displayName": "Example Source",
    "searchURLTemplate": "https://example.com/search?q={keyword}",
    "resultPattern": {
      "pattern": "<a href=\"([^\"]+)\" data-id=\"([^\"]+)\">([^<]+)</a>",
      "idGroup": 2,
      "urlGroup": 1,
      "titleGroup": 3
    },
    "episodePattern": {
      "pattern": "<a href=\"([^\"]+)\">第([0-9]+)集([^<]*)</a>",
      "idGroup": 2,
      "urlGroup": 1,
      "titleGroup": 3
    },
    "streamPattern": {
      "pattern": "source src=\"([^\"]+)\"",
      "urlGroup": 1,
      "qualityGroup": null
    },
    "userAgent": "TVShell/0.1 SelectorAnimeSource"
  }
]'
swift run TVShell
```

## 主要模組

| 模組 | 路徑 | 說明 |
| --- | --- | --- |
| App 入口 | `Sources/TVShell/TVShellApp.swift` | 建立 SwiftUI App 與輸入路由 |
| App 狀態 | `Sources/TVShellCore/App/AppState.swift` | 管理 runtime、焦點、設定、App 開啟 |
| Launcher | `Sources/TVShellCore/Launcher` | 主畫面、App 卡片、分類與焦點移動 |
| Design | `Sources/TVShellCore/Design` | 液態玻璃、動畫、TV 尺寸系統 |
| Input | `Sources/TVShellCore/Input` | 鍵盤、HID、媒體鍵到 `RemoteCommand` 的映射 |
| Runtime | `Sources/TVShellCore/Runtime` | WebView、Native App、影片播放、輔助使用控制 |
| YouTube | `Sources/TVShellCore/YouTube` | YouTube Data API、搜尋、播放器頁 |
| Bilibili | `Sources/TVShellCore/Bilibili` | Bilibili PGC 番劇搜尋、詳情、選集與播放 |
| Anime | `Sources/TVShellCore/Anime` | Bangumi、彈彈play、來源 catalog、adapter、動漫 UI |
| Settings | `Sources/TVShellCore/Settings` | 設定、遙控器、App 管理、動漫來源管理 |
| Checks | `Sources/TVShellChecks` | 專案檢查入口 |

## 大螢幕設計原則

- 所有可操作元件必須能用方向鍵聚焦。
- 焦點狀態要足夠明顯：放大、光暈、陰影、玻璃高亮。
- 文字與卡片要以遠距離觀看為優先。
- 版面必須適配 1080p、2K、4K 與更大視窗。
- 網頁 runtime 預設放大，並提供鍵盤模式與虛擬滑鼠模式。
- 動畫應該使用短、順、自然的 tvOS 風格轉場，避免桌面 App 式的小控件感。

## 輔助使用權限

若要控制任意 macOS App，必須允許 TVShell 使用 macOS 輔助使用：

1. 開啟「系統設定」
2. 進入「隱私權與安全性」
3. 進入「輔助使用」
4. 允許 TVShell 或目前執行中的 Terminal / Xcode

授權後，後續可以擴充：

- 將遙控器方向鍵映射成目前 App 的焦點移動。
- OK 對應滑鼠點擊或鍵盤 Enter。
- Back 對應 Esc、Command + [ 或返回主畫面。
- Home 強制回到 TVShell 主畫面。
- Menu 開啟 TVShell 控制層。

## 開發規範

- 優先保持 macOS 原生：SwiftUI + AppKit + WebKit。
- UI 必須先考慮遙控器與大螢幕，不以滑鼠小點擊為主。
- 新增 App 或頁面時，要接入 `RemoteCommand`。
- 新增動漫來源時，要走 adapter，不要把來源邏輯塞進 UI。
- 不接入未授權、需要繞過保護機制、或不穩定的抓取方式。
- 每次改動後至少跑：

```bash
swift run TVShellChecks
swift build -c release --product TVShell
```
