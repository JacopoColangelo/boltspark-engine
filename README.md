# Boltspark Engine

A native Windows 11 / DirectX 12 game engine and editor written in Haxe and powered by HashLink + Heaps. Its BoltUI interface is drawn with Heaps' `h2d` over the 3D scene — no browser runtime, no DOM/CSS, no SDL, and no OpenGL.

<img width="1919" height="980" alt="Screenshot 2026-11-23 145949" src="https://github.com/user-attachments/assets/8ba29c7d-0e9d-4309-9f21-461d109f5eb5" />


[![Windows portable checks](https://github.com/JacopoColangelo/boltspark-engine/actions/workflows/windows-ci.yml/badge.svg)](https://github.com/JacopoColangelo/boltspark-engine/actions/workflows/windows-ci.yml)

> **Status:** under active development. The editor runs on Windows 11 x64 with a DirectX 12 capable GPU; it is not yet a feature-complete production engine.

## Features

### Editor shell

- Native Windows desktop window booted by the HashLink VM and rendered through Heaps' DX12 driver (`h3d.impl.DX12Driver`).
- H2D-based editor chrome with menu and transform toolbars, searchable hierarchy, structured Inspector, viewport HUD, output log, and status diagnostics. Text uses runtime FreeType glyph caching at exact sizes for Inter, JetBrains Mono, and Tabler Icons.
- The Output Log focuses on actionable warnings and errors. Set `BOLTSPARK_VERBOSE_LOGS` to restore full interaction telemetry.
- Resizable hierarchy/inspector/console splitters with sizes persisted in `%LOCALAPPDATA%\Boltspark Engine\layout.json`.
- Native dark title bars and an embedded multi-resolution application icon.
- Rebindable shortcuts (Ctrl+Z/Y, Ctrl+S, Ctrl+Shift+S, Ctrl+X, F5/F6/F7, and more) in a separate native keybindings window under **File → Editor Settings → Editor Keybindings**, persisted to `%LOCALAPPDATA%\Boltspark Engine\keybindings.json`.

### Viewport

- Bounded 3D viewport with a Y-up grid, colored axes, studio lighting, scissored rendering, and two-pixel selection outlines. Clicks are converted into camera rays for picking.
- Unreal-style navigation: RMB free-look with WASD/QE flight, Shift/Ctrl speed modifiers, wheel dolly, MMB pan, Alt+LMB orbit, and **F** to frame the selection with a smooth, interruptible camera flight.
- The **PERSPECTIVE · LIT** strip opens camera settings with a numeric FOV field (30°–140°), grid toggle, and a live FPS/frame-time readout.
- The world is bounded to ±8 km per axis; transforms constrain complete geometry rather than deleting objects or capping scale.

### Transforms and gizmos

- Move (axis, plane, free-view-plane), Rotate (axis rings plus a virtual-sphere arc-ball), and Scale (axis, plane, uniform) gizmos. Shortcuts: **1**, **E**, **R**.
- WORLD/LOCAL axis-frame control, independent translation/rotation/scale snapping with step presets, **V** to suspend translation snapping, and **Ctrl+End** to snap to the grid.
- Quaternion-backed rotations with a stable Euler hint; the Inspector shows Unreal-style Rotator values in `(-180°, 180°]`.
- Inspector numeric fields support arrow stepping, drag scrubbing, keyboard entry, and one-click canonical resets. Scale can link axes to preserve proportions.
- All edits flow through the editor command path with live Inspector updates and undo/redo.

### Hierarchy, selection, and projects

- Ordered, deeply nested scene hierarchy with expand/collapse, search, inline rename, drag/drop reparenting, grouping, duplicate, copy/paste, unparent, subtree selection, and recursive delete. Structural edits preserve world transforms by default (hold **Alt** for local transforms).
- Multi-object selection from hierarchy or viewport (Ctrl/Shift+click) with one shared gizmo at the average pivot; edits apply to all selected objects as a single undoable command, and differing Inspector fields show "Multiple Values".
- Versioned project/scene files (`*.boltproject` / `*.boltscene`) with durable IDs, strict relative paths, component envelopes, reference validation, unknown-field preservation, atomic save plus backup, and a bounded undo history.
- Native file dialogs drive `ProjectSession`, which tracks dirty state and rebuilds `EditorSession` (scene graph, transforms, selection, clipboard, history) on load. The title strip shows an unsaved marker and closing confirms discarding changes.
- Open a project from the command line (`Boltspark.exe "D:\Projects\Demo.boltproject"` or `--project=…`) or opt into user-level `*.boltproject` file association with `tools\setup\register-project-association.ps1`.

### Assets and rendering

- Docked Asset Browser with a folder tree, adaptive grid/compact/detail views, multi-selection, breadcrumbs, search, type filtering, sorting, favorites, recents, real file operations, drag-to-move (Ctrl+drag to copy), and contextual shortcuts. Scene creation and loading live here rather than in the File menu.
- Built-in Cube, Sphere, Cylinder, Capsule, and Plane meshes plus White/Orange materials. Assets are reusable references with shared cached geometry and per-renderer geometry parameters, each with reset actions and undo/redo.
- OBJ, glTF, and FBX mesh import with assignable engine meshes.
- Material Editor with a metallic/smoothness PBR workflow: albedo, metallic, normal, and occlusion maps, colored emission, and tiling/offset. Texture slots accept drag-and-drop from the Asset Browser and preview live. Materials persist as version-2 `.boltmaterial` documents; schema-1 files migrate automatically.
- Deferred renderer with IBL, HDR tonemapping, FXAA, and shadow maps. Editor grid, outlines, and gizmos are depth-aware overlays.
- Engine-content thumbnails are baked offline into mipmapped bundles (`res\thumbnails\bundles`); the editor never renders a 3D scene just to draw a thumbnail.

### Runtime

- Unity-style component model: GameObjects, mandatory Transform, typed add/get/remove APIs, lifecycle dispatch, generic MeshRenderer components, primitive mesh factories, and a metadata-driven Inspector with Add Component.
- Play mode (F5/F6/F7 or the transport toolbar) runs a serialized, detached copy of the authored scene: `onStart`/`onUpdate`/`onDestroy` tick only on that copy, editor commands and selection stay frozen, and Stop discards it without touching undo history. The grid, gizmos, and selection outline hide while playing; camera navigation stays live.

## Requirements

- Windows 11 x64 and a DirectX 12 capable GPU/driver.
- Visual Studio 2022 or newer with the Desktop C++ workload and Windows SDK — only for native release builds. The build script discovers the installation with `vswhere`.
- Everything else (Haxe, HashLink, Haxelib packages, Neko) is vendored under `toolchain/`; no system-wide installation is needed.

## Build and run

Run these from the repository root in PowerShell:

```powershell
.\tools\build.ps1                      # build bin\boltspark.hl and release\Boltspark.exe
.\tools\build.ps1 -InstallDependencies # download pinned dependencies (one time, optional)
.\tools\build.ps1 -Check               # verify the Windows build environment
.\tools\build.ps1 -Run                 # run the development HashLink build
```

The development build runs through `hl.exe` and keeps its command window for logs and crash diagnostics. The packaged `release\Boltspark.exe` uses the Windows GUI subsystem. Dependency downloads are explicit and hash-verified; `release\` includes the executable, `freetype.hdll`, required runtime DLLs, and a consolidated `THIRD-PARTY-LICENSES.txt`.

### Tests

```powershell
.\tools\tests\test.ps1 -Portable                 # clean-worker compile + headless tests
.\tools\tests\test.ps1 -Build -NativeSmoke -PlayMode -CommandHistory `
  -RotationHandoff -WindowLifecycle -SplitterCapture -ProjectFiles `
  -AssetBrowser -ImportFiles -ExplorerDrop -UntitledSession `
  -AssetWatcher -FloatExplorerDrop -MaterialEditor -ImportMeshes
```

The second command runs the full suite plus DX12 interaction probes. See [TESTING.md](docs/TESTING.md) for the tracked portable/native matrix.

### Re-baking engine thumbnails

```powershell
.\tools\bake\bake-thumbnails.ps1                       # re-bake all built-in primitives
.\tools\bake\bake-thumbnails.ps1 -OutputDirectory D:\tmp\thumbs
.\tools\build.ps1                                      # rebuild to embed the new bundles
```

## Project structure

```
src/
  Main.hx                     — entry point (hxd.App), wires editor commands to engine objects
  boltspark/ui/
    BoltUI.hx                 — facade: theme + input adapter + editor shell
    core/                     — frame lifecycle, stable IDs, input state, diagnostics
    layout/                   — reusable dock geometry and local layout persistence
    render/                   — pooled draw commands + retained H2D executor
    Theme.hx                  — dark-editor color/size tokens
    UiContext.hx              — embedded fonts, native cursors, window state
    AppIcon.hx                — shared ICO decoding for HWND and title-strip branding
    UiSurface.hx / UiIcons.hx — square-edged surfaces and exact-size Tabler icon atlas
    UiText*.hx                — runtime FreeType text wrappers
    InputAdapter.hx           — central keyboard/focus/pointer reporting
    EditorShell.hx            — editor chrome layout and command callbacks
    widgets/                  — buttons, inputs, search, hierarchy, inspector, console, scrollbars
    widgets/AssetBrowser.hx    — docked three-pane browser: folder tree, grid/list, inspector
    widgets/AssetBrowserStore.hx — persisted favorites, recent assets, and view preferences
    project/AssetTypeRegistry.hx — authoritative asset kinds/extensions and internal-file rules
    windows/                  — native top-level editor-window routing and H2D content
  boltspark/project/          — versioned project/scene data, validation, atomic storage
  boltspark/engine/           — GameObject, Component, Transform, rendering components/assets
  boltspark/thumbnails/       — offline mesh thumbnail baker and mipmapped UI loader
  boltspark/editor/           — editor session/model plus viewport and gizmos
    commands/                 — object, transform, duplicate, and hierarchy history
  res/fonts/                  — embedded Inter and JetBrains Mono TTF faces
  res/icons/                  — embedded exact-size Tabler icon atlas
tests/
  native-foundation-acceptance.md
  repro/                      — headless math, UI-core, command, serialization, and native repros
  native/                     — tracked HWND, layout, DPI, reset, and performance probes
tools/
  build.ps1                   — install dependencies, check, build, and run
  bake/                       — offline DX12 thumbnail baker, host, and hxml
  assets/                     — pinned font and icon resource generators
  setup/                      — opt-in user-level .boltproject association
  tests/                      — portable CI, policy guard, and regression entry points
  font-source/                — JetBrains Mono source + OFL font license texts
  patches/                    — pinned HashLink/DX12 toolchain patches
third_party/hlfreetype/       — pinned runtime TTF/OTF rasterizer and Heaps glyph cache
third_party/tabler-icons/     — pinned icon mapping and MIT license
```

## Design rules

- **Native UI only.** The editor must not use Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, or CSS for its application UI. BoltUI is drawn by Heaps through `h2d` and receives input through Heaps' native event path.
- **DirectX 12 only.** The Windows target is HashLink + `hldx` + `-D dx12`. There is no DX11 fallback and no dependency on `hlsdl`, SDL, or OpenGL.
- **Project-local toolchain.** Haxe, HashLink, Haxelib packages, and Neko are vendored under `toolchain/`. The pinned versions and their rationale are recorded in [TOOLCHAIN_VERSIONS.md](docs/TOOLCHAIN_VERSIONS.md). Haxe 4.3.x stable cannot compile Heaps 2.1.0's DX12 driver (`hl.CArray` codegen); dev builds newer than 2025-10-23 break Heaps' event loop. The pin is the exact newest working point.
- **Commands own mutations.** UI widgets issue commands; they never mutate engine state directly.

## Documentation

**Getting started**

- [docs/README.md](docs/README.md) — foundation overview, platform rules, and environment setup
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules, layers, and data flow
- [TESTING.md](docs/TESTING.md) — portable/native test matrix and commands
- [TOOLCHAIN_VERSIONS.md](docs/TOOLCHAIN_VERSIONS.md) — pinned, hash-verified toolchain set

**Systems**

- [PROJECT_FORMAT.md](docs/PROJECT_FORMAT.md) — versioned project/scene contracts
- [COMPONENT_SYSTEM.md](docs/COMPONENT_SYSTEM.md) — GameObject/component APIs, lifecycle, and extension
- [ASSET_BROWSER.md](docs/ASSET_BROWSER.md) — three-pane Asset Browser design and verification
- [UI_CONVENTIONS.md](docs/UI_CONVENTIONS.md) — cursor, menu, popover, alignment, and icon rules
- [PERFORMANCE_BASELINE.md](docs/PERFORMANCE_BASELINE.md) — measured 15-minute idle/resize baseline
- [native-foundation-acceptance.md](tests/native-foundation-acceptance.md) — acceptance checklist with executed results

**Project reference**

- [DEVELOPMENT_PLAN.md](docs/DEVELOPMENT_PLAN.md) — master development plan (do not modify)
- [IMPLEMENTATION_SEQUENCE.md](docs/IMPLEMENTATION_SEQUENCE.md) — implementation sequencing
- [FOUNDATION_ARCHITECTURE.md](docs/FOUNDATION_ARCHITECTURE.md) — foundation architecture notes
- [M0_IMPLEMENTATION_REPORT.md](docs/M0_IMPLEMENTATION_REPORT.md) — what was done, evidence, deviations, known issues
- [NEXT_AGENT_TASK_ASSET_IMPORT.md](docs/NEXT_AGENT_TASK_ASSET_IMPORT.md) — asset-import handoff notes
- [AI_AGENT_GUIDELINES.md](docs/AI_AGENT_GUIDELINES.md) — rules for AI agents working in this repo
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) — third-party provenance, licenses, and bundling policy

## Contributing

Contributions are currently limited to the maintainer and invited collaborators. The AI-agent guidelines above document the conventions used for approved automated contributions.

## License

Boltspark Engine's own code is released under the [MIT License](LICENSE). Third-party components retain their own licenses; see [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) for provenance and the full texts shipped with the source tree and native release.
