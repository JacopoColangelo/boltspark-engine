# Boltspark Engine — Windows 11 / DirectX 12 native foundation

Boltspark is a native Windows game engine and editor built on **HashLink + Heaps + DirectX 12**. The application UI (BoltUI) is rendered by Heaps through `h2d` over the 3D scene — it is **not** HTML, DOM, CSS, Electron, NW.js, CEF, WebView, SDL, or OpenGL, and none of those technologies may ever enter this codebase (see "Hard platform policy" below).

## What is working (M0)

- A native Windows 11 x64 desktop window ("Boltspark Engine") booted by the HashLink VM, rendering through the **DirectX 12** Heaps driver (positively identified at runtime as `h3d.impl.DX12Driver`).
- A static orange editor cube in `s3d` behind a native `h2d` editor chrome overlay.
- A bounded 3D viewport clipped with Heaps' render-zone scissor; viewport clicks are converted into camera rays and synchronize cube selection with the hierarchy.
- A compact native BoltUI editor shell with exact-size runtime FreeType glyph caching for Inter and JetBrains Mono, exact-size pixel-grid-fitted analytic icons, crisp vector surfaces, menu/transform/transport toolbars, searchable hierarchy, structured Inspector sections, viewport HUD, output log, and status diagnostics. The Output Log stays focused on actionable warnings and errors instead of echoing routine selections, tool switches, and transform edits; launch with `BOLTSPARK_VERBOSE_LOGS` set to restore detailed interaction telemetry for diagnosis.
- The bounded 3D viewport has a Y-up editor grid, colored axes, studio lighting, and scale-invariant two-pixel selected-object wireframe feedback while retaining viewport ray picking and drag/drop placement.
- All three transform tools drive viewport gizmos: Move offers axis, two-axis plane, and center free-view-plane drags; Rotate offers axis rings plus a true virtual-sphere omni arc-ball; Scale offers axis/plane/uniform scaling. Arc-ball motion keeps the same response and rotation axis when the pointer enters or exits its virtual sphere, while large coalesced pointer deltas are subdivided so fast rim crossings cannot collapse. Successive Bell-surface points preserve off-center view-axis roll, while a linear pointer-travel angle keeps long relative-mode drags unbounded. Its accumulated quaternion remains untouched and normalized during long drags; an internal per-object Euler hint selects a stable equivalent branch, while the Inspector presents Unreal-style Rotator values in `(-180°, 180°]`. A clickable WORLD/LOCAL viewport control changes the shared axis frame (WORLD is the default), all changes flow through the editor command path with live inspector updates, and the default shortcuts are **1** (Move), **E** (Rotate), and **R** (Scale).
- Viewport translation, rotation, and scale snapping have independent toolbar toggles and step presets. Rotation snapping applies to the axis rings while the omni arc-ball always remains freeform. Holding **V** temporarily suspends translation snapping, while **Ctrl+End** snaps the selection to the translation grid. Keyboard actions can be rebound from **File → Editor Settings → Editor Keybindings**, which opens as a separate native application window; bindings persist in `%LOCALAPPDATA%\Boltspark Engine\keybindings.json` and synchronize back to the live editor.
- The release executable, taskbar, native windows, and main editor title strip share the embedded multi-resolution Boltspark icon. The main editor and auxiliary application windows use native Windows dark title bars. Opening the File menu prepares the small keybindings host in the background; closing its window hides it while retaining the HWND, DX12 device, and font cache, so subsequent opens do not launch or initialize another process.
- The hierarchy, inspector, and console regions can be resized with draggable splitters; panel sizes stay within usable bounds, adapt to window resizing, and persist in `%LOCALAPPDATA%\Boltspark Engine\layout.json`.
- Inspector numeric fields support compact up/down stepping, horizontal drag scrubbing, and keyboard editing with focus, validation, Enter-to-apply, and Escape-to-cancel.
- Position, Rotation, and Scale rows have one-click canonical resets; Scale can link its axes to preserve the current X/Y/Z proportions across field edits and gizmo drags, while signed values and pivot-crossing gizmo drags support mirrored transforms without singular zero scale.
- The editor world is bounded to ±8 km from the origin on every axis. Every transform path constrains complete transformed geometry instead of deleting objects or imposing an arbitrary scale-factor cap; the viewport far plane covers the bounded world, and camera-enclosing meshes remain visible from inside while editing.
- Editor commands flow UI → command → engine object (widgets never mutate engine state directly).

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
```

The single script sets the Haxe/HashLink environment per-session and uses project-local dependencies. Dependency installation is explicit; it downloads the pinned HashLink/C library, PIX runtime, and verified FreeType source only when requested. `-Check` reports the detected Visual Studio/MSBuild installation and verifies it is usable. Native builds select the matching toolset (VS2026 `v145`, VS2022 `v143`). The generated `release\` folder contains the executable, `freetype.hdll`, licenses, and its other required runtime files.

The development build runs through `hl.exe` and retains its command window for logs and crash diagnostics. The packaged `release\Boltspark.exe` uses the Windows GUI subsystem and starts without a command window.

## Documentation

- [`docs/README.md`](docs/README.md) — starter/foundation slice overview and platform rules
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — M0 architecture: modules, layers, data flow
- [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md) — the pinned, hash-verified toolchain set
- [`docs/M0_IMPLEMENTATION_REPORT.md`](docs/M0_IMPLEMENTATION_REPORT.md) — what was done, evidence, deviations, known issues
- [`docs/AI_AGENT_GUIDELINES.md`](docs/AI_AGENT_GUIDELINES.md) — rules for AI agents working on this repo
- [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) — licenses for fonts, hlfreetype, and FreeType
- [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) — master development plan (do not modify)
- [`tests/native-foundation-acceptance.md`](tests/native-foundation-acceptance.md) — acceptance checklist with executed results

## Source layout

```
src/
  Main.hx                     — entry point (hxd.App), wires editor commands to engine objects
  boltspark/ui/
    BoltUI.hx                 — facade: theme + input adapter + editor shell
    layout/                   — reusable dock geometry and local layout persistence
    Theme.hx                  — modern dark-editor color/size tokens
    UiContext.hx              — embedded fonts, native cursors, window state
    AppIcon.hx                — shared ICO decoding for HWND and title-strip branding
    UiSurface.hx / UiIcons.hx — square-edged surfaces and exact-size icon primitives
    UiText*.hx / shaders/     — runtime FreeType text wrappers and pixel-fitted icon coverage
    InputAdapter.hx           — central keyboard/focus/pointer reporting
    EditorShell.hx            — editor chrome layout and command callbacks
    widgets/                  — buttons, inputs, search, hierarchy, inspector, console, scrollbars
    windows/                  — native top-level editor-window routing and H2D content
  res/fonts/                  — embedded Inter and JetBrains Mono TTF faces
tests/
  native-foundation-acceptance.md
  repro/DxCArrayRepro.hx      — isolation repro for the DX12/CArray root cause
tools/
  build.ps1                   — install dependencies, check, build, and run
  generate-fonts.ps1          — sync the pinned JetBrains Mono runtime TTF resource
  font-source/                — JetBrains Mono source + OFL font license texts
third_party/hlfreetype/       — pinned runtime TTF/OTF rasterizer and Heaps glyph cache
```
