# Third-party notices

## Inter

BoltUI's proportional bitmap-font atlases are generated from **Inter 4.1** by
Rasmus Andersson and the Inter Project Authors.

- Source: <https://github.com/rsms/inter>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/Inter-LICENSE.txt`

## JetBrains Mono

BoltUI's console bitmap-font atlas is generated from **JetBrains Mono** by
JetBrains s.r.o.

- Source: <https://github.com/JetBrains/JetBrainsMono>
- License: SIL Open Font License 1.1
- Full license text: `tools/font-source/JetBrainsMono-LICENSE.txt`

Only the pre-rasterized glyph atlases under `src/res/fonts/` are embedded in
the application. The source fonts remain under `tools/font-source/` so the
checked-in atlases can be regenerated deterministically with
`tools/generate-fonts.ps1`.
