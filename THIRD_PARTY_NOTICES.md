# Third-Party Notices

## libchewing-data

MacTV includes a generated, compact Zhuyin candidate table derived from:

- Project: `chewing/libchewing-data`
- Files: `dict/chewing/tsi.csv`, `dict/chewing/word.csv`
- Source commit: `c44e81aef24b06f1509f19e1be54c99812d0c43f`
- Copyright: Copyright (c) 2025 libchewing Core Team
- License: LGPL-2.1-or-later

Generated file:

- `Sources/TVShellCore/Input/ZhuyinChewingDictionary.swift`

The generated table is kept in a separate source file so it can be updated or
replaced independently from MacTV application code.

## FrostWire jlibtorrent

The Windows and Android TV Compose products embed FrostWire jlibtorrent
2.0.12.9 and its platform-specific libtorrent native library to resolve
magnet links and provide piece-verified, in-app streaming.

- Project: `frostwire/frostwire-jlibtorrent`
- Source: <https://github.com/frostwire/frostwire-jlibtorrent>
- Copyright: Copyright (C) 2016 FrostWire, LLC
- License: MIT

The Java wrapper and native libraries are kept at the same pinned version.
TVShell does not invoke an externally installed torrent client.

## libtorrent

The native library embedded by jlibtorrent includes libtorrent 2.0.12.0 at
revision `cb6fe6b9c28735b42edd77740a554d1709acad02`.

- Project: `arvidn/libtorrent`
- Source: <https://github.com/arvidn/libtorrent>
- Copyright: Copyright (c) 2003-2020, Arvid Norberg
- License: BSD 3-Clause

Binary redistributions retain the libtorrent copyright, conditions and
disclaimer plus the upstream puff, ed25519, SHA and routing-code notices in
the packaged `licenses/libtorrent-*-LICENSE.txt` file.

The jlibtorrent native packages also statically include OpenSSL 3.6.0
(Apache-2.0) and Boost 1.88.0 (Boost Software License 1.0). Their notices and
license terms are retained in the same packaged notice file.

## Java Native Access (JNA)

The Windows Compose player uses JNA 5.19.1 to call the embedded libVLC API.

- Project: `java-native-access/jna`
- Source: <https://github.com/java-native-access/jna>
- License: Apache-2.0 OR LGPL-2.1-or-later (TVShell uses the Apache-2.0 option)

JNA's own `META-INF/LICENSE` remains present in the packaged dependency JAR.

## AndroidX Media3

The Android TV Compose products use AndroidX Media3 1.10.1 ExoPlayer with its
HLS and DASH modules for native adaptive, direct-file and BT Range playback.

- Project: `androidx/media`
- Source: <https://github.com/androidx/media>
- Copyright: The Android Open Source Project
- License: Apache-2.0

The packaged Android notices retain the complete Apache License 2.0 text.

## VideoLAN libVLC

The Windows Compose products package the libVLC 3.0.23 engine and runtime
plugins from the official `VideoLAN.LibVLC.Windows` 3.0.23.1 NuGet package.
The VLC desktop executable and Qt interface are not included. Some retained
plugins and statically linked codecs identify as GPL-2.0-or-later, including
the FFmpeg-backed decoding and chroma modules, so TVShell treats the runtime as
a mixed LGPL/GPL redistribution instead of relying only on NuGet metadata.

- Project: VideoLAN libVLC
- Source archive: <https://download.videolan.org/pub/videolan/vlc/3.0.23/vlc-3.0.23.tar.xz>
- Binary package: <https://www.nuget.org/packages/VideoLAN.LibVLC.Windows/3.0.23.1>
- License: LGPL-2.1-or-later for libVLC; GPL-2.0-or-later and other upstream licenses for bundled modules

The exact package and source information are included beside the embedded
runtime. Every Windows release also publishes
`TVShell-Windows-Corresponding-Sources.zip` containing VLC 3.0.23, FFmpeg
4.4.5, zlib 1.3.1, GSM 1.0.13, OpenJPEG 2.5.0, LAME 3.100 and mingw-w64 /
winpthreads 10.0.0 together with VLC's matching contrib rules and patches.
TVShell links to libVLC dynamically, keeps the DLLs replaceable and does not
modify them. The packaged runtime is restricted by a pinned positive plugin
allowlist; optional x264 encoder, Lua, Dolby-surround and headphone-mixer
plugins are not redistributed.
