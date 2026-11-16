# Tabler Icons

BoltUI uses selected icons from **Tabler Icons v3.52.0**, released on
2026-11-14 from commit `4581ad20d8d13e24f6c3be75caaea1c4ad6c4b35`.

- Project: <https://tabler.io/icons>
- Source: <https://github.com/tabler/tabler-icons/tree/v3.52.0>
- Raster source package: `@tabler/icons-png@3.52.0`
- License: MIT; see [`LICENSE`](LICENSE)
- Runtime atlas: `src/res/icons/tabler_ui.png`
- Atlas SHA-256: `775B63C2E56AC7693A1C7EBD5FBA54F5D485E702169BB8B9631A7BA1B11AAA52`
- Regeneration: `tools/generate-tabler-icons.ps1`

The generator downloads the official 240px PNG render of each pinned SVG and
creates dedicated 6–16px alpha-mask rasters. The generated atlas is embedded in
the HashLink bytecode/native executable, so Boltspark has no package-manager,
network, browser, or loose icon-file dependency at runtime.

## BoltUI mapping

| BoltUI kind | Tabler icon |
|---|---|
| `Add` | `outline/plus` |
| `Trash` | `outline/trash` |
| `Cube` | `outline/cube` |
| `Search` | `outline/search` |
| `Play` | `outline/player-play` |
| `Pause` | `outline/player-pause` |
| `Stop` | `outline/player-stop` |
| `Move` | `outline/arrows-move` |
| `Rotate` | `outline/rotate-clockwise` |
| `Scale` | `outline/arrows-diagonal-2` |
| `ChevronDown` | `outline/chevron-down` |
| `ChevronRight` | `outline/chevron-right` |
| `Console` | `outline/terminal-2` |
| `Sliders` | `outline/adjustments-horizontal` |
| `Hierarchy` | `outline/hierarchy-2` |
| `Close` | `outline/x` |
| `Grid` | `outline/grid-4x4` |
| `More` | `outline/dots` |
| `ChevronUp` | `outline/chevron-up` |
| `StatusDot` | `filled/point` |
| `Link` | `outline/link` |
| `Unlink` | `outline/unlink` |
| `Reset` | `outline/restore` |
| `Folder` | `outline/folder` |
| `Scene` | `outline/file-description` |
