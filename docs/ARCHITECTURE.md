# Boltspark M0 architecture — native foundation slice

This document describes the architecture as implemented at M0, on Windows 11 x64 with HashLink + Heaps + DirectX 12.

## Layer diagram

```
+---------------------------------------------------------------+
| Windows 11 x64 (D3D12 device, Win32 window/input via hldx)     |
+---------------------------------------------------------------+
| HashLink VM 1.16.0  (hl.exe + libhl.dll, toolchain/hashlink)   |
|   directx.hdll  — native window/input/event services           |
|   dx12.hdll     — Direct3D 12 rendering driver                 |
|   heaps.hdll    — Heaps native helpers                         |
+---------------------------------------------------------------+
| Heaps 2.1.0 (hxd.App lifecycle; h3d 3D scene; h2d 2D scene)    |
|   driver: h3d.impl.DX12Driver   (selected by -D dx12)          |
+---------------------------------------------------------------+
| BoltUI (src/boltspark/ui) — native H2D editor chrome           |
|   BoltUI facade -> EditorShell -> widgets (button/stepper/...) |
|   InputAdapter (scene-level keyboard/focus/pointer reporting)  |
+---------------------------------------------------------------+
| Main.hx — boot + command wiring (UI commands -> engine objects)|
+---------------------------------------------------------------+
```

No browser technology exists anywhere in this stack. There is no Electron/CEF/WebView, no DOM/CSS, no SDL, no OpenGL.

## Startup flow

1. `hl bin/boltspark.hl` — HashLink VM loads the bytecode and resolves native modules beside `hl.exe` (`directx.hdll`, `dx12.hdll`, `heaps.hdll`).
2. `Main.main()` constructs `Main extends hxd.App`; Heaps creates the native window, 3D scene (`s3d`), 2D scene (`s2d`), and the render engine.
3. `h3d.Engine` selects `h3d.impl.DX12Driver` because `compile.hxml` defines `-D dx12` (with `-D hl_ver=1.16.0` required by the driver's `hl.CArray` usage).
4. `Main.init()`:
   - logs the actual driver class name (`Type.getClassName(Type.getClass(engine.driver))`) — M0's positive driver evidence;
   - builds the sample cube primitive in `s3d`;
   - constructs `BoltUI` in `s2d` (the overlay).
5. `Main.update(dt)` runs per frame: `boltUI.update(dt)` (re-layout on native resize only), camera aspect maintenance, and cube rotation at the editor-controlled spin speed.

## Module responsibilities (src/boltspark/ui)

| Module | Responsibility |
|---|---|
| `BoltUI.hx` | Facade. Owns context/input/shell; forwards `update`/`resize`; exposes editor command callbacks (`onTestAction`, `onSpinSpeedChanged`, `onColorChanged`) and `log()`. |
| `Theme.hx` | Design tokens: colors and layout metrics. Single source of truth for chrome appearance. |
| `UiContext.hx` | Shared widget state: native window ref, default font, current client size, small text-centering helpers. Widgets never read globals. |
| `InputAdapter.hx` | One scene-level `addEventListener` hook recording keyboard (name + counts), focus transitions, and pointer movement. Purely observational — reports to the status bar; no behavior. |
| `EditorShell.hx` | Owns chrome geometry: draws top bar, side panels, console area, status bar into one `h2d.Graphics`; positions widgets; exposes editor command callbacks upward. Rebuilds static geometry only on resize. |
| `widgets/UiButton.hx` | `h2d.Interactive` hit region + centered label; hover/push/release-outside color states; click callback. |
| `widgets/Stepper.hx` | Bounded numeric editing in fixed steps (`[-] value [+]`); reports changes via `onValueChanged`. |
| `widgets/SwatchPicker.hx` | Color swatch row with selected-outline highlight; reports via `onColorChanged`. |
| `widgets/ConsolePanel.hx` | Bounded append-only log (timestamped, last N lines) rendered as one multiline `h2d.Text`. |

## Key design rules established at M0

1. **Transparent viewport.** The chrome never fills the center column; `s3d` shows through `s2d`. (The starter filled the whole window with an opaque background and hid the 3D scene — fixed in M0.)
2. **Command flow, not direct mutation.** Widgets call shell callbacks; `Main` maps commands to engine objects (`sampleCube.material.color`, spin speed). Gate 4 will formalize this into an editor command queue.
3. **Resize-aware, allocation-conscious.** Static chrome geometry is rebuilt only when the OS window size changes; per-frame work is limited to state updates and tiny rotations.
4. **Positive driver identification.** The app logs the driver class at startup; acceptance requires this line rather than inferring DX12 from the compile flag.
5. **Toolchain as a locked set.** Compiler/runtime/bindings are pinned together (see `docs/TOOLCHAIN_VERSIONS.md`); `tools/check-windows.ps1` enforces the pins.

## Deliberately out of scope at M0

Immediate-mode BoltUI API, splitters/docking, text input, menus, picking, asset pipeline, PBR, packaging to a standalone executable, and multi-monitor/DPI validation beyond basics. These follow in Gates 4–5 per `docs/IMPLEMENTATION_SEQUENCE.md`.
