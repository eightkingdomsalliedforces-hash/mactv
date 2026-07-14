# TVShell Android TV and Windows

This project renders Android TV and Windows from the same Compose Multiplatform UI. Layout, card ratio, spacing, focus animation, and remote commands mirror `Contracts/tvshell-contract.json` and the macOS TVShell UI.

## Android TV

Requirements: JDK 17+, Android SDK 36, and accepted Android SDK licenses.

```sh
cd platforms/compose
./gradlew :android-app:assemblePlayRelease
./gradlew :android-app:assembleLauncherRelease
./gradlew :anime-android-app:assembleRelease
```

- `play` declares `LEANBACK_LAUNCHER` and behaves as a normal Android TV app.
- `launcher` declares `LEANBACK_LAUNCHER`, `HOME`, and `DEFAULT`, so Android can offer it as the system Home app. It always includes an Android Settings card as an escape route.
- Both variants discover installed Leanback activities and launch them as separate Android processes.

Debug APKs are under `android-app/build/outputs/apk/{play,launcher}/debug/`.

The standalone TVShell Anime APK uses the exact same `AnimeBrowser` composable as the Anime route inside TVShell. Its debug artifact is under `anime-android-app/build/outputs/apk/debug/`.

## Windows

The desktop target discovers Start Menu `.lnk`/`.exe` entries and starts them as separate processes. Build and test on any JDK host; create an installer or a no-install portable ZIP on Windows:

```sh
cd platforms/compose
./gradlew :shared-ui:desktopTest
./gradlew :shared-ui:packageMsi
./gradlew :anime-desktop:packageMsi
./gradlew :shared-ui:createDistributable
./gradlew :anime-desktop:createDistributable
```

The MSI is written under `shared-ui/build/compose/binaries/main/msi/`.
The standalone Anime MSI is written under `anime-desktop/build/compose/binaries/main/msi/`.
`createDistributable` writes a self-contained app directory under each module's `build/compose/binaries/main/app/` directory. The release workflow compresses those folders as `TVShell-Windows-Portable.zip` and `TVShell-Anime-Windows-Portable.zip`; unzip either archive and run the bundled executable without installing it.

## 動畫播放核心

`shared-ui` 共用 CSS1 選集／畫質解析、BT RSS magnet 正規化、失敗站點略過、播放器命令與自動快取淘汰規則。Android 使用系統 `MediaPlayer` 接收 CSS1 HTTP headers；Windows 使用 VLC RC 介面支援播放、暫停與前後 15 秒跳轉。

獨立動畫 App 啟動後會載入 Bilibili 番劇排行，正版來源分頁提供動畫瘋與官方 YouTube；動畫瘋會開啟官方頁面並保留廣告、登入、年齡與地區限制。Windows 訂閱來源可用下列環境變數設定：

- `TVSHELL_ANISUBS_CSS1_URL`：ani-subs CSS1 首頁或訂閱入口。
- `TVSHELL_ANISUBS_BT_URL`：ani-subs BT RSS。
- `TVSHELL_MIKAN_RSS_URL`：Mikan RSS。
- `TVSHELL_DMHY_RSS_URL`：動漫花園 RSS。

未設定的來源會在畫面上顯示缺少的設定名稱，不會誤報成「沒有來源」。

Windows 預設執行 `vlc`，也可用 `TVSHELL_VLC_PATH` 指定 `vlc.exe` 的完整路徑。BT 下載器由平台層提供；下載完成後將檔案交給同一個 `AnimePlayerAdapter`，並在啟動與播放結束時呼叫 cache cleaner。
