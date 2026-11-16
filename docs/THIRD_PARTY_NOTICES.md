# Third-party notices

## Build-tool-only Haxe runtime libraries

The project-local pinned Haxe development compiler is accompanied by the
official Windows binary distribution's `libmbedcrypto`, `libmbedtls`,
`libmbedx509`, PCRE2, and zlib runtime DLLs. They are needed only to start
`toolchain/haxe-dev/haxe.exe` (including on hosted CI) and are not staged into
`release/Boltspark.exe` or shipped as Boltspark runtime dependencies.

- Haxe compiler distribution: <https://build.haxe.org/builds/haxe/windows64/>
- Mbed TLS: Apache License 2.0, <https://github.com/Mbed-TLS/mbedtls>
- PCRE2: BSD 3-Clause license, <https://github.com/PCRE2Project/pcre2>
- zlib: zlib license, <https://zlib.net/>

Exact file hashes are recorded in `docs/TOOLCHAIN_VERSIONS.md`.

## Tabler Icons

BoltUI embeds selected **Tabler Icons 3.52.0** glyphs by Paweł Kuna and the
Tabler Icons contributors. The official SVG-derived PNGs are pre-rasterized at
the editor's exact 6–16px sizes into `src/res/icons/tabler_ui.png`; no Tabler
package or network access is required at runtime.

- Project: <https://tabler.io/icons>
- Source: <https://github.com/tabler/tabler-icons/tree/v3.52.0>
- License: MIT
- Full license text: `third_party/tabler-icons/LICENSE`
- Pinned icon mapping and regeneration details: `third_party/tabler-icons/README.md`

## Inter

BoltUI embeds **Inter 4.1** TTF faces by Rasmus Andersson and the Inter Project
Authors. FreeType rasterizes the Regular, SemiBold, and Bold faces at the exact
pixel size requested by the editor and caches glyphs internally at runtime.

- Source: <https://github.com/rsms/inter>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/Inter-LICENSE.txt`

## JetBrains Mono

BoltUI embeds **JetBrains Mono Regular** by JetBrains s.r.o. FreeType rasterizes
it at the existing exact 12px size for console lines and numeric values, with
fixed-width advances and an on-demand glyph cache.

- Source: <https://github.com/JetBrains/JetBrainsMono>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/JetBrainsMono-LICENSE.txt`

The runtime resource can be restored byte-for-byte from the pinned source with
`tools/generate-fonts.ps1`.

## hlfreetype

The HashLink/Heaps FreeType integration is **hlfreetype 1.0.0** by dtwotwo,
pinned to commit `56c8aac44b1874f0e50c61d970fe8c171c3c5e70` with the local integration
changes documented in `third_party/hlfreetype/UPSTREAM.md`.

- Source: <https://github.com/dtwotwo/hlfreetype>
- License: MIT
- Full license text: `third_party/hlfreetype/LICENSE`

## FreeType

Glyph rasterization uses **FreeType 2.14.3**, statically linked into the
project-local `freetype.hdll`. No system-wide FreeType installation is used.

This software is based in part on the work of the FreeType Team.

- Source: <https://github.com/freetype/freetype>
- License: FreeType License
- Full license text: `third_party/hlfreetype/FreeType-LICENSE.txt`
