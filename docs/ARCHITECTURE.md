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
|   freetype.hdll — exact-size runtime TTF/OTF glyph rasterizer  |
+---------------------------------------------------------------+
| Heaps 2.1.0 (hxd.App lifecycle; h3d 3D scene; h2d 2D scene)    |
|   driver: h3d.impl.DX12Driver   (selected by -D dx12)          |
+---------------------------------------------------------------+
| BoltUI (src/boltspark/ui) — native H2D editor chrome           |
|   BoltUI facade -> EditorShell -> widgets (button/number/...)  |
|   InputAdapter (scene-level keyboard/focus/pointer reporting)  |
|   windows/ (separate top-level HWND process per editor dialog) |
+---------------------------------------------------------------+
| Main.hx — boot + command wiring (UI commands -> engine objects)|
+---------------------------------------------------------------+
```

No browser technology exists anywhere in this stack. There is no Electron/CEF/WebView, no DOM/CSS, no SDL, no OpenGL.

## Startup flow

1. `tools/build.ps1 -Run` starts `hl` with `bin/` as the working directory. HashLink loads `boltspark.hl`, resolves the project-local `freetype.hdll` from `bin/`, and resolves the locked DirectX/Heaps modules from the HashLink runtime path.
2. `Main.main()` normally constructs `Main extends hxd.App`; Heaps creates the native window, 3D scene (`s3d`), 2D scene (`s2d`), and the render engine. A `--boltspark-window=...` route instead starts the requested application-level editor window with its own native HWND and DX12 swap chain.
3. `h3d.Engine` selects `h3d.impl.DX12Driver` because `compile.hxml` defines `-D dx12` (with `-D hl_ver=1.16.0` required by the driver's `hl.CArray` usage).
4. `Main.init()`:
   - logs the actual driver class name (`Type.getClassName(Type.getClass(engine.driver))`) — M0's positive driver evidence;
   - builds the sample cube primitive in `s3d`;
   - constructs `BoltUI` in `s2d` (the overlay); `UiContext` creates exact-size
     Inter and JetBrains Mono faces through FreeType and preloads the common
     editor characters.
5. `Main.update(dt)` runs per frame: `boltUI.update(dt)`, gizmo follow, and selection-outline synchronization. The editor cube has no passive animation.

## Module responsibilities (src/boltspark/ui)

| Module | Responsibility |
|---|---|
| `BoltUI.hx` | Facade. Owns context/input/shell; forwards `update`/`resize`; exposes transform, reset, scale-link, object, and viewport command callbacks plus `log()`. |
| `Theme.hx` | Design tokens: colors and layout metrics. Single source of truth for chrome appearance. |
| `UiContext.hx` | Shared widget state: native window ref, default font, current client size, small text-centering helpers. Widgets never read globals. |
| `UiText.hx` / `UiTextInput.hx` | Editor text rasterized from embedded Inter or JetBrains Mono TTF faces at its exact requested size; missing glyphs are inserted into a shared per-face atlas on demand. Console and numeric values retain JetBrains Mono Regular at 12px. |
| `UiIcons.hx` / `shaders/UiIconShader.hx` | Exact-size analytic icon shapes with no icon-image sampling. One/1.5/two-pixel optical weights are fitted to the physical pixel grid; derivatives anti-alias curves and diagonals. |
| `InputAdapter.hx` | One scene-level `addEventListener` hook recording keyboard (name + counts), focus transitions, and pointer movement. Purely observational — reports to the status bar; no behavior. |
| `EditorShell.hx` | Owns chrome geometry: draws top bar, side panels, console area, status bar into one `h2d.Graphics`; positions widgets; exposes editor command callbacks upward. Rebuilds static geometry only on resize. |
| `windows/ApplicationWindowManager.hx` | Starts and owns one reusable native host process per application-level editor window. This is the safe multi-window boundary for the locked Heaps 2.1 DX12 driver, whose swap chain is process-window scoped. Opening the relevant parent menu prepares a hidden host; parent/host show/quit commands travel over a private stdin pipe. |
| `windows/KeybindingsWindowApp.hx` / `KeybindingsWindowContent.hx` | Native top-level Editor Keybindings window and its retained-H2D content. Close/Escape hides the hosted HWND; reopening reuses its existing DX12 device and font cache. Persisted changes synchronize to the running editor through the validated keybinding store. |
| `widgets/UiButton.hx` | `h2d.Interactive` hit region + centered label; hover/push/release-outside color states; click callback. |
| `widgets/NumericDragField.hx` / `AxisValue.hx` | DCC-style numeric transform editing through text, arrow steps, and raw-input horizontal scrubbing that remains active beyond window and desktop edges. Fractional stabilization rounds only the remainder, avoiding 32-bit overflow for large transform values. |
| `editor/ScalePolicy.hx` | Shared signed-scale finite-number safety and zero dead-zone policy used by Inspector commits, grid snapping, and scale gizmos. |
| `editor/WorldBounds.hx` | Shared ±8 km world policy. Position, rotation, scale, snapping, creation, and gizmo commands constrain complete transformed object bounds without deleting scene objects. |
| `widgets/ConsolePanel.hx` | Bounded append-only log (timestamped, up to 9 complete visible lines) rendered as one clipped multiline `h2d.Text`. |

## Key design rules established at M0

1. **Transparent viewport.** The chrome never fills the center column; `s3d` shows through `s2d`. (The starter filled the whole window with an opaque background and hid the 3D scene — fixed in M0.)
2. **Command flow, not direct mutation.** Widgets call shell callbacks; `Main` maps transform/reset/proportional-scale commands to engine objects. Gate 4 will formalize this into an editor command queue.
3. **Resize-aware, allocation-conscious.** Static chrome geometry is rebuilt only when the OS window size changes; per-frame work is limited to state synchronization.
4. **Positive driver identification.** The app logs the driver class at startup; acceptance requires this line rather than inferring DX12 from the compile flag.
5. **Toolchain as a locked set.** Compiler/runtime/bindings are pinned together (see `docs/TOOLCHAIN_VERSIONS.md`); `tools/build.ps1 -Check` enforces the pins.
6. **Runtime font identity.** Inter Regular, SemiBold, and Bold remain separate TTF faces. FreeType uses each face's native TrueType hinting and pen advances instead of resizing a pre-rasterized font or synthesizing weight.
7. **Editor rotation convention.** Rotation X/Z are converted to Heaps Z/X at the command boundary; numeric fields, colored rings, picking, and gizmo quaternion application all use the same mapping while Y is unchanged.
8. **Application windows are real OS windows.** Editor dialogs and future detached panels do not emulate title bars inside the main render surface. Each gets a native hldx HWND/DX12 surface with a Windows dark title bar; transient menus and dropdowns remain in-window popups. A closed auxiliary HWND is hidden and cached until editor shutdown, avoiding repeat process, device, and font initialization.
9. **Scale is signed but never singular.** Negative components mirror geometry; Inspector, snapping, linked scaling, and gizmos share a ±0.01 dead zone around zero. Odd-negative parity swaps face culling so reflected mesh exteriors remain visible.
10. **World bounds constrain geometry, not scale factors.** Using the editor's Unreal-style centimetre units, the scene spans `[-800000, +800000]` (±8 km) on X/Y/Z. Transform commands keep each object's transformed bounds inside that cube, report clamping, and never remove an object for crossing it. Large meshes enclosing the editor camera temporarily render two-sided so they remain identifiable and editable.

## Deliberately out of scope at M0

Immediate-mode BoltUI API, splitters/docking, text input, menus, picking, asset pipeline, PBR, packaging to a standalone executable, and multi-monitor/DPI validation beyond basics. These follow in Gates 4–5 per `docs/IMPLEMENTATION_SEQUENCE.md`.
