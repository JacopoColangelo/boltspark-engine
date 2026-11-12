# Native foundation implementation sequence — Windows 11 / DirectX 12

## Gate 0 — Reproducible Windows toolchain

**Tasks**
- Install Haxe 4.3+, a compatible HashLink x64 build, Heaps 2.1.0, `format`, and `hldx` 1.16.0 (or a documented compatible set).
- Confirm `hl.exe` is available on `PATH` and the matching HashLink distribution provides both `directx.hdll` and `dx12.hdll`.
- Install the DirectX 12 Agility SDK package matching `HL_DX12_AGILITY_VERSION` used by that HashLink runtime; place `D3D12Core.dll` and `d3d12SDKLayers.dll` in `D3D12` beside `hl.exe`.
- Record exact Haxe, HashLink, HashLink native module hashes, Agility SDK version, Heaps, `format`, `hldx`, Windows build, GPU model, and driver version.
- Do not install or depend on `hlsdl` for this Windows-first project configuration.

**Exit criteria**
- `haxe --version`, `hl --version`, and `haxelib list` are captured in `docs/TOOLCHAIN_VERSIONS.md`.
- `haxelib path heaps`, `haxelib path format`, and `haxelib path hldx` succeed.
- Both HashLink native modules (`directx.hdll` and `dx12.hdll`) are found by the HashLink VM.
- Both required Agility SDK runtime DLLs are present in `D3D12` beside `hl.exe`, with a version matching the HashLink runtime build.
- `compile.hxml` explicitly includes `-D dx12`.
- The same checkout compiles twice without dependency changes.

## Gate 1 — Native DirectX 12 Heaps application

**Tasks**
- Compile the starter `Main extends hxd.App` target with `-lib hldx -D dx12`.
- Launch the resulting `.hl` file using the HashLink VM on Windows 11 x64.
- Verify the window title, close behavior, and vsync setting.
- Confirm no browser or alternate graphics backend process is spawned.

**Exit criteria**
- A normal Windows desktop window opens using the DirectX 12 backend.
- Runtime logs or diagnostics identify the expected Direct3D 12 device/backend; verify no D3D11 renderer was selected.
- No Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, browser, Node, SDL, or OpenGL fallback is involved in this configuration.
- Clean shutdown; no crash on close.

## Gate 2 — 2D + 3D rendering

**Tasks**
- Render the test mesh in `s3d`.
- Render the editor overlay in `s2d`.
- Confirm resize updates the H2D layout and the 3D aspect ratio/FOV (the starter updates both explicitly).
- Verify the Direct3D 12 device and driver on the actual target hardware.

**Exit criteria**
- Both scenes render in the same process and the 2D overlay appears above the 3D content.
- [x] Drag-resize the native window while confirming rendering and layout continue updating.
- [ ] Test small, large, maximized, and restored sizes without stale geometry or crashes.
- No warnings/errors from the DirectX runtime during this smoke test.

## Gate 3 — Input and UI event flow

**Tasks**
- Click the sample button.
- Add keyboard event reporting to the central input adapter.
- Verify focus, pointer capture, release-outside, and resize events before adding draggable dock splitters.

**Exit criteria**
- Every click registers exactly once.
- Clicking outside does not activate the control.
- Window focus loss/regain does not leave a stuck pressed state.

## Gate 4 — BoltUI minimum system

Implement in this order:
1. Theme tokens and logical units.
2. Rect/layout primitives and vertical/horizontal containers.
3. Stable widget IDs and persistent UI state.
4. Button, label, separator, panel.
5. Pointer capture and keyboard focus.
6. Splitter and simple dock tree.
7. Text input and menu primitives.

**Exit criteria**
- A two-panel split layout resizes by dragging.
- Panel layout survives window resize and state changes.
- UI controls issue editor commands; they do not directly mutate engine state.

## Gate 5 — Viewport embedding decision

The prototype clips `s3d` to the computed viewport rectangle with Heaps `Engine.setRenderZone`, then resets the render zone before drawing H2D chrome. The camera projection is centered on the viewport, and viewport-local clicks are converted to window coordinates before unprojection into collider rays.

**Exit criteria**
- [x] 3D content is clipped to the viewport rectangle rather than hidden only by opaque panels.
- [x] Picking rays use viewport-local coordinates and synchronize hierarchy selection.
- [x] Native DX12 smoke tests confirm viewport clipping, cube selection, empty-space deselection, and camera/picking alignment after a 1440x900 to 1280x800 window resize.
- [ ] Dock-splitter resize and high-DPI behavior are validated on a Windows target.
- [ ] Device-loss/reset runtime validation remains pending.

## DX12-specific validation

DX12 is the baseline, not a later experiment. Before declaring the foundation complete, validate the matching HashLink VM, `directx.hdll`, `dx12.hdll`, Agility SDK version, `D3D12` runtime DLL placement, debug-layer behavior, and GPU support as one tested set. A future D3D11 fallback would require a separate explicit build configuration and architecture decision; it must not be automatic.

## Only after Gate 5

Proceed to scene hierarchy, inspectors, asset browser, project settings, and HIDE data migration. Do not start deferred rendering, GI, terrain, physics, or the full editor before the native UI and viewport gates pass.

## Gate 6 — First scene hierarchy editing slice

The initial editor scene contains selectable cube objects managed by the editor. The hierarchy can create and delete cubes; selecting an object updates the inspector, and viewport picking selects the nearest object.

**Exit criteria**
- Create, rename, select, and delete multiple objects without stale hierarchy rows.
- Inspector edits affect only the selected object and persist when switching selection.
- Viewport picking selects the nearest cube; empty-space clicks clear selection.
- Long hierarchy lists can be navigated without rows escaping the panel bounds.
- Scene save/load, undo/redo, and general entity/component authoring remain later milestones.

## Gate 7 — Editor panel usability and object creation

The hierarchy lists only scene objects and uses a real scrollbar when its content
overflows. Ctrl-click and Shift-click support multiple selection; Delete removes
all selected objects unless an inspector text field is being edited. Inspector
properties are grouped into styled cards and scroll when the panel is too short.
The console retains a bounded history, scrolls through it, and has a Clear all
button.

The toolbar Add Game Object button and hierarchy right-click menu open the same
object palette. The current palette contains a Cube template: click it to create
one at the default position, or drag it into the viewport to place it on the
ground plane. Multi-selection is supported for selection and deletion; inspector
editing is intentionally limited to a single selected object.

**Exit criteria**
- The hierarchy contains scene objects only, with selection and scrolling kept
  inside the panel.
- Toolbar and hierarchy context menu can create objects; dragging a palette
  object into the viewport creates it at the drop position.
- Multi-selection and Delete remove the intended objects; text editing keeps
  ownership of Delete while an inspector field is focused.
- Inspector properties and console history remain reachable when their content
  exceeds panel bounds, and console Clear all removes the stored log.

## Gate 8 — Viewport transform gizmo (Move tool)

The viewport shows a three-axis move gizmo at the primary selection's position.
It renders through the scene camera (`h3d.scene.Graphics`) with always-on-top
depth testing, highlights the axis under the pointer, and captures the press to
drag the object along the picked world axis. The drag solves the closest points
between the pointer ray and the axis line with press-time anchor compensation,
so the object never jumps to the pointer on the first move. Release applies the
final position through the editor command flow; a consumed press calls
`preventClick` so gizmo drags never re-pick the viewport. Rotate and Scale
tools keep the gizmo hidden until their milestones.

**Exit criteria**
- [x] The Move tool shows the axis gizmo at the selection; Rotate/Scale hide it and report as reserved.
- [x] Axis picking and hover highlighting use the pointer ray against the axis segments with a world-space threshold.
- [x] Dragging moves the object along the picked axis only, with live inspector value updates and no first-move jump.
- [x] Release applies the position through the command flow and viewport click-picking stays suppressed during the drag.
- [x] Automated evidence: a Win32 message probe (window-scoped `SendMessageTimeout`, no screen-level input injection) drives two axis-locked drags, moving sampleCube position.x 0 → -1.93 → 0 with y/z locked (`bin/gizmo-runlog.txt`).
