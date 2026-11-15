# AI agent guidelines — Boltspark Engine

Rules for AI agents (and humans) working in this repository. Read this before making changes.

## Non-negotiable platform rules

1. **Native only.** The Windows target is HashLink + `hldx` + `-D dx12`. Never introduce or suggest Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML, CSS, Node, SDL (`hlsdl`), or OpenGL as UI or rendering technology. There is no fallback to DX11: `-D dx12` must stay in `compile.hxml`.
2. **Never touch the locked toolchain set.** Do not update Haxe, HashLink, Heaps, `format`, `hldx`, hlfreetype, FreeType, or any file in `toolchain/` without an explicit user decision. Any upgrade requires a clean compile and the full acceptance suite. The current lock is documented in `docs/TOOLCHAIN_VERSIONS.md` (compiler: `5.0.0-preview.1+dcda605` at `toolchain/haxe-dev`; HashLink 1.16.0 at `toolchain/hashlink`; hlfreetype 1.0.0 at pinned commit `56c8aac`; FreeType 2.14.3; the compiler pin is the newest one that works with Heaps 2.1.0 — newer dev builds break Heaps, older/stable compilers cannot run DX12 with Heaps 2.1.0).
3. **Do not modify `docs/DEVELOPMENT_PLAN.md`.** It is the master plan. Propose changes to the user instead.

## Environment rules

4. The toolchain is **project-local** (`toolchain/`). Never install anything system-wide or on `C:`. The user explicitly does not want anything on C:.
5. Harness processes do not inherit updated registry env; set per-session env before invoking tools:
   ```powershell
   $tc = 'D:\Giochi\BoltSpark Engine\toolchain'
   $env:Path = "$tc\haxe-dev;$tc\neko;$tc\hashlink;$env:Path"
   $env:HAXE_STD_PATH = "$tc\haxe-dev\std"
   $env:HAXELIB_PATH  = "$tc\haxelib"
   $env:NEKOPATH      = "$tc\neko"
   ```
6. `haxelib.exe` needs Neko on PATH or it dies with `STATUS_DLL_NOT_FOUND`.

## Code rules

7. Follow Heaps 2.x APIs — do not assume Heaps 1.x (e.g. `h3d.scene.DirLight` no longer exists). When unsure, read the actual library source in `toolchain/haxelib/heaps/2,1,0/` before writing code.
8. Widgets issue **commands** via callbacks; they never mutate engine state directly (see `docs/ARCHITECTURE.md`).
9. The 3D viewport area must stay transparent in the `h2d` chrome — never fill the full window with an opaque background.
10. New Haxe files must have names matching their class/module (Haxe resolves modules by exact case), and PowerShell `Set-Content` writes UTF-16 by default — always pass `-Encoding ascii` (or UTF-8) for source files.

## Honesty rules

11. **Never claim unverified success.** Every "working" claim needs evidence: exit codes, log lines (e.g. the `[M0] renderer driver = ...` line), screenshots, or checklist entries in `tests/native-foundation-acceptance.md`.
12. When something fails, report the failure and the exact error; do not silently substitute a different technology to make the symptom disappear.
13. Update the acceptance checklist and the milestone report as work progresses; link evidence files.

## Verification workflow

14. Before each runtime test, kill lingering `hl.exe` processes (an exception dialog from a previous run can block the test).
15. Build with `tools/build.ps1`, run with `tools/build.ps1 -Run`. For screenshots of the native window use `PrintWindow` (screen-copy grabs the wrong monitor on multi-monitor setups).
16. Run `tools/build.ps1 -Check` before diagnosing "environment" issues — it validates OS, pins, native modules, and build config in one pass. Install third-party build dependencies only when required with `tools/build.ps1 -InstallDependencies`.
17. Keep the DX12/CArray regression repro (`tests/repro/DxCArrayRepro.hx`) compiling and passing whenever toolchain changes are ever approved.
18. Keep `tests/repro/FreeTypeRuntimeRepro.hx` passing when changing fonts, hlfreetype, FreeType, glyph metrics, or atlas behavior.
19. Run `tools/test.ps1 -Portable` for every source change. Before claiming a
    native integration complete, run `tools/test.ps1 -Build -NativeSmoke` plus
    the relevant `-WindowLifecycle`, `-DpiProbe`, or `-DeviceReset` switch.
20. Keep reusable probes under `tests/native/`, never only under ignored `bin/`.
    Generated evidence belongs in `bin/test-results/`; document the exact probe
    and machine instead of committing transient bytecode or screenshots.
