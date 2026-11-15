# Boltspark Native Foundation — Windows 11 / DirectX 12 starter slice

This starter establishes the first executable architecture gate for Boltspark on **Windows 11 x64**, using **HashLink + Heaps + DirectX 12**. The Haxe build selects Heaps' `hldx` backend with `-D dx12`. DX12 is the primary target in this project; the default DirectX 11 mode is not selected and there is no automatic fallback.

The proof slice contains:

- one native Windows desktop window;
- Heaps `hxd.App` owns startup, frame lifecycle, input routing, and the standard 2D/3D scenes;
- `h3d` renders a static orange editor cube through the DX12 driver;
- `h2d` renders a native editor chrome overlay;
- a native Heaps interactive control verifies mouse input;
- the UI responds to native window resizing.

## Hard platform policy

The editor must not use Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, or CSS for its application UI. BoltUI is drawn by Heaps through `h2d` and receives input through Heaps' native event path.

**Windows target:** HashLink + `hldx` + `-D dx12`. This project does not depend on `hlsdl`, SDL, or an OpenGL fallback. DirectX 12 is the selected native graphics backend, not a browser shell.

## DX12 backend selection and native runtime modules

`compile.hxml` must contain both:

```hxml
-lib hldx
-D dx12
```

Heaps documents `-lib hldx -D dx12` as its Windows DirectX 12 configuration. Do not remove `-D dx12`: without it, Heaps selects the default DirectX path instead of the DX12 driver.

The HashLink native runtime uses two separate DirectX modules in this configuration:

- `directx.hdll` — native Windows window/input/event services used by Heaps' `hldx` platform layer;
- `dx12.hdll` — Direct3D 12 rendering driver.

Both modules must be built for x64 and be loadable by the same HashLink VM. The `hldx` Haxelib package supplies Haxe bindings; it is not a substitute for the native `.hdll` runtime modules. HashLink's DirectX CMake configuration defines `directx.hdll` and `dx12.hdll` as separate native targets.

## DirectX 12 Agility SDK runtime (not required)

**The official HashLink 1.16.0 win64 binary build does not require the D3D12 Agility SDK.** This was verified directly: the pinned runtime (in `toolchain/hashlink/`) has no `D3D12/` folder, defines no `HL_DX12_AGILITY_VERSION`, and the DX12 driver initializes and renders correctly (driver positively identified at runtime as `h3d.impl.DX12Driver`; see `docs/TOOLCHAIN_VERSIONS.md`).

The Agility SDK is only relevant if you build HashLink yourself with its `ReleaseDX12Agility`/`ReleaseAll` CMake configuration (which also pulls in Nsight Aftermath). This project uses the official binary and does not do that. If a future milestone switches to a self-built Agility-enabled HashLink, the `D3D12/` folder rules below would then apply:

```text
D3D12/
  D3D12Core.dll
  d3d12SDKLayers.dll
```

placed beside the application executable, with the SDK package version matching `HL_DX12_AGILITY_VERSION` of that build. **Never mix Agility DLLs from another HashLink build.**

## Prerequisites

The pinned Haxe/HashLink toolchain ships under `toolchain/`. Native release builds additionally require Visual Studio 2022 or newer with the Desktop C++ workload and Windows SDK. The build script discovers the installed instance with `vswhere`, without assuming a Visual Studio edition or install path.

1. Windows 11 x64.
2. **Pinned compiler** `toolchain/haxe-dev` — Haxe `5.0.0-preview.1+dcda605` (dev build dated 2025-10-23; see `docs/TOOLCHAIN_VERSIONS.md` for why Haxe 4.3.x stable cannot run Heaps 2.1.0's DX12 driver).
3. **HashLink runtime** `toolchain/hashlink` — official HashLink 1.16.0 win64 binary with both `directx.hdll` and `dx12.hdll`.
4. **Haxelib packages** in the project-local repository `toolchain/haxelib`: `heaps` **2.1.0**, `format` **3.8.0**, `hldx` **1.16.0**, and HashLink/C **1.16.0**.
5. Project-local hlfreetype **1.0.0** + FreeType **2.14.3** source, installed and built by the dependency/build scripts; nothing is installed system-wide.
6. A Windows 11 GPU and driver supporting Direct3D 12.
7. No Agility SDK required (see the section above).
8. Pinned Microsoft WinPixEventRuntime **1.0.240308001**, installed by the dependency script for native linking.

### Install dependencies (PowerShell)

Run from the project root to install the pinned Haxe/C library, PIX runtime,
and verified project-local FreeType source:

```powershell
.\tools\build.ps1 -InstallDependencies
```

Use `.\tools\build.ps1 -Check` to verify the whole set (OS, compiler pin, HashLink modules, build config, and detected Visual Studio/MSBuild) before building.

## Build and run (Windows PowerShell)

From the repository root:

```powershell
.\tools\build.ps1
.\tools\test.ps1 -Portable
.\tools\test.ps1 -Build -NativeSmoke -WindowLifecycle -DpiProbe -DeviceReset
```

The default action builds both the development bytecode (`bin\boltspark.hl`) and native release (`release\Boltspark.exe` plus its runtime files). Use `.\tools\build.ps1 -Run` to launch the bytecode build; launch the native release directly from `release\Boltspark.exe`.

The scripts prefer the project-local toolchain (`toolchain/haxe-dev`, `toolchain/hashlink`, `toolchain/haxelib`) and set the required environment (`HAXE_STD_PATH`, `HAXELIB_PATH`, `NEKOPATH`) per session. Native projects use the matching Visual Studio toolset (VS2026 `v145`, VS2022 `v143`).

Equivalent manual commands (PowerShell, from the repo root):

```powershell
$tc = "$PWD\toolchain"
$env:Path        = "$tc\haxe-dev;$tc\neko;$tc\hashlink;$env:Path"
$env:HAXE_STD_PATH = "$tc\haxe-dev\std"
$env:HAXELIB_PATH  = "$tc\haxelib"
$env:NEKOPATH      = "$tc\neko"
New-Item -ItemType Directory -Force bin | Out-Null
haxe compile.hxml
if ($LASTEXITCODE -ne 0) { throw 'Haxe compilation failed.' }
Push-Location bin
hl boltspark.hl
Pop-Location
```

The development output is HashLink bytecode (`bin/boltspark.hl`); the native Windows release is packaged separately in `release\Boltspark.exe`.
See [`TESTING.md`](TESTING.md) for the portable/native test split and the
remaining physical hardware gates.

## What you should see

- A native Windows window titled `Boltspark Engine`.
- A static orange 3D cube in the transparent center viewport using the DX12 driver (runtime log prints `[M0] renderer driver = h3d.impl.DX12Driver`).
- Editor chrome drawn with H2D: top bar (`BOLTSPARK`), left hierarchy, Transform inspector with Position/Rotation/Scale fields, an editor console below the viewport, and a bottom status bar.
- Transform fields support arrow stepping, horizontal scrubbing, and keyboard entry. Each row has a reset action; Scale also has a chain toggle that preserves existing axis proportions for field and gizmo scaling.
- Resizing the OS window redraws the editor chrome to the new dimensions.

## Windows native release

Run `.\tools\build.ps1 -InstallDependencies` once to install the HashLink/C support library, pinned PIX runtime, and pinned FreeType source. Then `.\tools\build.ps1` builds the project-local `freetype.hdll`, development bytecode, and native Windows executable into `release\Boltspark.exe`. The `release\` folder includes the HashLink modules, `freetype.hdll`, licenses, and required DLLs alongside the executable. Native builds require Visual Studio 2022 or newer with the Desktop C++ workload and Windows SDK.

## Important scope boundary

The repository has advanced beyond the original one-window proof: it now has
resizable persisted panel regions, bounded picking, hierarchy/Inspector editing,
three transform gizmos, native application windows, and reusable BoltUI/data
foundations. It is still not a complete editor or the final immediate-mode API.
Integrated project open/save, asset import, plugins, custom render passes, PBR,
and HIDE migration remain outside the current implementation boundary.

The current BoltUI hybrid keeps retained H2D controls while using explicit frame
boundaries, scoped stable IDs, persistent state, deterministic layout, and a
pooled draw-command path for static chrome. Future public immediate-mode APIs can
build on those contracts without allocating a new scene tree every frame.

## Acceptance checks

See [`tests/native-foundation-acceptance.md`](tests/native-foundation-acceptance.md). Do not mark the Windows DX12 gate complete until it has been run on a real Windows 11 machine with the intended GPU, driver, and HashLink modules.

## Windows / DirectX 12 references

- [Heaps: Hello HashLink](https://heaps.io/documentation/hashlink.html) — documents `-lib hldx` and the optional `-D dx12` define for DirectX 12.
- [Heaps: Installation](https://heaps.io/documentation/installation.html) — lists `hldx` as the DirectX support package.
- [HashLink DirectX CMake configuration](https://github.com/HaxeFoundation/hashlink/blob/master/libs/directx/CMakeLists.txt) — shows separate `directx.hdll` and `dx12.hdll` native targets.
- [HashLink DirectX 12 Agility SDK notes](https://github.com/HaxeFoundation/hashlink/blob/master/libs/directx/README.md) — documents the `D3D12` runtime folder and matching `HL_DX12_AGILITY_VERSION` requirement.
- [HashLink releases](https://github.com/HaxeFoundation/hashlink/releases) — source of the VM/native runtime; use and record a compatible x64 build.
- [hldx package](https://lib.haxe.org/p/hldx) — Haxe/HashLink DirectX bindings.
- [Microsoft DirectX 12 Agility SDK](https://devblogs.microsoft.com/directx/directx12agility/) — SDK downloads and documentation.
