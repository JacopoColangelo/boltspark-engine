# Boltspark Engine — Windows 11 / DirectX 12 native foundation

Boltspark is a native Windows game engine and editor built on **HashLink + Heaps + DirectX 12**. The application UI (BoltUI) is rendered by Heaps through `h2d` over the 3D scene — it is **not** HTML, DOM, CSS, Electron, NW.js, CEF, WebView, SDL, or OpenGL, and none of those technologies may ever enter this codebase (see "Hard platform policy" below).

## What is working (M0)

- A native Windows 11 x64 desktop window ("Boltspark Engine — Native Foundation") booted by the HashLink VM, rendering through the **DirectX 12** Heaps driver (positively identified at runtime as `h3d.impl.DX12Driver`).
- A rotating 3D mesh in `s3d` behind a native `h2d` editor chrome overlay.
- The first BoltUI framework slice: top bar, hierarchy, transparent 3D viewport, inspector with an editable spin-speed stepper and color swatches, an editor console, a status bar with a central input adapter (keyboard/focus/pointer diagnostics), and resize-aware layout.
- Editor commands flow UI → command → engine object (widgets never mutate engine state directly).

## Hard platform policy

The editor must not use Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, or CSS for its application UI. On Windows the graphics backend is exclusively `hldx` + `-D dx12`; `hlsdl`, SDL, and OpenGL are not dependencies and must not be added.

## Project-local toolchain

The full toolchain lives inside this repository — nothing needs to be installed system-wide:

| Path | Contents |
|---|---|
| `toolchain/haxe-dev` | **Pinned compiler: Haxe 5.0.0-preview.1+dcda605** (dev build dated 2025-10-23) — the only verified compiler that can build Heaps 2.1.0 + HashLink 1.16 + DX12. User-ratified 2026-11-11. |
| `toolchain/haxe` | Haxe 4.3.7 stable (reference only; **cannot** run the DX12 driver — do not build with it) |
| `toolchain/hashlink` | Official HashLink **1.16.0** win64 binary (with `directx.hdll`, `dx12.hdll`, `libhl.dll`, `dxcompiler.dll`, `dxil.dll`) |
| `toolchain/haxelib` | Project-local Haxelib repository (heaps 2.1.0, format 3.8.0, hldx 1.16.0) |
| `toolchain/neko` | Neko runtime (needed by `haxelib.exe`) |

Full version lock, hashes, and the reasoning behind the compiler pin: [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md).

### Why not Haxe 4.3.x stable?

Heaps 2.1.0's DX12 driver requires `hl.CArray`, whose correct codegen exists only in Haxe development builds with native `hl_carray` support. Haxe 4.3.7 has no such support and its stdlib references C primitives that no released HashLink exports. Dev builds newer than 2025-10-23 break Heaps 2.1.0 (`EventLoop` refactor). The pin is the exact newest-working point; upgrading requires re-verification of the whole set.

## Build and run (Windows PowerShell)

```powershell
.\tools\check-windows.ps1        # verify OS + project toolchain + build config
.\tools\build-windows.ps1        # haxe compile.hxml -> bin/boltspark.hl
.\tools\run-windows.ps1          # launch with the project-local HashLink runtime
```

The scripts set the toolchain environment per-session and prefer the project-local paths; they do not depend on system-wide installs.

## Documentation

- [`docs/README.md`](docs/README.md) — starter/foundation slice overview and platform rules
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — M0 architecture: modules, layers, data flow
- [`docs/TOOLCHAIN_VERSIONS.md`](docs/TOOLCHAIN_VERSIONS.md) — the pinned, hash-verified toolchain set
- [`docs/M0_IMPLEMENTATION_REPORT.md`](docs/M0_IMPLEMENTATION_REPORT.md) — what was done, evidence, deviations, known issues
- [`docs/AI_AGENT_GUIDELINES.md`](docs/AI_AGENT_GUIDELINES.md) — rules for AI agents working on this repo
- [`docs/DEVELOPMENT_PLAN.md`](docs/DEVELOPMENT_PLAN.md) — master development plan (do not modify)
- [`tests/native-foundation-acceptance.md`](tests/native-foundation-acceptance.md) — acceptance checklist with executed results

## Source layout

```
src/
  Main.hx                     — entry point (hxd.App), wires editor commands to engine objects
  boltspark/ui/
    BoltUI.hx                 — facade: theme + input adapter + editor shell
    Theme.hx                  — color/size tokens
    UiContext.hx              — shared window/font state handed to widgets
    InputAdapter.hx           — central keyboard/focus/pointer reporting
    EditorShell.hx            — editor chrome layout and command callbacks
    widgets/                  — UiButton, Stepper, SwatchPicker, ConsolePanel
tests/
  native-foundation-acceptance.md
  repro/DxCArrayRepro.hx      — isolation repro for the DX12/CArray root cause
tools/
  check-windows.ps1           — environment check (no Agility SDK requirement)
  build-windows.ps1           — compile
  run-windows.ps1             — launch
  install-dependencies.ps1    — install pinned Haxelib packages into toolchain/haxelib
```
