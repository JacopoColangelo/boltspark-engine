# Native foundation acceptance checklist — Windows 11 / DirectX 12

Executed on 2026-11-11 on the dev machine (Windows 11 Pro build 26300 x64, RTX 3080, i7-12700K).
Evidence files are under `bin/` unless noted otherwise.

## Build/runtime

- [x] Windows 11 x64 machine and GPU/driver recorded (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Haxe compilation succeeds with the pinned toolchain using `compile.hxml` (`tools\build.ps1`).
- [x] Native release build links HashLink/C into `release\Boltspark.exe` and stages the required runtime modules beside it.
- [x] `compile.hxml` selects `-lib hldx`, explicitly defines `-D dx12`, and pins `-D hl_ver=1.16.0`.
- [x] HashLink VM starts the compiled `.hl` file (`toolchain/hashlink/hl.exe bin/boltspark.hl`).
- [x] HashLink native module `directx.hdll` (window/input/event services) is present and loads at runtime (window opens, input works).
- [x] HashLink native module `dx12.hdll` (Direct3D 12 rendering driver) is present and loads at runtime (rendering succeeds; driver positively identified as `h3d.impl.DX12Driver`).
- [x] **Agility SDK: not required.** The official HashLink 1.16.0 binary is a standard DX12 build; no `D3D12/` folder or Agility DLLs are needed.
- [x] Process opens a normal native Windows desktop window (`bin/m0_window.png` — title "Boltspark Engine").
- [x] No Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, browser, Node, SDL, or OpenGL fallback is launched/used: the only modules loaded are HashLink runtime + `dx12.hdll`/`directx.hdll`/`heaps.hdll`; `hlsdl`/`sdl.hdll` is never referenced by the build (`compile.hxml` checked by `tools/build.ps1 -Check`).
- [x] Window closes cleanly (run exits with code 0 on close).

## Rendering

- [x] DX12 driver is positively identified in runtime diagnostics, not only inferred from the compile flag: `[M0] renderer driver = h3d.impl.DX12Driver` (`bin/runlog.txt`).
- [x] 3D cube appears in the 3D scene using the Heaps DX12 driver (`bin/m0_window.png`, `bin/m0_input_test.png`).
- [x] Cube visibly rotates without application logic errors (rotation rate editable live from the inspector stepper).
- [x] H2D editor chrome appears over the 3D scene (top bar, hierarchy, inspector, console, status bar; viewport area left transparent for the 3D scene).
- [x] Text is legible at baseline window size (1440x900 default; verified at 1296x900 after resize).
- [x] Resize behavior: chrome redraws to the new client size (`bin/m0_input_test.png` was captured at a resized 1296x900 window with correct layout). Maximize/restore re-uses the same `resize()` path.
- [x] No Direct3D 12 device/runtime errors during the test (no exception dialogs, clean run log).

## Input

- [x] Clicking `Test native input` registers once per click (automated Win32 clicks: one `command: test native input (click registered)` line per click, `bin/m0_input_test.png`).
- [x] Clicking outside the control does not activate it (h2d.Interactive bounds; release-outside is handled by the widget's `onReleaseOutside` state restore).
- [x] Repeated clicks remain responsive (multiple stepper clicks in a row registered in exact 0.25 increments).
- [x] Focus loss/regain does not leave stuck visual/input state (input adapter reports focus 4/4 transitions with no stuck hover/pressed state; button color restored on release-outside).
- [x] Keyboard event reporting flows through the central input adapter (status bar shows `key ... | dN uN mvN focus G/L` live; `boltspark/ui/InputAdapter.hx`).

## Platform and toolchain

- [x] Record Haxe, HashLink, Heaps, `format`, and `hldx` versions (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Record HashLink distribution source and hashes of native modules (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Agility SDK: n/a — not required by the official HashLink 1.16.0 binary (documented, with rationale).
- [x] Record GPU model, driver version (`docs/TOOLCHAIN_VERSIONS.md`). D3D12 feature level recorded from hardware class (12_1); Heaps DX12Driver does not expose a device feature-level query at M0 — direct runtime feature-level read is deferred to a later milestone if needed.
- [x] Confirm `compile.hxml` selects `hldx` + `-D dx12` and does not reference `hlsdl` (enforced by `tools/build.ps1 -Check`).
- [x] Root-cause diagnosis for the initial DX12 startup failure documented with an isolated repro (`tests/repro/DxCArrayRepro.hx` + analysis in `docs/M0_IMPLEMENTATION_REPORT.md`).

## Performance baseline

- [ ] Record idle frame time and CPU/GPU usage at 1440x900.
- [ ] Record memory after 1 minute and 15 minutes.
- [ ] No unbounded memory growth while idle or resizing.

(Performance capture is pending a dedicated measurement pass; all functional gates above are verified.)

**Do not mark this gate complete until the checklist is executed on a real Windows 11 target machine.** — Executed on the primary dev machine on 2026-11-11; a second-machine confirmation remains open for later milestones.
