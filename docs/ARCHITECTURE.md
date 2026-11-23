# Boltspark architecture — native editor foundation

This document describes the currently implemented foundation on Windows 11 x64
with HashLink + Heaps + DirectX 12. M0 is complete; reusable BoltUI and durable
project-data foundations are now being built without changing that native stack.

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
|   core/ (frame, stable IDs, input state, diagnostics)          |
|   layout/ + render/ (geometry + pooled H2D draw commands)      |
|   windows/ (separate top-level HWND process per editor dialog) |
+---------------------------------------------------------------+
| Editor (scene objects, viewport mapper, gizmos, command history)|
+---------------------------------------------------------------+
| Project data (versioned manifests/scenes, validation, storage) |
+---------------------------------------------------------------+
| Main.hx — lifecycle and integration wiring                     |
+---------------------------------------------------------------+
```

No browser technology exists anywhere in this stack. There is no Electron/CEF/WebView, no DOM/CSS, no SDL, no OpenGL.

## Startup flow

1. `tools/build.ps1 -Run` starts `hl` with `bin/` as the working directory. HashLink loads `boltspark.hl`, resolves the project-local `freetype.hdll` from `bin/`, and resolves the locked DirectX/Heaps modules from the HashLink runtime path.
2. `Main.main()` normally constructs `Main extends hxd.App`; Heaps creates the native window, 3D scene (`s3d`), 2D scene (`s2d`), and the render engine. A `--boltspark-window=...` route instead starts the requested application-level editor window with its own native HWND and DX12 swap chain.
3. `h3d.Engine` selects `h3d.impl.DX12Driver` because `compile.hxml` defines `-D dx12` (with `-D hl_ver=1.16.0` required by the driver's `hl.CArray` usage).
4. `Main.init()`:
   - logs the actual driver class name (`Type.getClassName(Type.getClass(engine.driver))`) — M0's positive driver evidence;
   - creates a sample generic GameObject with Transform + MeshRenderer; the
     Heaps bridge resolves its primitive mesh into `s3d`;
   - constructs `BoltUI` in `s2d` (the overlay); `UiContext` creates exact-size
     Inter and JetBrains Mono faces through FreeType and preloads the common
     editor characters.
5. `Main.update(dt)` runs per frame: application-window synchronization,
   GameObject component lifecycle dispatch, BoltUI's explicit begin/end frame,
   component-render-view synchronization, gizmo follow, scale/culling
   maintenance, and selection-outline synchronization. Optional performance
   and device-reset probes are disabled during normal sessions.

## Module responsibilities (src/boltspark/ui)

| Module | Responsibility |
|---|---|
| `BoltUI.hx` | Facade. Owns context/input/shell; forwards `update`/`resize`; exposes transform, reset, scale-link, object, and viewport command callbacks plus `log()`. |
| `Theme.hx` | Design tokens: colors and layout metrics. Single source of truth for chrome appearance. |
| `UiContext.hx` | Shared native window/fonts/cursors plus the backend-independent `UiFrame`. Widgets never read globals. |
| `core/` | Explicit frame lifecycle, scoped deterministic IDs, persistent widget state, input snapshots, and contract diagnostics. |
| `layout/BoxLayout.hx` | GPU-independent deterministic row, column, and stack geometry; dock geometry and persistence remain in the same package. |
| `render/` | Pooled draw-command buffer and H2D executor. Static editor chrome uses this path and reuses commands across layout rebuilds. |
| `UiText.hx` / `UiTextInput.hx` | Editor text rasterized from embedded Inter or JetBrains Mono TTF faces at its exact requested size; missing glyphs are inserted into a shared per-face atlas on demand. Console and numeric values retain JetBrains Mono Regular at 12px. |
| `UiIcons.hx` | Tabler Icons 3.52.0 rendered into dedicated 6–16px atlas entries. Runtime drawing samples exact-size alpha masks on integer coordinates and tints them for widget state; no SVG parser, package manager, or network dependency ships with the editor. |
| `InputAdapter.hx` | One window event target routes key/focus/pointer state into `UiInputState`, dispatches rebound editor actions, and reports unmatched key-up diagnostics. |
| `EditorShell.hx` | Owns chrome geometry and hierarchy interaction: nested filtering/folding, range selection, inline rename, context actions, and validated drag/drop targets; exposes editor command callbacks upward. Rebuilds static geometry only on resize. |
| `windows/ApplicationWindowManager.hx` | Starts and owns one reusable native host process per application-level editor window. This is the safe multi-window boundary for the locked Heaps 2.1 DX12 driver, whose swap chain is process-window scoped. Opening the relevant parent menu prepares a hidden host; parent/host show/quit commands travel over a private stdin pipe. |
| `windows/KeybindingsWindowApp.hx` / `KeybindingsWindowContent.hx` | Native top-level Editor Keybindings window and its retained-H2D content. Close/Escape hides the hosted HWND; reopening reuses its existing DX12 device and font cache. Persisted changes synchronize to the running editor through the validated keybinding store. |
| `widgets/AssetBrowser.hx` | Docked Unreal-style asset browser (first bottom tab): scans real project files and empty folders into a collapsible folder tree with per-row names, shows a scrollable grid of tiles with Tabler folder/scene glyphs, and supports Add → Scene/Folder, double-click Open, F2/inline Rename, drag-to-folder with Move/Copy choice, Move To / Copy To, Ctrl+C/Ctrl+V/Ctrl+X clipboard, and Delete via callbacks to `Main`. Shares the bottom dock with the Output Log through tab buttons persisted in `layout.json` v2. |
| `widgets/UiButton.hx` | `h2d.Interactive` hit region + centered label; hover/push/release-outside color states; click callback. |
| `widgets/NumericDragField.hx` / `AxisValue.hx` | DCC-style numeric transform editing through text, arrow steps, and raw-input horizontal scrubbing that remains active beyond window and desktop edges. Fractional stabilization rounds only the remainder, avoiding 32-bit overflow for large transform values. |
| `editor/ScalePolicy.hx` | Shared signed-scale finite-number safety and zero dead-zone policy used by Inspector commits, grid snapping, and scale gizmos. |
| `editor/WorldBounds.hx` | Shared ±8 km world policy. Position, rotation, scale, snapping, creation, and gizmo commands constrain complete transformed object bounds without deleting scene objects. |
| `widgets/ConsolePanel.hx` | Bounded append-only log (timestamped, up to 9 complete visible lines) rendered as one clipped multiline `h2d.Text`. |

## Editor and project foundations

| Module | Responsibility |
|---|---|
| `engine/GameObject.hx` / `Component.hx` / `Transform.hx` | Generic component container, mandatory Transform, typed component queries/removal, ownership, and start/update/destroy dispatch. |
| `engine/MeshRenderer.hx` / `Mesh.hx` / `Material.hx` | Renderer-independent geometry/material assignment. Primitive factories configure ordinary GameObjects; the editor Heaps bridge owns concrete `h3d.scene.Mesh` projections. |
| `engine/ComponentRegistry.hx` / `engine/inspector/` | Extensible scene factories and UI-neutral Inspector property metadata. Unknown serialized components remain opaque and round-trip safely. |
| `editor/EditorViewport.hx` | One source of truth for render-zone composition and viewport/window/backbuffer coordinate conversion used by rendering, rays, and gizmos. |
| `editor/EditorSession.hx` / `SceneHierarchy.hx` | Renderer-independent owner of generic component-based scene objects, the ordered scene graph, durable/runtime IDs, selection, clipboard, and bounded history. Hierarchy mutation is centralized; iterative traversal and revision-stamped world matrices avoid recursion and eager subtree invalidation. `Main` mirrors this model into nested Heaps nodes. |
| `editor/EditorTransform.hx` / `TransformMatrix.hx` | Exact local affine state: position, normalized quaternion interpretation, signed non-zero scale, and shear. Matrix decomposition retains the shear required by world-preserving reparenting between rotated, non-uniform ancestors. |
| `editor/commands/` | Concrete create/delete/duplicate/reparent/rename/transform commands plus bounded execute/undo/redo history and failure-safe composites. Structural commands restore parent, sibling order, transform, identity, and selection. |
| `project/` | Stable IDs, safe project-relative paths, versioned project/scene models, strict validation, unknown-field preservation, atomic storage with backup, and `SceneSerializer` mapping for hierarchy/component/exact-transform state. `ProjectSession.hx` adds the editor-facing layer: current documents/paths, project-relative resolution, dirty state, unique multi-scene allocation, rename/delete, and session rebuild on open/save. |
| `tests/repro/` | Portable math/UI/data/command tests plus native-module regressions. |
| `tests/native/` | Tracked HWND lifecycle, command-history, DPI, forced DX12 reset, smoke, and performance probes; outputs go to ignored `bin/test-results/`. |

## Key design rules established at M0

1. **Transparent viewport.** The chrome never fills the center column; `s3d` shows through `s2d`. (The starter filled the whole window with an opaque background and hid the 3D scene — fixed in M0.)
2. **Command flow, not direct widget mutation.** Widgets call shell callbacks;
   the pure `EditorSession` executes create/delete/rename/transform commands and
   `Main` synchronizes their models to engine objects. Inspector scrubs and
   complete gizmo drags retain live previews but commit one history entry.
   Undo/Redo is exposed through the Edit menu and rebindable shortcuts.
3. **Resize-aware, allocation-conscious.** Static chrome geometry is rebuilt only when the OS window size changes; per-frame work is limited to state synchronization.
4. **Positive driver identification.** The app logs the driver class at startup; acceptance requires this line rather than inferring DX12 from the compile flag.
5. **Toolchain as a locked set.** Compiler/runtime/bindings are pinned together (see `docs/TOOLCHAIN_VERSIONS.md`); `tools/build.ps1 -Check` enforces the pins.
6. **Runtime font identity.** Inter Regular, SemiBold, and Bold remain separate TTF faces. FreeType uses each face's native TrueType hinting and pen advances instead of resizing a pre-rasterized font or synthesizing weight.
7. **Editor rotation convention.** Rotation X/Z are converted to Heaps Z/X at the command boundary; numeric fields, colored rings, picking, and gizmo quaternion application all use the same mapping while Y is unchanged.
8. **Application windows are real OS windows.** Editor dialogs and future detached panels do not emulate title bars inside the main render surface. Each gets a native hldx HWND/DX12 surface with a Windows dark title bar; transient menus and dropdowns remain in-window popups. A closed auxiliary HWND is hidden and cached until editor shutdown, avoiding repeat process, device, and font initialization.
9. **Scale is signed but never singular.** Negative components mirror geometry; Inspector, snapping, linked scaling, and gizmos share a ±0.01 dead zone around zero. Odd-negative parity swaps face culling so reflected mesh exteriors remain visible.
10. **World bounds constrain geometry, not scale factors.** Using the editor's Unreal-style centimetre units, the scene spans `[-800000, +800000]` (±8 km) on X/Y/Z. Transform commands keep each object's transformed bounds inside that cube, report clamping, and never remove an object for crossing it. Large meshes enclosing the editor camera temporarily render two-sided so they remain identifiable and editable.
11. **Serialized data is versioned and recoverable.** Project and scene readers
    reject unsupported schemas and unsafe paths, retain unknown fields, validate
    IDs/references, and save through temporary + backup files.
12. **Verification code is tracked; evidence is generated.** Test programs and
    native probes live under `tests/`, while machine-specific logs, screenshots,
    bytecode, and measurements remain ignored under `bin/test-results/`.
13. **Hierarchy state has one owner.** Parent/child/root collections are changed
    only through `SceneHierarchy`; UI rows and Heaps objects are projections.
    Reparenting rejects cross-scene links and cycles, preserves world matrices by
    default, and records exact reversible forest changes.
14. **Object behavior comes from components.** Every GameObject owns exactly one
    non-removable Transform. Cubes and future primitives are factory presets,
    not object subclasses or kinds. Component ownership and lifecycle are
    centralized, and the Inspector iterates component metadata rather than
    branching on GameObject type.

## Current scope boundary

Splitters, retained text input, menus, bounded picking, native packaging,
current-monitor DPI awareness, integrated project/scene open/save, and
Play/Stop runtime mode now exist. Play mode serializes the authored editor
graph into a `SceneDocument`, rebuilds a detached session from that snapshot,
and ticks component lifecycle only on the copy; Stop destroys it without ever
touching editor objects, selection, or history. Still out of scope are a
complete immediate-mode public BoltUI API, physical mixed-DPI monitor
validation, a general dock tree/detached panels, asset import, and production
materials/PBR. See `docs/PROJECT_FORMAT.md` for the implemented data boundary.
