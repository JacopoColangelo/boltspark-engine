# Third-party notices

## Inter

BoltUI embeds **Inter 4.1** TTF faces by Rasmus Andersson and the Inter Project
Authors. FreeType rasterizes the Regular, SemiBold, and Bold faces at the exact
pixel size requested by the editor and caches glyphs internally at runtime.

- Source: <https://github.com/rsms/inter>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/Inter-LICENSE.txt`

## JetBrains Mono

BoltUI's console bitmap-font atlas is generated from **JetBrains Mono** by
JetBrains s.r.o.

- Source: <https://github.com/JetBrains/JetBrainsMono>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/JetBrainsMono-LICENSE.txt`

The fixed console atlas can be regenerated with `tools/generate-fonts.ps1`.

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
