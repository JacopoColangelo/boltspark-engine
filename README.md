# Boltspark Engine — Windows 11 / DirectX 12 native foundation

Boltspark is a native Windows game engine and editor built on **HashLink + Heaps + DirectX 12**. The application UI (BoltUI) is rendered by Heaps through `h2d` over the 3D scene — it is **not** HTML, DOM, CSS, Electron, NW.js, CEF, WebView, SDL, or OpenGL, and none of those technologies may ever enter this codebase (see "Hard platform policy" below).

## What is working (M0)

- A native Windows 11 x64 desktop window ("Boltspark Engine") booted by the HashLink VM, rendering through the **DirectX 12** Heaps driver (positively identified at runtime as `h3d.impl.DX12Driver`).
- An orange sample GameObject composed from Transform + MeshRenderer components
  in `s3d`, behind a native `h2d` editor chrome overlay.
- A bounded 3D viewport clipped with Heaps' render-zone scissor; viewport clicks are converted into camera rays and synchronize cube selection with the hierarchy.
- A compact native BoltUI editor shell with exact-size runtime FreeType glyph caching for Inter and JetBrains Mono, exact-size Tabler Icons, crisp vector surfaces, menu/transform/transport toolbars, searchable hierarchy, structured Inspector sections, viewport HUD, output log, and status diagnostics. The Output Log stays focused on actionable warnings and errors instead of echoing routine selections, tool switches, and transform edits; launch with `BOLTSPARK_VERBOSE_LOGS` set to restore detailed interaction telemetry for diagnosis.
- The bounded 3D viewport has a Y-up editor grid, colored axes, studio lighting, and scale-invariant two-pixel selected-object wireframe feedback while retaining viewport ray picking and drag/drop placement.
- Viewport camera controls follow Unreal-style activation: RMB captures free-look and enables WASD/QE flight, Shift/Ctrl speed modifiers, and wheel speed changes; an idle wheel over the viewport dollies in/out, MMB pans, Alt+LMB orbits in the expected tumble direction, and **F** smoothly frames the entire selection using the complete world-space bounds of every selected object. Focus is a selection command rather than a navigation command: it works with any active selection even when the pointer is over a panel, while text entry and active viewport gestures still suppress it. Focus flights use a fixed-duration ease so objects remain responsive even across the full editor world, and direct camera input interrupts them immediately. Clicking the **PERSPECTIVE · LIT** strip opens camera settings with a transform-style numeric FOV field (30°–140°): click to type an exact value, drag to scrub, or use the arrow buttons to step; evenly spaced checkbox rows toggle the editor grid and performance stats. Enabling performance stats shows a frameless live FPS / frame-time readout in the viewport's top-right corner.
- All three transform tools drive viewport gizmos: Move offers axis, two-axis plane, and center free-view-plane drags; Rotate offers axis rings plus a true virtual-sphere omni arc-ball; Scale offers axis/plane/uniform scaling. Arc-ball motion keeps the same response and rotation axis when the pointer enters or exits its virtual sphere, while large coalesced pointer deltas are subdivided so fast rim crossings cannot collapse. Successive Bell-surface points preserve off-center view-axis roll, while a linear pointer-travel angle keeps long relative-mode drags unbounded. Its accumulated quaternion remains untouched and normalized during long drags; an internal per-object Euler hint selects a stable equivalent branch, while the Inspector presents Unreal-style Rotator values in `(-180°, 180°]`. A clickable WORLD/LOCAL viewport control changes the shared axis frame (WORLD is the default), all changes flow through the editor command path with live inspector updates, and the default shortcuts are **1** (Move), **E** (Rotate), and **R** (Scale).
- Viewport translation, rotation, and scale snapping have independent toolbar toggles and step presets. Rotation rings snap their captured axis angle directly, so they remain stable and single-axis after an arbitrary omni arc-ball tumble; the arc-ball itself stays freeform. Holding **V** temporarily suspends translation snapping, while **Ctrl+End** snaps the selection to the translation grid. Keyboard actions—including **Ctrl+Z/Ctrl+Y** Undo/Redo, **Ctrl+S** Save Current Scene, **Ctrl+Shift+S** Save All, and **Ctrl+X** Cut Asset—can be rebound from **File → Editor Settings → Editor Keybindings**, which opens as a separate native application window; the list is grouped into Tools, Viewport, Editing, Snapping, Clipboard, and Files categories with dividers, and bindings persist in `%LOCALAPPDATA%\Boltspark Engine\keybindings.json` and synchronize back to the live editor.
- The release executable, taskbar, native windows, and main editor title strip share the embedded multi-resolution Boltspark icon. The main editor and auxiliary application windows use native Windows dark title bars. Opening the File menu prepares the small keybindings host in the background; closing its window hides it while retaining the HWND, DX12 device, and font cache, so subsequent opens do not launch or initialize another process.
- The hierarchy, inspector, and console regions can be resized with draggable splitters; panel sizes stay within usable bounds, adapt to window resizing, and persist in `%LOCALAPPDATA%\Boltspark Engine\layout.json`.
- Scene objects form an ordered, deeply nested hierarchy. Rows expand and collapse, retain ancestor paths while searching, support inline rename and multi-row drag/drop reparenting, and expose create-child, empty-parent grouping, duplicate, copy/paste, unparent, subtree-selection, and recursive delete actions. Structural edits preserve world transforms by default, can explicitly preserve local transforms with **Alt**, and undo/redo restores exact parent, sibling, transform, identity, and selection state.
- Multi-object selection works from both the hierarchy and the viewport (Ctrl+click toggles, Shift+click adds). One shared transform gizmo sits at the selection's average pivot and applies a single move/rotate/scale delta to every selected object as one undoable command. The Inspector keeps showing components common to the selection, displays "Multiple Values" for fields that differ, and applies edits to all selected objects.
- MeshRenderer exposes type-aware asset pickers for mesh and material. The built-in catalog offers Cube, Sphere, Cylinder, Capsule, and Plane meshes plus a Default Material (assigned automatically). Mesh/material assets stay reusable references — each entity owns its own render instance while sharing cached geometry — and picker changes update the viewport immediately. The Add palette and hierarchy creation menus list every built-in primitive, and each primitive publishes its own Inspector geometry parameters (sphere sides/rings/radius, cylinder sides/radius/height with a capped/hollow toggle, cube/plane/capsule sizes) stored per renderer instance. Every parameter row has a reset action, and parameter edits participate in undo/redo (one history entry per scrub gesture; multi-selection edits commit a single composite entry).
- Inspector numeric fields support compact up/down stepping, horizontal drag scrubbing, and keyboard editing with focus, validation, Enter-to-apply, and Escape-to-cancel.
- Position, Rotation, and Scale rows have one-click canonical resets; Scale can link its axes to preserve the current X/Y/Z proportions across field edits and gizmo drags, while signed values and pivot-crossing gizmo drags support mirrored transforms without singular zero scale.
- The editor world is bounded to ±8 km from the origin on every axis. Every transform path constrains complete transformed geometry instead of deleting objects or imposing an arbitrary scale-factor cap; the viewport far plane covers the bounded world, and camera-enclosing meshes remain visible from inside while editing.
- Editor commands flow UI → command → engine object (widgets never mutate engine state directly).
- The reusable BoltUI seed now has explicit frame boundaries, scoped stable IDs,
  persistent widget state, backend-independent input snapshots, duplicate-ID and
  invalid-layout diagnostics, deterministic row/column/stack geometry, and a
  pooled draw-command path used by the editor chrome.
- Versioned project/scene serialization foundations are in place with durable
  IDs, strict relative paths, generic versioned component envelopes, reference
  validation, unknown-field preservation, atomic save + backup, fixtures, and a
  bounded undo/redo command history. A renderer-independent `EditorSession` now
  owns the ordered scene graph, local affine transforms, selection, clipboard,
  and history. Parent references, sibling order, exact quaternion/shear state,
  and attached components map to and from `SceneDocument`.
- Integrated project/scene open/save is wired to the File menu: native Windows
  file dialogs (from the bundled `ui.hdll`) drive `ProjectSession`, which owns
  the current `*.boltproject`/`*.boltscene` documents, resolves relative scene
  paths, tracks dirty state, rebuilds the editor session on load, and routes all
  writes through atomic save + backup. The File menu is limited to project
  operations plus saving the current scene; scene creation and loading live in
  the docked **Asset Browser** (Unreal-style Levels workflow). It is the first
  bottom-dock tab and shows a grid of tiles: it scans real files under the
  project root into a collapsible folder tree (rows show folder names, not
  paths) with Tabler folder/scene glyphs, and
  supports Add → Scene/Folder, double-click to open, F2/inline Rename (folders
  too), drag an asset onto a folder for a Move/Copy choice, Move To / Copy To
  submenus, Ctrl+C/Ctrl+V/Ctrl+X clipboard, and Delete. Empty folders appear in
  the folder column, and the grid scrolls when assets exceed the dock height. Each scene gets a unique name/path so creating
  one never overwrites another, and rename/delete keep the manifest and files
  consistent. The title strip shows
  the project and scene with an unsaved marker, and closing confirms discarding
  unsaved work. The editor also accepts a `*.boltproject` path on the command
  line (or `--project=…`) and opens it at startup; an opt-in user-level Windows
  association script makes double-clicking the file launch the packaged editor.
- A Unity-style component runtime now provides generic GameObjects, mandatory
  Transform components, typed add/get/remove APIs, lifecycle dispatch,
  component-preserving history/serialization, generic MeshRenderer components,
  primitive mesh factories, and a metadata-driven component Inspector with an
  Add Component command. Cubes are ordinary GameObjects rather than object kinds.
- The docked Asset Browser is now a professional two-pane editor component:
  hierarchical folder tree with draggable/nestable folders, adaptive grid /
  compact / detail views with multi-selection, breadcrumbs and history, live
  search, type filtering and sorting, favorites and recent assets, real
  generic file/folder operations with confirmation, direct drag-to-move
  (Ctrl+drag to copy), and contextual keyboard shortcuts. It advertises only
  the engine's one loadable format (`.boltscene`) while still showing unknown
  files as generic files ([`docs/ASSET_BROWSER.md`](docs/ASSET_BROWSER.md)).

## Hard platform policy

The editor must not use Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, or CSS for its application UI. On Windows the graphics backend is exclusively `hldx` + `-D dx12`; `hlsdl`, SDL, and OpenGL are not dependencies and must not be added.

## Project-local toolchain

The Haxe/HashLink toolchain and Haxelib dependencies are project-local. Building a native Windows release additionally requires Visual Studio 2022 or newer with the Desktop C++ workload and Windows SDK. The build script discovers the installed Visual Studio instance with `vswhere`; it does not depend on a specific edition or install path.

| Path | Contents |
|---|---|
| `toolchain/haxe-dev` | **Pinned compiler: Haxe 5.0.0-preview.1+dcda605** (dev build dated 2025-10-23) — the only verified compiler that can build Heaps 2.1.0 + HashLink 1.16 + DX12. User-ratified 2026-11-11. |
| `toolchain/haxe` | Haxe 4.3.7 stable (reference only; **cannot** run the DX12 driver — do not build with it) |
| `toolchain/hashlink` | Official HashLink **1.16.0** win64 binary (with `directx.hdll`, `dx12.hdll`, `libhl.dll`, `dxcompiler.dll`, `dxil.dll`) |
| `toolchain/haxelib` | Project-local Haxelib repository (heaps 2.1.0, format 3.8.0, hldx 1.16.0, HashLink/C 1.16.0) |
| `toolchain/neko` | Neko runtime (needed by `haxelib.exe`) |
| `third_party/hlfreetype` | Pinned HashLink FreeType 1.0.0 integration; statically links project-local FreeType 2.14.3 into `freetype.hdll` |
| `WinPixEventRuntime` | Pinned x64 native dependency installed by `tools/build.ps1 -InstallDependencies` |

Full version lock, hashes, and the reasoning behind the compiler pin: [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md).

### Why not Haxe 4.3.x stable?

Heaps 2.1.0's DX12 driver requires `hl.CArray`, whose correct codegen exists only in Haxe development builds with native `hl_carray` support. Haxe 4.3.7 has no such support and its stdlib references C primitives that no released HashLink exports. Dev builds newer than 2025-10-23 break Heaps 2.1.0 (`EventLoop` refactor). The pin is the exact newest-working point; upgrading requires re-verification of the whole set.

## Build and run (Windows PowerShell)

```powershell
.\tools\build.ps1                      # build bin\boltspark.hl and release\Boltspark.exe
.\tools\build.ps1 -InstallDependencies # install missing pinned dependencies (optional)
.\tools\build.ps1 -Check              # validate the Windows build environment
.\tools\build.ps1 -Run                # run the development HashLink build
.\tools\test.ps1 -Portable            # clean-worker compile + headless tests
.\tools\test.ps1 -Build -NativeSmoke -CommandHistory -RotationHandoff -WindowLifecycle -SplitterCapture -ProjectFiles -AssetBrowser  # full tests + DX12 interaction probes
```

The single script sets the Haxe/HashLink environment per-session and uses project-local dependencies. Dependency installation is explicit; it downloads the pinned HashLink/C library, PIX runtime, and verified FreeType source only when requested. `-Check` reports the detected Visual Studio/MSBuild installation and verifies it is usable. Native builds select the matching toolset (VS2026 `v145`, VS2022 `v143`). The generated `release\` folder contains the executable, `freetype.hdll`, one consolidated `THIRD-PARTY-LICENSES.txt`, and its other required runtime files. Canonical upstream license files remain separate in the source tree.

The development build runs through `hl.exe` and retains its command window for logs and crash diagnostics. The packaged `release\Boltspark.exe` uses the Windows GUI subsystem and starts without a command window.

### Engine thumbnail bake

Engine-content thumbnails are baked offline; the editor never renders a 3D scene just to draw a thumbnail. The bake command renders each primitive at 1024x1024 into a depth-buffered offscreen target, smooths it with a `ScreenFx` tent filter plus FXAA (no MSAA — the DX12 backend does not support MSAA offscreen targets), builds a premultiplied-linear mip pyramid and writes `res\thumbnails\bundles\*.bundle` (including a transparent-background `material.bundle`). `ThumbnailLoader` then uploads those mips into one trilinearly filtered texture so the Asset Browser size slider scales smoothly. The thumbnail `h2d.Graphics` opts into `smooth = true` so Heaps selects `MIN_MAG_MIP_LINEAR` instead of point sampling inside a mip level. Baked geometry uses a denser mesh than the editor default (64 segments / 48 rings), the key light comes from the upper right, and the camera is framed tightly inside the card without clipping.

```powershell
.\tools\bake-thumbnails.ps1                  # re-bake all built-in primitives
.\tools\bake-thumbnails.ps1 -OutputDirectory D:\tmp\thumbs
.\tools\build.ps1                            # rebuild to embed the new bundles
```

The baked bundles in `res\thumbnails\bundles` are the only thumbnail source; there is no runtime PNG fallback. The CPU half of the pipeline (halo-free mips + bundle round-trip) is covered by `ThumbnailPipelineRepro`.

To open a project from the command line or a file association, pass the manifest path:

```powershell
.\release\Boltspark.exe "D:\Projects\Demo.boltproject"
```

Double-clicking `*.boltproject` requires an explicit, user-level association (no admin, no system-wide install):

```powershell
.\tools\register-project-association.ps1          # register (opt-in)
.\tools\register-project-association.ps1 -Check   # inspect current state
.\tools\register-project-association.ps1 -Unregister
```

## Documentation

- [`docs/README.md`](docs/README.md) — starter/foundation slice overview and platform rules
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — M0 architecture: modules, layers, data flow
- [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md) — the pinned, hash-verified toolchain set
- [`docs/M0_IMPLEMENTATION_REPORT.md`](docs/M0_IMPLEMENTATION_REPORT.md) — what was done, evidence, deviations, known issues
- [`docs/AI_AGENT_GUIDELINES.md`](docs/AI_AGENT_GUIDELINES.md) — rules for AI agents working on this repo
- [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) — third-party provenance, licenses, and release bundling policy
- [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) — master development plan (do not modify)
- [`docs/TESTING.md`](docs/TESTING.md) — tracked portable/native test matrix and commands
- [`docs/ASSET_BROWSER.md`](docs/ASSET_BROWSER.md) — three-pane Asset Browser design, scope decision, and verification
- [`docs/UI_CONVENTIONS.md`](docs/UI_CONVENTIONS.md) — stable BoltUI cursor, menu, popover, alignment, and icon rules
- [`docs/PROJECT_FORMAT.md`](docs/PROJECT_FORMAT.md) — initial versioned project/scene contracts
- [`docs/COMPONENT_SYSTEM.md`](docs/COMPONENT_SYSTEM.md) — GameObject/component APIs, lifecycle, rendering, and extension
- [`docs/PERFORMANCE_BASELINE.md`](docs/PERFORMANCE_BASELINE.md) — measured 15-minute idle/resize baseline
- [`tests/native-foundation-acceptance.md`](tests/native-foundation-acceptance.md) — acceptance checklist with executed results

## Source layout

```
src/
  Main.hx                     — entry point (hxd.App), wires editor commands to engine objects
  boltspark/ui/
    BoltUI.hx                 — facade: theme + input adapter + editor shell
    core/                     — frame lifecycle, stable IDs, input state, diagnostics
    layout/                   — reusable dock geometry and local layout persistence
    render/                   — pooled draw commands + retained H2D executor
    Theme.hx                  — modern dark-editor color/size tokens
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
  boltspark/editor/           — pure editor session/model plus viewport and gizmos
    commands/                 — object, transform, duplicate, and hierarchy history
  res/fonts/                  — embedded Inter and JetBrains Mono TTF faces
  res/icons/                  — embedded exact-size Tabler icon atlas
tests/
  native-foundation-acceptance.md
  repro/                      — headless math, UI-core, command, serialization, and native repros
  native/                     — tracked HWND, layout, DPI, reset, and performance probes
tools/
  build.ps1                   — install dependencies, check, build, and run
  bake-thumbnails.ps1         — offline DX12 thumbnail bake command
  bake/                       — bake command host and its hxml
  test.ps1                    — portable CI and full native regression entry point
  check-policy.ps1            — native-only backend/dependency policy guard
  register-project-association.ps1 — opt-in user-level .boltproject association
  generate-fonts.ps1          — sync the pinned JetBrains Mono runtime TTF resource
  font-source/                — JetBrains Mono source + OFL font license texts
third_party/hlfreetype/       — pinned runtime TTF/OTF rasterizer and Heaps glyph cache
third_party/tabler-icons/     — pinned icon mapping and MIT license
```
