# Boltspark Engine — Windows 11 / DirectX 12 native foundation

Boltspark is a native Windows game engine and editor built on **HashLink + Heaps + DirectX 12**. The application UI (BoltUI) is rendered by Heaps through `h2d` over the 3D scene — it is **not** HTML, DOM, CSS, Electron, NW.js, CEF, WebView, SDL, or OpenGL, and none of those technologies may ever enter this codebase (see "Hard platform policy" below).

## What is working (M0)

- A native Windows 11 x64 desktop window ("Boltspark Engine") booted by the HashLink VM, rendering through the **DirectX 12** Heaps driver (positively identified at runtime as `h3d.impl.DX12Driver`).
- A rotating 3D mesh in `s3d` behind a native `h2d` editor chrome overlay.
- A bounded 3D viewport clipped with Heaps' render-zone scissor; viewport clicks are converted into camera rays and synchronize cube selection with the hierarchy.
- A compact native BoltUI editor shell with embedded anti-aliased Inter/JetBrains Mono atlases, crisp vector surfaces, procedural icons, menu/transform/transport toolbars, searchable hierarchy, structured Inspector sections, viewport HUD, output log, and status diagnostics.
- The bounded 3D viewport has a Y-up editor grid, colored axes, studio lighting, and selected-object wireframe feedback while retaining viewport ray picking and drag/drop placement.
- The hierarchy, inspector, and console regions can be resized with draggable splitters; panel sizes stay within usable bounds, adapt to window resizing, and persist in `%LOCALAPPDATA%\Boltspark Engine\layout.json`.
- Inspector numeric fields support compact up/down stepping, horizontal drag scrubbing, and keyboard editing with focus, validation, Enter-to-apply, and Escape-to-cancel.
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

The single script sets the Haxe/HashLink environment per-session and uses project-local dependencies. Dependency installation is explicit; it downloads the pinned HashLink/C library and PIX runtime only when requested. `-Check` reports the detected Visual Studio/MSBuild installation and verifies it is usable. Native builds select the matching toolset (VS2026 `v145`, VS2022 `v143`). The generated `release\` folder contains the executable and its required runtime files.

## Documentation

- [`docs/README.md`](docs/README.md) — starter/foundation slice overview and platform rules
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — M0 architecture: modules, layers, data flow
- [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md) — the pinned, hash-verified toolchain set
- [`docs/M0_IMPLEMENTATION_REPORT.md`](docs/M0_IMPLEMENTATION_REPORT.md) — what was done, evidence, deviations, known issues
- [`docs/AI_AGENT_GUIDELINES.md`](docs/AI_AGENT_GUIDELINES.md) — rules for AI agents working on this repo
- [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) — licenses for embedded UI font atlases
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
    UiContext.hx              — embedded fonts, 9-slice tile, native cursors, window state
    UiSurface.hx / UiIcons.hx — square-edged surface and procedural icon primitives
    InputAdapter.hx           — central keyboard/focus/pointer reporting
    EditorShell.hx            — editor chrome layout and command callbacks
    widgets/                  — buttons, inputs, search, hierarchy, inspector, console, scrollbars
  res/                        — embedded bitmap-font atlases
tests/
  native-foundation-acceptance.md
  repro/DxCArrayRepro.hx      — isolation repro for the DX12/CArray root cause
tools/
  build.ps1                   — install dependencies, check, build, and run
  generate-fonts.ps1          — deterministically regenerate embedded UI font atlases
  font-source/                — OFL-licensed Inter and JetBrains Mono source fonts
```
