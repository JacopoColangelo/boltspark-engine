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
- Resize repeatedly (small, large, maximized, restore) without stale geometry or crash.
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
