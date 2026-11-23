# Native foundation acceptance checklist — Windows 11 / DirectX 12

Executed on 2026-11-11 on the dev machine (Windows 11 Pro build 26300 x64, RTX 3080, i7-12700K).
Evidence files are under `bin/` unless noted otherwise.
Reusable Haxe tests and native probes are tracked under `tests/repro/` and
`tests/native/`; fresh outputs are generated under `bin/test-results/`.

External hardware-only checks are currently deferred by the tracked
`ignoreExternalHardwareValidation` flag in `tests/validation-policy.json` until
M9 release hardening. They remain unchecked and must not be described as passed.
The former second-machine item was closed on 2026-11-23 on the project owner's
firsthand report that the editor runs successfully on two additional Windows 11 /
DX12 PCs. It is recorded as user-attested because no per-machine logs or
screenshots were retained; the two hardware-only items below remain deferred.

## Build/runtime

- [x] Windows 11 x64 machine and GPU/driver recorded (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Haxe compilation succeeds with the pinned toolchain using `compile.hxml` (`tools\build.ps1`).
- [x] Native release build links HashLink/C into `release\Boltspark.exe` and stages the required runtime modules beside it.
- [x] The packaged `release\Boltspark.exe` uses the Windows GUI subsystem and launches without a command window; development runs through `hl.exe` retain their diagnostics console.
- [x] The multi-resolution Boltspark ICO is embedded in `release\Boltspark.exe`, and both development and native-release HWNDs expose non-null small/large window icons (`bin/app-icon-executable.png`, `bin/app-icon-runtime.log`, `bin/app-icon-release.log`).
- [x] `compile.hxml` selects `-lib hldx`, explicitly defines `-D dx12`, and pins `-D hl_ver=1.16.0`.
- [x] HashLink VM starts the compiled `.hl` file through `tools/build.ps1 -Run`, with `bin/freetype.hdll` available in the bytecode working directory.
- [x] HashLink native module `directx.hdll` (window/input/event services) is present and loads at runtime (window opens, input works).
- [x] HashLink native module `dx12.hdll` (Direct3D 12 rendering driver) is present and loads at runtime (rendering succeeds; driver positively identified as `h3d.impl.DX12Driver`).
- [x] Project-local `freetype.hdll` loads in both HashLink and native-release runs; FreeType 2.14.3 is statically linked, so no system font-rendering dependency is installed.
- [x] **Agility SDK: not required.** The official HashLink 1.16.0 binary is a standard DX12 build; no `D3D12/` folder or Agility DLLs are needed.
- [x] Process opens a normal native Windows desktop window (`bin/m0_window.png` — title "Boltspark Engine").
- [x] No Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, browser, Node, SDL, or OpenGL fallback is launched/used: the native modules are HashLink runtime services + `dx12.hdll`/`directx.hdll`/`heaps.hdll` and the project-local `freetype.hdll`; `hlsdl`/`sdl.hdll` is never referenced by the build (`compile.hxml` checked by `tools/build.ps1 -Check`).
- [x] Window closes cleanly (run exits with code 0 on close).
- [x] One tracked entry point (`tools/tests/test.ps1`) enforces the native-only policy,
  compiles the complete project, runs portable/native regressions, and can add
  development + packaged-release HWND smoke tests. Hosted Windows CI executes
  its portable path (`.github/workflows/windows-ci.yml`).

## Rendering

- [x] DX12 driver is positively identified in runtime diagnostics, not only inferred from the compile flag: `[M0] renderer driver = h3d.impl.DX12Driver` (`bin/runlog.txt`).
- [x] 3D cube appears in the 3D scene using the Heaps DX12 driver (`bin/m0_window.png`, `bin/m0_input_test.png`).
- [x] The editor cube is a stable, static orange primitive by default; rotation and color are no longer driven by sample/demo behavior.
- [x] H2D editor chrome appears over the bounded 3D viewport (top bar, hierarchy, inspector, console, status bar).
- [x] The embedded Boltspark artwork is rendered in the main editor title strip in place of the procedural placeholder and `BOLTSPARK` text (`bin/app-icon-editor.png`).
- [x] Compact flat editor styling renders in the native DX12 window with square-edged controls, continuous inspector sections, and no legacy rounded-surface texture (`bin/ui-compact-editor.png`).
- [x] The native release keeps the compact hierarchy, viewport, inspector, and console aligned after a live resize to 1280x800 (`bin/ui-compact-release-1280.png`).
- [x] 3D content is clipped to the viewport rectangle by the render zone, aligned with the editor panels.
- [x] Clicking the sample cube selects it from the viewport; clicking empty viewport space clears hierarchy selection.
- [x] Create multiple cubes, select and rename them from the hierarchy, and verify inspector edits stay with the selected object.
- [x] Delete selected objects and verify hierarchy rows and viewport meshes are removed together.
- [x] Navigate a long hierarchy list and select objects above and below the visible range.
- [x] Pick a created cube in the viewport and verify its hierarchy row and inspector become active.
- [x] Native window resize (1440x900 to 1280x800) updates viewport framing and picking coordinates without stale content or crashes.
- [x] Dock-splitter resize is validated against viewport framing and picking:
  the tracked lifecycle probe moved the left panel from 250px to 350px, persisted
  the new layout, deselected in empty viewport space, and selected the origin cube
  at the recalculated center (`tests/native/Test-WindowLifecycle.ps1`).
- [x] Small/large/baseline resize, maximize/restore, and minimize/restore retain
  a responsive native window (`tests/native/Test-WindowLifecycle.ps1`).
- [x] The reference monitor reports a per-monitor-aware process, Win32 96 DPI,
  and matching hldx 1× display scale (`tests/native/Test-DpiAwareness.ps1`).
- [ ] **Deferred by validation policy:** physical transitions between monitors at multiple Windows scaling factors.
- [x] Heaps' explicit DX12 context-loss path disposes/recreates the driver,
  invokes resource restoration, leaves the HWND responsive, and closes cleanly
  (`tests/native/Test-DeviceReset.ps1`).
- [ ] **Deferred by validation policy:** genuine driver/OS-triggered DXGI device-removal recovery.
- [x] Text is legible at baseline window size (1440x900 default; verified at 1296x900 after resize).
- [x] Inter Regular, SemiBold, and Bold are rasterized from embedded TTF data by FreeType at exact 11/13/15px sizes, using native face hinting and correct pen advances; un-preloaded characters are cached on demand (`bin/ui-freetype-native-hint.png`, `bin/ui-freetype-release.png`, `bin/freetype-runtime-repro.log`). JetBrains Mono Regular uses the same path at 12px for console and numeric values while preserving its former 17px line height, 13px baseline, 7px digit advance, and zero-kerning fixed-width layout (`bin/console-freetype.png`, `bin/numeric-freetype.png`, `bin/text-freetype-evidence.txt`).
- [x] Scene-hierarchy object labels are vertically centered from the exact Inter line metrics instead of the stale 4px offset; their text body now aligns with the disclosure/cube icon row (`bin/hierarchy-alignment.png`).
- [x] The current editor control glyphs use the pinned Tabler Icons 3.52.0
  mapping and dedicated 6–16px atlas rasters, including the Asset Browser's
  Folder and Scene glyphs. PrintWindow captures from the
  development and packaged DX12 editors are pixel-identical, and both native
  smoke launches close cleanly (`src/res/icons/tabler_ui.png`,
  `bin/test-results/tabler-icons-native.png`,
  `bin/test-results/tabler-icons-release.png`).
- [x] Resize behavior: chrome redraws to the new client size (`bin/m0_input_test.png` was captured at a resized 1296x900 window with correct layout). Maximize/restore re-uses the same `resize()` path.
- [x] Native title-bar movement does not run the full vsynced interactive-resize renderer. The packaged-release Win32 probe measured move-loop timer dispatch at 8.381 ms average versus 23.609 ms while the resize callback was deliberately active; live rendering remains enabled for `WM_SIZING` only (`tests/native/historical/verify-move-loop.ps1`, `bin/window-behavior-evidence.txt`).
- [x] No Direct3D 12 device/runtime errors during the test (no exception dialogs, clean run log).

## Input

- [x] Toolbar Add, the hierarchy `+`, and hierarchy right-click all open the same compact game-object palette (`bin/compact-add-toolbar.png`, `bin/compact-add-hierarchy-button.png`, `bin/context-hierarchy-compact.png`).
- [x] Right-click creation is scoped to hierarchy rows and empty hierarchy space; right-clicking the viewport does not open the palette (`bin/context-hierarchy-empty-compact.png`, `bin/context-viewport-no-menu.png`).
- [x] An open right-click Add Object palette closes when empty viewport, hierarchy, inspector, or console space is left-clicked (`bin/palette-dismiss-open.png`, `bin/palette-dismiss-viewport.png`, `bin/palette-dismiss-inspector-selected-open.png`, `bin/palette-dismiss-inspector-selected.png`, `bin/palette-dismiss-console.png`, `bin/palette-dismiss-hierarchy.png`).
- [x] The compact palette uses a 28px single-line Cube entry and preserves its click-to-create target (`bin/compact-add-created-cube.png`).
- [x] Clicking the compact Cube row creates a hierarchy object; dragging it into the viewport shows a compact preview, creates, and selects it (`bin/compact-toolbar-row-click-fixed.png`, `bin/compact-add-drag-preview.png`, `bin/compact-add-drag-created.png`).
- [x] Selected objects no longer add a redundant Delete toolbar button; the Delete key still removes the selection (`bin/ui-no-delete-button.png`, `bin/delete-key-object-removed.png`).
- [x] Ctrl-click selects multiple hierarchy objects; Delete removes all selected objects and clears the inspector selection.
- [x] A long hierarchy shows a scrollbar without listing editor/debug controls among scene objects.
- [x] Hierarchy wheel scrolling is direction-correct with a long list (`bin/wheel-hierarchy-top.png`, `bin/wheel-hierarchy-after-down.png`).
- [x] Hierarchy scrollbar thumb dragging is direction-correct with a long list (`bin/thumb-hierarchy-before.png`, `bin/thumb-hierarchy-after-up.png`).
- [x] Console scrollbar appears after enough log entries and its thumb reaches earlier log lines.
- [x] Console wheel-up reaches older entries and wheel-down returns to newer entries (`bin/wheel-console-after-up.png`, `bin/wheel-console-after-down.png`).
- [x] Clear all removes the console history.
- [x] Normal editor sessions do not flood the Output Log with startup, tool-switch, selection, transform, snapping, or gizmo telemetry. After launch, a Rotate switch, and a viewport selection change, the panel remained empty and development stdout contained only the required DX12 driver identity; `BOLTSPARK_PROBE`/`BOLTSPARK_VERBOSE_LOGS` restores detailed diagnostics for automated probes (`bin/quiet-console.png`, `bin/quiet-console-stdout.txt`, `bin/verbose-console-probe-stdout.txt`).
- [x] Inspector thumb dragging reveals later properties clipped by a short panel (`bin/thumb-inspector-before.png`, `bin/thumb-inspector-after-down.png`).
- [x] Each removable component section exposes a header trash action; clicking it detaches the component and commits one undoable `Remove <Component>` command. The mandatory Transform publishes `removable = false` and has no remove action (`tests/native/Test-ComponentRemoval.ps1`, `tests/repro/ComponentSystemRepro.hx`).
- [x] Inspector wheel scrolling is direction-correct over property values, while a value owns keyboard focus, and directly over the scrollbar (`bin/wheel-property-after-down.png`, `bin/wheel-property-focused-after-down.png`, `bin/wheel-scrollbar-after-down.png`).
- [x] Shift-click selects a contiguous range in the hierarchy.
- [x] Left-clicking empty hierarchy list space or uncovered hierarchy header chrome clears keyboard focus and object selection, while rows and Search retain their own behavior (`bin/hierarchy-empty-body-deselect.png`, `bin/hierarchy-empty-header-deselect.png`, `bin/hierarchy-search-preserves-selection.png`).
- [x] Delete is suppressed as an object command while editing inspector text or transform values (`bin/delete-key-edit-safe.png`).
- [x] Numeric transform properties use compact up/down arrows instead of separate +/- buttons; arrow clicks apply the configured 0.1 step (`bin/numeric-drag-fields.png`, `bin/numeric-axis-scrub-right.png`).
- [x] Horizontal click-drag scrubbing changes transform-axis values in 0.1 steps, with each change flowing through editor commands. Native mouse capture keeps the scrub active beyond windowed client bounds and delivers the outside release; after the drag threshold, hldx raw-input mode keeps accumulating movement at desktop edges (`bin/numeric-axis-scrub-right.png`, `bin/numeric-outside-capture-evidence.txt`, `bin/numeric-unbounded-scrub-evidence.txt`).
- [x] Clicking a numeric value without dragging focuses and selects its text for direct keyboard editing (`bin/numeric-click-edit-focus.png`).
- [x] Focus loss/regain does not leave stuck visual/input state (input adapter reports focus transitions; button color restored on release-outside).
- [x] Native cursor policy is stable: ordinary editor controls use Arrow, text values use IBeam, splitters use SizeWE/SizeNS, and the draggable palette item uses SizeAll; numeric scrub regions use SizeWE while hovered but restore Arrow after leaving or releasing a drag outside (`bin/cursor-regression.txt`, `bin/numeric-cursor-dismiss-regression.txt`, captured with Win32 `GetCursorInfo`).
- [x] Keyboard event reporting flows through the central input adapter (status bar shows `key ... | dN uN mvN focus G/L` live; `boltspark/ui/InputAdapter.hx`).

## Grid snapping and rebindable editor shortcuts

Executed on 2026-11-14 with window-scoped native key/mouse events against the HashLink/DX12 windows. Current application-window evidence is in `bin/main-dark-titlebar.png`, `bin/keybindings-native-window.png`, `bin/keybindings-native-window-rebound.png`, and `bin/native-window-evidence.txt`; earlier shortcut/drag evidence remains in `bin/keybindings-v-held.png`, `bin/keybindings-evidence.txt`, `bin/keybindings-final-runtime.log`, and `bin/snap-hold-*.log`.

- [x] The viewport exposes independent translation, rotation, and scale snap toggles plus preset dropdowns; the controls stay inside the live splitter-sized viewport and the active values are visible in the native DX12 render.
- [x] Default tool shortcuts are 1 Move, E Rotate, and R Scale. One native run emitted `viewport tool: Rotate gizmo active` for E and `viewport tool: Scale gizmo active` for R (`bin/keybindings-final-runtime.log`).
- [x] Holding V temporarily disables translation snapping without changing its stored toolbar toggle. Identical X-axis drags ended at snapped `x=1` normally and unsnapped `x=0.8` while V was held (`bin/snap-hold-on.log`, `bin/snap-hold-bypass.log`). The translation cell also renders inactive during the hold (`bin/keybindings-v-held.png`).
- [x] V cannot stick when modifiers change or focus is lost: the sequence V-down, Ctrl-down, V-up, Ctrl-up emitted one suspend and one resume transition (`bin/keybindings-evidence.txt`).
- [x] The main editor and Editor Keybindings HWNDs use the Windows immersive-dark-mode title bar (`bin/main-dark-titlebar.png`, `bin/keybindings-native-window.png`).
- [x] File → Editor Settings → Editor Keybindings opens a separate, responsive native top-level HWND with a task-switchable lifecycle, retained-H2D client area, and DX12 swap chain in both development and native-release builds. Opening File prepares the host while hidden; OS-close/Escape hides the HWND, and reopening restores the same child PID/HWND without rebuilding its DX12 device or font cache. Closing the main editor terminates the cached host (`bin/native-window-evidence.txt`).
- [x] The keybindings HWND is assigned the launching editor as its native owner before its first show, then explicitly restored/raised/activated. A first-open menu probe confirmed `GW_OWNER == editor HWND`, preventing the settings window from opening behind the editor (`tests/native/historical/verify-first-keybindings-open.ps1`, `bin/window-behavior-evidence.txt`).
- [x] Rebind capture ignores modifier-only events: Ctrl then T captured `Ctrl+T` for Rotate in the separate window, persisted a complete versioned JSON map, synchronized into the already-running main editor, and immediately selected Rotate there (`bin/keybindings-native-window-rebound.png`, `bin/native-window-evidence.txt`). Duplicate chords are rejected and malformed/partial persisted maps leave the complete live/default map intact in `Keybindings.hx`.
- [x] Shortcut commands, hold snapping, snap-to-grid, and Delete remain suppressed while an inspector/search text control owns keyboard capture.
- [x] The Editor Keybindings window shows all 20 actions in 7 categories in a
  scrollable list with a native scrollbar and no instructional/mouse helper
  text; shrinking the HWND switches the list into its clipped scroll mode
  (`tests/native/Test-KeybindingsList.ps1`, `bin/test-results/keybindings-list/keybindings-state.log`).
- [x] Viewport camera settings popups and editor dropdown/menu bodies keep the
  standard arrow cursor instead of Heaps' `Cursor.Button` pointing hand.
- [x] Undo and Redo are exposed through the native Edit menu and rebindable
  Ctrl+Z/Ctrl+Y defaults; Ctrl+S saves the current scene and Ctrl+Shift+S saves
  all; Ctrl+C/Ctrl+V/Ctrl+X copy, paste, and cut assets in the Asset Browser.
  Historical keybinding maps migrate to version 7 by retaining existing
  actions and appending collision-free history, hierarchy, grid, focus, save,
  and Play/Pause/Stop transport bindings (including Shift-aware chords).

## Viewport camera navigation

Executed on 2026-11-16 through the production-controller HashLink regression
(`tests/repro/EditorCameraControllerRepro.hx`) and followed by successful DX12
development/release native smoke launches.

- [x] Hover alone leaves WASD/QE inert; RMB capture enables flight, and RMB
  release immediately clears smoothed velocity.
- [x] An idle wheel over the viewport dollies along the view axis (up moves in,
  down moves out), while RMB+wheel retains camera-speed adjustment.
- [x] Alt+LMB orbit uses the corrected Unreal-style horizontal and vertical
  tumble directions.
- [x] Rebindable F Focus Selection smoothly frames the complete world-space
  bounds of every selected object (their union), with aspect/FOV-aware padding
  and preserved view rotation; empty GameObjects contribute their world pivot,
  and a multi-object frame visibly differs from a single-object frame
  (`tests/repro/EditorCameraControllerRepro.hx`).
- [x] Focus is a selection command, not viewport navigation: F works with any
  active selection even when the pointer stays over the hierarchy panel
  (`tests/native/Test-FocusSelection.ps1`, `bin/test-results/focus-selection/stdout.log`).
  Text entry and an active viewport gesture still suppress it.
- [x] Its fixed-duration cubic ease completes exactly after nearby or
  multi-million-unit travel, while direct camera navigation and gizmo input
  cancel the flight immediately.
- [x] The PERSPECTIVE strip opens a camera-settings popup whose field of view is
  a transform-style `NumericDragField` spanning 30°–140° instead of a preset
  dropdown: click to type an exact value, drag to scrub, or step with arrows.
  While the field owns text focus, editor shortcuts stay suppressed. A
  window-scoped probe types and commits an exact value and confirms it reaches
  the shared viewport FOV and the strip label
  (`tests/native/Test-FovInput.ps1`, `bin/test-results/fov-input/stdout.log`).

## Viewport transform gizmo (Move tool)

Executed on 2026-11-12 with the automated Win32 probe (`tests/native/historical/verify-gizmo-drag.ps1`): synchronous `SendMessageTimeout` mouse events addressed to the Boltspark window handle only (no screen-level input injection), with stdout mirrored to `bin/gizmo-runlog.txt`.

- [x] The Move tool shows a three-axis gizmo at the primary selection's position, rendered in `s3d` through the scene camera with always-on-top depth testing (now part of the full three-tool gizmo suite below; the Rotate/Scale-reserved behavior it references was superseded by `tests/native/historical/verify-transform-gizmo.ps1` evidence).
- [x] Hovering an axis highlights it; picking compares projected handle samples against a 14-pixel screen-space threshold, keeping interaction stable across camera distance.
- [x] Pressing an axis starts a constrained drag that moves the object along that world axis only, with the gizmo following per frame and inspector transform values updating live (`bin/gizmo-runlog.txt`).
- [x] Drag motion captures a press-time projected axis mapping and applies accumulated pointer displacement from that unchanged anchor, so the object does not jump on the first move and sensitivity does not decay outside the viewport (zero-delta at press verified).
- [x] Releasing a gizmo drag applies the final position through the editor command flow (`command: sampleCube position.x = ...`) and never falls through to viewport click-picking (`preventClick`; no `viewport:` line appears during drags in `bin/gizmo-runlog.txt`).
- [x] Axis-locked motion both directions: drag 1 moved sampleCube position.x 0 → -1.93 with y/z locked at 0; drag 2 pressed on the moved cube's projected pixel and returned it to 0 (`bin/gizmo-runlog.txt`, `bin/gizmo-drag-evidence.txt`).

## Full transform gizmo suite (Move planes, Rotate, Scale, shortcuts)

Executed on 2026-11-12 with the automated Win32 probe (`tests/native/historical/verify-transform-gizmo.ps1`): three sessions with app relaunches between tools so every press starts with sampleCube at the origin; window-scoped `SendMessageTimeout` mouse and key messages only, no screen-level input injection. Engine evidence mirrored to `bin/gizmo-runlog-move.txt`, `bin/gizmo-runlog-rotate.txt`, `bin/gizmo-runlog-scale.txt`, summarized in `bin/transform-gizmo-evidence.txt`.

- [x] All three tools drive live viewport gizmos from one gizmo implementation (`TransformGizmo.hx`): Move (axes + two-axis plane quads + center free-move square), Rotate (active-space axis rings + center wire-sphere arc-ball), Scale (axis boxes + plane quads + center uniform box), all rendered as Unreal-style wireframe handles with always-on-top depth testing (`bin/gizmo-runlog-*.txt`).
- [x] Historical Gate 9 evidence used number-row shortcuts (2 → Rotate, 3 → Scale, 1 → Move) and verified the text-editing guard (`bin/gizmo-runlog-rotate.txt`, `bin/gizmo-runlog-scale.txt`). The current mapping supersedes 2/3 with the rebindable E/R defaults verified in the grid-snapping/keybindings section above.
- [x] Two-axis plane drags move the selection inside the handle's plane with the third axis locked: plane.xy drag ended at (-0.02, 0.87, 0) — z stayed exactly 0 across the whole drag (`bin/gizmo-runlog-move.txt`). The plane basis used for drawing/picking is scratch state separate from the drag's captured frame, so per-frame redraws cannot corrupt an active plane drag.
- [x] Rotation gizmo: WORLD-space ring drag applies only around the selected world axis from the static default cube (latest ring result `(27.82, 0, 0)` degrees). The center region uses a true virtual hemisphere rather than the old z=0 direction circle; the following omni drag produced `(38.55, -73.88, 21.93)` degrees, demonstrating camera-space tumble rather than screen roll (`bin/gizmo-runlog-rotate.txt`).
- [x] The omni arc-ball remains freeform when the 15° rotation snap is enabled: a mixed-axis drag ended at `(37.11, -40.9, -15.63)` degrees, while a separate axis-ring drag under the same enabled snap landed at exactly `(30, 0, 0)` degrees (`bin/gizmo-arcball-freeform-snap-on.txt`, `bin/gizmo-ring-snap-still-on.txt`).
- [x] A torus drag immediately after an arbitrary arcball tumble preserves the
  captured world/local axis and snaps only its accumulated angle; it never
  re-decomposes the freeform quaternion into coupled Euler deltas. The portable
  regression retains the same orientation at raw 51°/52° inside one 45° snap
  bin and advances exactly 15° at the next boundary. The native window-scoped
  probe moved `(50.59, -36.57, -28.8)` to
  `(20.59, -36.57, -28.8)` with empty stderr
  (`tests/repro/RotationRingRepro.hx`,
  `tests/native/Test-RotationRingHandoff.ps1`,
  `bin/test-results/rotation-ring-handoff/development.stdout.log`).
- [x] Rotation uses a continuous per-object Euler hint internally rather than Heaps' smallest-magnitude branch, but Details/Inspector presentation follows Unreal-style normalized Rotator values in `(-180°, 180°]`. The headless regression covers full turns, both ±90° gimbal branches, exact quaternion reconstruction, and boundary cases from -725° through +725°. In the native editor, eight accumulated arc-ball drags wrapped the display from `(173.67, 164.97, 174.13)` to `(-162.26, -116.04, -168.43)` without interrupting quaternion motion, and every reported component passed the range assertion (`tests/repro/RotationEulerRepro.hx`, `bin/rotation-euler-repro.log`, `bin/gizmo-arcball-normalized-rotator.txt`).
- [x] Arc-ball response remains continuous and unbounded while the pointer enters, exits, and travels far beyond the virtual sphere. Large raw-input deltas use the production subdivision count; pointer positions map to a C1 Bell trackball surface (spherical cap inside, hyperbolic sheet outside), whose successive points choose the 3D axis, while linear pointer travel supplies an undamped angle. The shared headless regression verifies the exact Bell join, equal coarse/fine radial results at 1/5/20 trackball radii, and exact out-and-back reversal (`tests/repro/ArcballRotationRepro.hx`, `bin/arcball-rotation-repro.log`).
- [x] Arc-ball direction remains camera-relative over the whole virtual sphere: trackball vectors map directly to the camera basis (right, up, toward-scene) with camera-facing surface points at z <= 0, and successive vectors accumulate through `previous x current` without reflection artifacts, so off-center, quadrant, and outside-rim drags roll with the pointer instead of intermittently inverting. The headless regression covers center, both off-center quadrants, a mixed diagonal, an angled camera, and both outside-rim roll directions; a native window-scoped off-center drag selected `rotation.omni`, completed at `(9.1, -5.48, -22.03)` degrees, and emitted no stderr (`tests/repro/ArcballRotationRepro.hx`, `bin/arcball-rotation-repro.log`, `bin/arcball-direction-runtime.txt`).
- [x] Rotation-ring colors follow the viewport grid convention in WORLD mode: the visible red X arc follows the red X grid direction, green remains Y, and the blue Z arc follows the blue Z grid direction. The editor's X/Z rotation components are converted consistently to Heaps Z/X for numeric entry, rendering, pick samples, drag planes, and quaternion application; red reports `rotation.x`, blue reports `rotation.z`, and neither applies the opposite physical axis (`bin/gizmo-solid-rotate.png`, `bin/ring-axis-picks-log.txt`, `bin/gizmo-runlog-rotate.txt`).
- [x] Rotation rings are clipped to their camera-facing hemisphere, producing Unity-style front arcs without showing the rear half through the object. Picking uses the same hemisphere test: the visible `+Y` crossing selected `rotation.x`, while the clipped `-Y` crossing started no gizmo drag (`bin/gizmo-front-facing-rotate.png`, `bin/gizmo-front-pick-visible.txt`, `bin/gizmo-front-pick-hidden.txt`).
- [x] WORLD/LOCAL is an active viewport control, not a label. WORLD is the default; after any explicit object rotation, LOCAL applies that quaternion to Move/Rotate/Scale drawing, screen-space pick samples, and press-captured drag axes/planes through one shared basis (`bin/gizmo-space-log.txt`).
- [x] Move center handle: pressing the screen-facing center square selected `position.view`; dragging in the camera plane moved sampleCube from (0, 0, 0) to (-0.72, 0.5, 0.32), changing all applicable world components without selecting an axis/plane (`bin/gizmo-center-move-log.txt`).
- [x] Scale gizmo: axis box drag scales only that axis (scale (1.93, 1, 1)); center uniform box scales all three axes by the same ratio relative to the drag-start scale, preserving axis ratios set by a prior axis drag ((23.99, 12.43, 12.43) = ×1.93 on all three) (`bin/gizmo-runlog-scale.txt`).
- [x] Scale values are signed: Inspector entry can mirror one axis, and Scale gizmo drags can cross the pivot into negative values. A sign-preserving ±0.01 dead zone prevents singular transforms; odd-negative scale parity swaps front/back culling so the mirrored exterior remains visible (`bin/negative-scale-mirror.png`, `bin/negative-scale-evidence.txt`).
- [x] The editor world is bounded to ±8 km on X/Y/Z (±800000 centimetre-based world units) using each object's complete transformed geometry, not an arbitrary scale-factor cap. Runtime Inspector entry retained uniform `+1200` and `-1200` scales without removing the object; a unit cube requested at positions ±900000 stopped at ±799999.5, and scales ±2000000 stopped at ±1600000. Camera-enclosing meshes remained visible from inside, the hierarchy retained its object, and stderr stayed empty (`bin/world-bounds-stdout.txt`, `bin/world-bounds-scale-1200.png`, `bin/world-bounds-scale-negative-1200.png`).
- [x] Inspector shows Position / Rotation / Scale rows; gizmo drags update all nine values live during the drag, and Rotation/Scale fields commit through the same command flow as position fields.
- [x] Selection outline traces the object's actual transformed silhouette (12 mesh edges through the object rotation/scale) instead of an axis-aligned boundary cube, and is redrawn per frame so it tracks transform edits and gizmo drags. Its two-pixel width stays in screen space without scale-relative corner inflation; near/far clipping prevents large edges crossing the camera plane from expanding into oversized outline polygons (`bin/selection-outline-scale-7000.png`).
- [x] The viewport grid uses thinner minor/major/axis strokes and an explicit earlier render layer; the depth-tested selection outline renders later, so projected grid lines cannot paint over selected-object edges (`bin/gizmo-solid-move.png`).
- [x] Reproducibility: two consecutive full-probe runs produced matching values (axis 0 → 0.73 → 0; plane z locked at 0), confirming a previously observed one-off drag flake was probe timing, not gizmo math.
- [x] Production gizmo drags use Heaps `MouseMode.Relative`: the pinned hldx backend hides/clips the cursor, registers Windows Raw Input, suppresses legacy absolute `WM_MOUSEMOVE`, and reports hardware `lLastX/lLastY` to the drag callback. Release restores `Absolute` mode and parks the cursor at the virtual drag endpoint; no edge wrapping or cursor teleport loop is used.
- [x] Beyond-edge regression: press-time screen Jacobians/tangents replace rays built from distant synthetic screen coordinates for move, ring rotation, and scale. A window-scoped unbounded X-axis probe produced 0.99, 9.95, and 19.89 world units for 1×, 10×, and 20× equal displacement; the 20× endpoint `(-971, 994)` was beyond both client edges and retained proportional motion with Y/Z locked. Ring rotation remained active at 10× displacement, while axis scale produced 1.95, 10.46, and 19.92 with its other axes fixed at 1 (`bin/gizmo-unbounded-drag-evidence.txt`).
- [x] Position and Rotation reset to `(0, 0, 0)` and Scale resets to `(1, 1, 1)` through row-level Inspector actions. Scale linking preserves the existing proportions instead of forcing equality: an unlinked `1.1/1/1` scale became `1.2/1.09/1.09` after linking and stepping X; a linked X-axis gizmo drag from reset produced `2.14/2.14/2.14` (`bin/transform-linked-scale.png`, `bin/transform-actions-log.txt`).

## Reusable UI and durable-data foundations

Executed through `tools/tests/test.ps1` on 2026-11-15; portable tests also form the
hosted Windows CI job.

- [x] BoltUI frame lifecycle reports duplicate IDs, invalid layout, and
  unbalanced scopes; scoped IDs remain stable and persistent state survives
  frames (`tests/repro/BoltUiCoreRepro.hx`).
- [x] Backend-independent input state distinguishes first key-downs and records
  unmatched key-up events, replacing the unexplained `u4` observation with
  explicit `orphanUp` diagnostics instead of affecting editor commands.
- [x] Deterministic row/column/stack layout and pooled draw commands pass
  headless tests; editor static chrome executes through the pooled H2D path.
- [x] Bounded command history passes execute, composite rollback ordering,
  undo, redo, redo-branch invalidation, and capacity tests
  (`tests/repro/CommandHistoryRepro.hx`).
- [x] The renderer-independent editor session routes create, delete, rename,
  Inspector transforms, resets, snapping, and complete gizmo drags through
  history. Structural undo restores stable identity, hierarchy order, and
  selection; transform undo preserves exact quaternion and Euler-hint state
  (`tests/repro/EditorSessionRepro.hx`). A native window-scoped probe moved the
  sample cube to `(-1, 0, 0)`, then verified Ctrl+Z restored `(0, 0, 0)` and
  Ctrl+Y restored `(-1, 0, 0)`. The same run stepped Inspector Position X,
  then exercised native Create/Delete undo and redo with Cube2 identity and
  selection restoration (`tests/native/Test-CommandHistory.ps1`).
- [x] Versioned project/scene fixtures round-trip with stable IDs, signed
  transforms, unknown fields, and component envelopes preserved. Unsafe paths,
  malformed references, duplicate IDs, cycles, and singular transforms are
  rejected; atomic saves retain a previous `.bak`
  (`tests/repro/ProjectSerializationRepro.hx`, `tests/fixtures/project/`).
- [x] The integrated project session creates, saves, and reopens `*.boltproject`
  and `*.boltscene` documents, resolves project-relative scene paths, registers
  the default scene asset, rebuilds an `EditorSession` with stable identities
  and components, tracks dirty state, and rejects missing, unsafe, and
  unsupported-version inputs (`tests/repro/ProjectSessionRepro.hx`). The full
  native build bundles `ui.hdll` for the Windows file dialogs; both development
  and packaged editors still launch and close cleanly (`tools/tests/test.ps1 -NativeSmoke`).
- [x] File menu project commands are driven end-to-end in a native DX12 window:
  Save Project As writes the manifest and scene, the title-strip dirty marker
  appears on edits and clears on save, an unsaved-change answer of `no` cancels
  close while `yes` allows it, and Open Project rebuilds the saved scene graph
  (`tests/native/Test-ProjectFiles.ps1`). Bare picker names without a filter
  extension are normalized to `.boltproject`/`.boltscene`, Save Current Scene on
  an untitled project routes to Save Project As, and new scenes allocate unique
  names/paths (`tests/repro/ProjectSessionRepro.hx`). The docked Asset Browser
  scans real project files into folders and supports Add/Open/Rename/Move/Copy/
  Delete with manifest/file consistency and a scrolling grid; the last scene is
  protected, UTF-8 BOM documents
  load, and a `.boltproject` command-line argument opens at startup
  (`tests/native/Test-AssetBrowser.ps1`). Probe hooks
  substitute scripted paths for the modal OS picker so the real menu → command →
  storage path is tested.
- [x] The professional two-pane Asset Browser adds folder tree / grid+list,
  breadcrumb + back/forward/up navigation, live search,
  type filtering, four sort keys, adjustable thumbnail size, compact and detail
  views, multi-selection, tooltips, favorites and recent assets, real generic
  file/folder operations, direct drag-to-move with Ctrl-to-copy, draggable and
  nestable folders, root-level folder creation, and contextual shortcuts. Its
  data layer is covered by headless assertions (`tests/repro/AssetBrowserRepro.hx`), the original
  native interaction probe still passes
  (`tests/native/Test-AssetBrowser.ps1`), and the rendered layout was inspected
  in a DX12 PrintWindow capture (`bin/test-results/asset-browser-visual/asset-browser.png`).
  Reveal in Explorer on the root "All" folder with no project loaded prompts
  project creation instead of throwing or opening a stray directory
  (`tests/native/Test-RevealRoot.ps1`).
- [ ] Visual click-through of the native Windows file-picker chrome itself.
  The command path is automated above; the modal OS dialog rendering is not.
- [x] The renderer-independent ordered scene graph rejects hierarchy cycles,
  preserves exact world matrices during affine reparenting, canonicalizes
  selected forests, and restores parent/sibling/transform/identity/selection
  state across complex undo/redo. Exhaustive five-root insertion permutations,
  sparse empty-parent grouping, recursive duplicate/delete, out-of-order parent
  records, and a 3,000-level chain pass
  (`tests/repro/SceneHierarchyRepro.hx`).
- [x] Nested Heaps nodes reproduce the pure scene graph's exact world matrix,
  including signed non-uniform scale and shear, and rebuild affine correction
  state after editable TRS channels change
  (`tests/repro/SceneObjectAffineRepro.hx`).

## Play mode (M4 vertical slice)

Executed 2026-11-23 through the headless isolation repro and a window-scoped
DX12 transport probe. Runtime evidence is in `bin/test-results/play-mode/`.

- [x] Play captures the authored editor graph as a `SceneDocument` and rebuilds
  a fresh detached session; runtime objects, components, and hierarchy are
  distinct instances with identical durable ids, transforms, and parenting.
  Runtime transform edits never reach the editor session, history, or selection
  (`tests/repro/PlayModeRepro.hx`).
- [x] Component `onStart`/`onUpdate`/`onDestroy` dispatch once per running frame
  and exactly once on stop; pausing suppresses both updates and elapsed time,
  and a second Play starts from the authored snapshot with fresh components
  (`tests/repro/PlayModeRepro.hx`).
- [x] The transport toolbar Play button, rebindable F5/F6/F7 shortcuts (schema
  version 7, 20 actions in 7 categories), pause/resume, and stop work in the
  real DX12 window; stdout reports object count, elapsed time, and an unchanged
  editor history revision across the cycle, with empty stderr
  (`tests/native/Test-PlayMode.ps1`, `tests/native/Test-KeybindingsList.ps1`).
- [x] Editor-only viewport overlays (grid, transform gizmo, selection outline,
  drop-target highlights) and all scene mutation callbacks are suppressed while
  playing, while camera navigation stays live; Stop rebuilds the authored
  editor views and restores the grid preference.

## External asset import and Explorer drag-in

Executed 2026-11-23 on the dev machine. Final evidence:
`bin/test-results/import-files/aaa5bf403b4647b8a162f2b4e6b508ec/`
(`stdout.log`, `workspace/Import Demo.boltproject`, and
`imported-texture-thumbnail.png`),
`bin/test-results/explorer-drop/5f2d83d74ac147a3adb2290eb1f60019/`
(`stdout.log` and `workspace/Drop Demo.boltproject`), and
`bin/test-results/untitled-session/e8055ef725fc4f7d8be35574ed6abcdf/`
(`stdout.log` and isolated `workspace/`). Probes recreate a fresh `<run-id>`
folder on every run.

- [x] PNG/JPG/JPEG/TGA are registered as loadable `texture` kinds by
  `AssetTypeRegistry` and appear in the browser filter, Add menu, and New…
  submenu (`tests/repro/AssetBrowserRepro.hx`, 126 checks passed).
- [x] `ProjectSession.importAssets()` validates every path before copying,
  rejects unsupported extensions and escaping folders, de-duplicates names,
  copies into the project, appends `AssetRecord(type:"texture")`, and saves the
  manifest. Repeat imports and rejected imports leave the manifest consistent
  (`tests/repro/AssetBrowserRepro.hx`).
- [x] Add → Import Asset reaches the native picker call site with an
  image-only filter (PNG/JPG/JPEG/TGA, no All Files option) and **multi-select**:
  one command imports a two-file JPG texture set. The probe copies a PNG, a
  JPG named like the reported `Metal049C_2K` maps, and a two-map batch
  directly into `Content/`, persists four texture records, and refreshes the browser
  (`tests/native/Test-ImportFiles.ps1`, `stdout.log` and manifest in the
  evidence folder). `tools/native/multifile.c` is a project-local native
  extension built into `bin/multifile.hdll` and staged in the release; no
  locked toolchain file was changed.
- [x] Untitled sessions are interactive: the scratch `Content` folder is
  visible, Add → Folder writes a folder, Add → Import Asset copies and decodes
  a texture, and no `.boltproject` is created
  (`tests/native/Test-UntitledSession.ps1`, headless coverage in
  `tests/repro/AssetBrowserRepro.hx`).
- [x] Texture cards use real decoded thumbnails. `TextureCache` reads headers
  headlessly (`tests/repro/TextureCacheRepro.hx`), decodes via `hxd.res.Image`,
  caps uploads to 256 px and installs a `realloc` callback for DX12 device
  resets (device-reset restoration itself remains covered by the existing
  `-DeviceReset` probe for the renderer). The native probe asserts the
  tile-upload log line and records a `PrintWindow` capture at
  `imported-texture-thumbnail.png`.
- [x] Multi-file Explorer drops land in the folder under the cursor, import
  both files, and register both records. Drops are refused during Play mode
  without changing the manifest (`tests/native/Test-ExplorerDrop.ps1`).
  A documented `BOLTSPARK_PROBE_DROP_DIR` hook feeds the production drop
  handler because a cross-process synthetic `WM_DROPFILES` cannot marshal its
  `HGLOBAL` into the editor process.
- [x] External file/folder changes refresh the Asset Browser without manual
  refresh. `AssetWatcher` polls a bounded tree snapshot from `Main.update()`
  (polling chosen over `hl.uv.Fs` because its Windows directory handle blocks
  folder renaming). `tests/native/Test-AssetWatcher.ps1` asserts a top-level
  file and a nested folder/file each produce a `[watcher]` signal and a browser
  re-scan; evidence under `bin/test-results/asset-watcher/`.
- [x] Explorer drops into a *floating* Asset Browser window. `winfloat.c`
  accepts `WM_DROPFILES`, latches UCS-2 paths in GC memory, and Haxe drains them
  after the native pump; the float maps the point to its own folder and reuses
  the import command. Multi-file placement and the Play-mode guard pass in
  `tests/native/Test-FloatExplorerDrop.ps1` (evidence under
  `bin/test-results/float-explorer-drop/`).
- [x] Project material assets with an albedo texture reference, authored in a
  dockable Material Editor panel that can also float as a native HWND.
  Double-clicking a material opens (or focuses) the editor. Albedo maps bind to
  the viewport renderer through `MaterialTextureBindings`; `MeshRenderer` stays
  unchanged. Evidence: `tests/native/Test-MaterialEditor.ps1` and
  `tests/repro/MaterialEditorRepro.hx`.

## Platform and toolchain

- [x] Record Haxe, HashLink, Heaps, `format`, `hldx`, hlfreetype, and FreeType versions (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Record HashLink distribution source and hashes of native modules (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Agility SDK: n/a — not required by the official HashLink 1.16.0 binary (documented, with rationale).
- [x] Record GPU model, driver version (`docs/TOOLCHAIN_VERSIONS.md`). D3D12 feature level recorded from hardware class (12_1); Heaps DX12Driver does not expose a device feature-level query at M0 — direct runtime feature-level read is deferred to a later milestone if needed.
- [x] Confirm `compile.hxml` selects `hldx` + `-D dx12` and does not reference `hlsdl` (enforced by `tools/build.ps1 -Check`).
- [x] Root-cause diagnosis for the initial DX12 startup failure documented with an isolated repro (`tests/repro/DxCArrayRepro.hx` + analysis in `docs/M0_IMPLEMENTATION_REPORT.md`).
- [x] **Second-machine confirmation (user-attested, 2026-11-23):** the project owner reports the editor
  runs successfully on two additional Windows 11 / DX12 PCs. Accepted on firsthand owner report in place
  of in-repo artifacts; no per-machine logs or screenshots were retained for those runs.

## Performance baseline

- [x] Record idle frame time and CPU/GPU usage at 1440x900. The first
  60-second frame window averaged 16.807 ms / 59.498 FPS with vsync enabled;
  idle CPU averaged 4.529% and observed GPU Engine samples averaged 10.130%
  (`docs/PERFORMANCE_BASELINE.md`).
- [x] Record memory after 1 minute and 15 minutes: working set 141.70 →
  142.77 MiB, private bytes 166.66 → 164.37 MiB, handles 484 → 476.
- [x] No unbounded memory growth was observed during the 15-minute run. After
  the first idle minute, fourteen minutes of 1280×800↔1440×900 resizing ended
  with working set +1.08 MiB, private bytes -2.29 MiB, and eight fewer handles
  (`tests/native/Measure-EditorPerformance.ps1`, `docs/PERFORMANCE_BASELINE.md`).

(The baseline is observational rather than a product budget; longer soak,
GPU-memory, and representative-project measurements remain later work.)

The native foundation gate was executed on the primary Windows 11/DX12 machine
beginning 2026-11-11 and revalidated with tracked probes on 2026-11-15.
Second-machine confirmation was added on 2026-11-23 as a user-attested report
covering two additional Windows 11/DX12 PCs. The two remaining external hardware
items stay visibly open but are non-blocking until M9 under
`tests/validation-policy.json`.
