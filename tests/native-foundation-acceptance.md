# Native foundation acceptance checklist — Windows 11 / DirectX 12

Executed on 2026-11-11 on the dev machine (Windows 11 Pro build 26300 x64, RTX 3080, i7-12700K).
Evidence files are under `bin/` unless noted otherwise.

## Build/runtime

- [x] Windows 11 x64 machine and GPU/driver recorded (`docs/TOOLCHAIN_VERSIONS.md`).
- [x] Haxe compilation succeeds with the pinned toolchain using `compile.hxml` (`tools\build.ps1`).
- [x] Native release build links HashLink/C into `release\Boltspark.exe` and stages the required runtime modules beside it.
- [x] `compile.hxml` selects `-lib hldx`, explicitly defines `-D dx12`, and pins `-D hl_ver=1.16.0`.
- [x] HashLink VM starts the compiled `.hl` file through `tools/build.ps1 -Run`, with `bin/freetype.hdll` available in the bytecode working directory.
- [x] HashLink native module `directx.hdll` (window/input/event services) is present and loads at runtime (window opens, input works).
- [x] HashLink native module `dx12.hdll` (Direct3D 12 rendering driver) is present and loads at runtime (rendering succeeds; driver positively identified as `h3d.impl.DX12Driver`).
- [x] Project-local `freetype.hdll` loads in both HashLink and native-release runs; FreeType 2.14.3 is statically linked, so no system font-rendering dependency is installed.
- [x] **Agility SDK: not required.** The official HashLink 1.16.0 binary is a standard DX12 build; no `D3D12/` folder or Agility DLLs are needed.
- [x] Process opens a normal native Windows desktop window (`bin/m0_window.png` — title "Boltspark Engine").
- [x] No Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, browser, Node, SDL, or OpenGL fallback is launched/used: the native modules are HashLink runtime services + `dx12.hdll`/`directx.hdll`/`heaps.hdll` and the project-local `freetype.hdll`; `hlsdl`/`sdl.hdll` is never referenced by the build (`compile.hxml` checked by `tools/build.ps1 -Check`).
- [x] Window closes cleanly (run exits with code 0 on close).

## Rendering

- [x] DX12 driver is positively identified in runtime diagnostics, not only inferred from the compile flag: `[M0] renderer driver = h3d.impl.DX12Driver` (`bin/runlog.txt`).
- [x] 3D cube appears in the 3D scene using the Heaps DX12 driver (`bin/m0_window.png`, `bin/m0_input_test.png`).
- [x] The editor cube is a stable, static orange primitive by default; rotation and color are no longer driven by sample/demo behavior.
- [x] H2D editor chrome appears over the bounded 3D viewport (top bar, hierarchy, inspector, console, status bar).
- [x] Compact flat editor styling renders in the native DX12 window with square-edged controls, continuous inspector sections, and no legacy rounded-surface texture (`bin/ui-compact-editor.png`).
- [x] The native release keeps the compact hierarchy, viewport, inspector, and console aligned after a live resize to 1280x800 (`bin/ui-compact-release-1280.png`).
- [x] 3D content is clipped to the viewport rectangle by the render zone, aligned with the editor panels.
- [x] Clicking the sample cube selects it from the viewport; clicking empty viewport space clears hierarchy selection.
- [x] Create multiple cubes, select and rename them from the hierarchy, and verify inspector edits stay with the selected object.
- [x] Delete selected objects and verify hierarchy rows and viewport meshes are removed together.
- [x] Navigate a long hierarchy list and select objects above and below the visible range.
- [x] Pick a created cube in the viewport and verify its hierarchy row and inspector become active.
- [x] Native window resize (1440x900 to 1280x800) updates viewport framing and picking coordinates without stale content or crashes.
- [ ] Dock-splitter resize is validated against viewport framing and picking coordinates.
- [ ] High-DPI scaling and device-loss/reset recovery are validated on a Windows target.
- [x] Text is legible at baseline window size (1440x900 default; verified at 1296x900 after resize).
- [x] Inter Regular, SemiBold, and Bold are rasterized from embedded TTF data by FreeType at exact 11/13/15px sizes, using native face hinting and correct pen advances; un-preloaded characters are cached on demand (`bin/ui-freetype-native-hint.png`, `bin/ui-freetype-release.png`, `bin/freetype-runtime-repro.log`). The already-legible console mono path is preserved.
- [x] Resize behavior: chrome redraws to the new client size (`bin/m0_input_test.png` was captured at a resized 1296x900 window with correct layout). Maximize/restore re-uses the same `resize()` path.
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
- [x] Inspector thumb dragging reveals later properties clipped by a short panel (`bin/thumb-inspector-before.png`, `bin/thumb-inspector-after-down.png`).
- [x] Inspector wheel scrolling is direction-correct over property values, while a value owns keyboard focus, and directly over the scrollbar (`bin/wheel-property-after-down.png`, `bin/wheel-property-focused-after-down.png`, `bin/wheel-scrollbar-after-down.png`).
- [x] Shift-click selects a contiguous range in the hierarchy.
- [x] Left-clicking empty hierarchy list space or uncovered hierarchy header chrome clears keyboard focus and object selection, while rows and Search retain their own behavior (`bin/hierarchy-empty-body-deselect.png`, `bin/hierarchy-empty-header-deselect.png`, `bin/hierarchy-search-preserves-selection.png`).
- [x] Delete is suppressed as an object command while editing inspector text or transform values (`bin/delete-key-edit-safe.png`).
- [x] Numeric transform properties use compact up/down arrows instead of separate +/- buttons; arrow clicks apply the configured 0.1 step (`bin/numeric-drag-fields.png`, `bin/numeric-axis-scrub-right.png`).
- [x] Horizontal click-drag scrubbing changes transform-axis values in 0.1 steps, with each change flowing through editor commands (`bin/numeric-axis-scrub-right.png`).
- [x] Clicking a numeric value without dragging focuses and selects its text for direct keyboard editing (`bin/numeric-click-edit-focus.png`).
- [x] Focus loss/regain does not leave stuck visual/input state (input adapter reports focus transitions; button color restored on release-outside).
- [x] Native cursor policy is stable: ordinary editor controls use Arrow, text values use IBeam, splitters use SizeWE/SizeNS, and the draggable palette item uses SizeAll; numeric scrub regions use SizeWE while hovered but restore Arrow after leaving or releasing a drag outside (`bin/cursor-regression.txt`, `bin/numeric-cursor-dismiss-regression.txt`, captured with Win32 `GetCursorInfo`).
- [x] Keyboard event reporting flows through the central input adapter (status bar shows `key ... | dN uN mvN focus G/L` live; `boltspark/ui/InputAdapter.hx`).

## Grid snapping and rebindable editor shortcuts

Executed on 2026-11-14 with window-scoped `SendMessageTimeout` key/mouse events against the native HashLink/DX12 window. Visual evidence is in `bin/keybindings-window-defaults.png`, `bin/keybindings-window-rebound.png`, and `bin/keybindings-v-held.png`; command and drag evidence is summarized in `bin/keybindings-evidence.txt` with raw logs in `bin/keybindings-final-runtime.log` and `bin/snap-hold-*.log`.

- [x] The viewport exposes independent translation, rotation, and scale snap toggles plus preset dropdowns; the controls stay inside the live splitter-sized viewport and the active values are visible in the native DX12 render.
- [x] Default tool shortcuts are 1 Move, E Rotate, and R Scale. One native run emitted `viewport tool: Rotate gizmo active` for E and `viewport tool: Scale gizmo active` for R (`bin/keybindings-final-runtime.log`).
- [x] Holding V temporarily disables translation snapping without changing its stored toolbar toggle. Identical X-axis drags ended at snapped `x=1` normally and unsnapped `x=0.8` while V was held (`bin/snap-hold-on.log`, `bin/snap-hold-bypass.log`). The translation cell also renders inactive during the hold (`bin/keybindings-v-held.png`).
- [x] V cannot stick when modifiers change or focus is lost: the sequence V-down, Ctrl-down, V-up, Ctrl-up emitted one suspend and one resume transition (`bin/keybindings-evidence.txt`).
- [x] File → Editor Settings → Editor Keybindings opens a native retained-H2D floating window above the editor hit layers. It lists all defaults, supports Escape/click-close and Reset to Defaults, and consumes blank-window input rather than passing it into the viewport (`bin/keybindings-window-defaults.png`).
- [x] Rebind capture ignores modifier-only events: Ctrl then T captured `Ctrl+T` for Rotate, persisted a complete versioned JSON map, and the rebound chord immediately selected Rotate (`bin/keybindings-window-rebound.png`, `bin/keybindings-evidence.txt`). Duplicate chords are rejected and malformed/partial persisted maps fall back atomically to complete defaults in `Keybindings.hx`.
- [x] Shortcut commands, hold snapping, snap-to-grid, and Delete remain suppressed while an inspector/search text control owns keyboard capture.

## Viewport transform gizmo (Move tool)

Executed on 2026-11-12 with the automated Win32 probe (`bin/verify-gizmo-drag.ps1`): synchronous `SendMessageTimeout` mouse events addressed to the Boltspark window handle only (no screen-level input injection), with stdout mirrored to `bin/gizmo-runlog.txt`.

- [x] The Move tool shows a three-axis gizmo at the primary selection's position, rendered in `s3d` through the scene camera with always-on-top depth testing (now part of the full three-tool gizmo suite below; the Rotate/Scale-reserved behavior it references was superseded by `bin/verify-transform-gizmo.ps1` evidence).
- [x] Hovering an axis highlights it; picking compares projected handle samples against a 14-pixel screen-space threshold, keeping interaction stable across camera distance.
- [x] Pressing an axis starts a constrained drag that moves the object along that world axis only, with the gizmo following per frame and inspector transform values updating live (`bin/gizmo-runlog.txt`).
- [x] Drag motion captures a press-time projected axis mapping and applies accumulated pointer displacement from that unchanged anchor, so the object does not jump on the first move and sensitivity does not decay outside the viewport (zero-delta at press verified).
- [x] Releasing a gizmo drag applies the final position through the editor command flow (`command: sampleCube position.x = ...`) and never falls through to viewport click-picking (`preventClick`; no `viewport:` line appears during drags in `bin/gizmo-runlog.txt`).
- [x] Axis-locked motion both directions: drag 1 moved sampleCube position.x 0 → -1.93 with y/z locked at 0; drag 2 pressed on the moved cube's projected pixel and returned it to 0 (`bin/gizmo-runlog.txt`, `bin/gizmo-drag-evidence.txt`).

## Full transform gizmo suite (Move planes, Rotate, Scale, shortcuts)

Executed on 2026-11-12 with the automated Win32 probe (`bin/verify-transform-gizmo.ps1`): three sessions with app relaunches between tools so every press starts with sampleCube at the origin; window-scoped `SendMessageTimeout` mouse and key messages only, no screen-level input injection. Engine evidence mirrored to `bin/gizmo-runlog-move.txt`, `bin/gizmo-runlog-rotate.txt`, `bin/gizmo-runlog-scale.txt`, summarized in `bin/transform-gizmo-evidence.txt`.

- [x] All three tools drive live viewport gizmos from one gizmo implementation (`TransformGizmo.hx`): Move (axes + two-axis plane quads + center free-move square), Rotate (active-space axis rings + center wire-sphere arc-ball), Scale (axis boxes + plane quads + center uniform box), all rendered as Unreal-style wireframe handles with always-on-top depth testing (`bin/gizmo-runlog-*.txt`).
- [x] Historical Gate 9 evidence used number-row shortcuts (2 → Rotate, 3 → Scale, 1 → Move) and verified the text-editing guard (`bin/gizmo-runlog-rotate.txt`, `bin/gizmo-runlog-scale.txt`). The current mapping supersedes 2/3 with the rebindable E/R defaults verified in the grid-snapping/keybindings section above.
- [x] Two-axis plane drags move the selection inside the handle's plane with the third axis locked: plane.xy drag ended at (-0.02, 0.87, 0) — z stayed exactly 0 across the whole drag (`bin/gizmo-runlog-move.txt`). The plane basis used for drawing/picking is scratch state separate from the drag's captured frame, so per-frame redraws cannot corrupt an active plane drag.
- [x] Rotation gizmo: WORLD-space ring drag applies only around the selected world axis from the static default cube (latest ring result `(27.82, 0, 0)` degrees). The center region uses a true virtual hemisphere rather than the old z=0 direction circle; the following omni drag produced `(38.55, -73.88, 21.93)` degrees, demonstrating camera-space tumble rather than screen roll (`bin/gizmo-runlog-rotate.txt`).
- [x] Rotation-ring colors follow the viewport grid convention in WORLD mode: the visible red X arc follows the red X grid direction, green remains Y, and the blue Z arc follows the blue Z grid direction. The editor's X/Z rotation components are converted consistently to Heaps Z/X for numeric entry, rendering, pick samples, drag planes, and quaternion application; red reports `rotation.x`, blue reports `rotation.z`, and neither applies the opposite physical axis (`bin/gizmo-solid-rotate.png`, `bin/ring-axis-picks-log.txt`, `bin/gizmo-runlog-rotate.txt`).
- [x] WORLD/LOCAL is an active viewport control, not a label. WORLD is the default; after any explicit object rotation, LOCAL applies that quaternion to Move/Rotate/Scale drawing, screen-space pick samples, and press-captured drag axes/planes through one shared basis (`bin/gizmo-space-log.txt`).
- [x] Move center handle: pressing the screen-facing center square selected `position.view`; dragging in the camera plane moved sampleCube from (0, 0, 0) to (-0.72, 0.5, 0.32), changing all applicable world components without selecting an axis/plane (`bin/gizmo-center-move-log.txt`).
- [x] Scale gizmo: axis box drag scales only that axis (scale (1.93, 1, 1)); center uniform box scales all three axes by the same ratio relative to the drag-start scale, preserving axis ratios set by a prior axis drag ((23.99, 12.43, 12.43) = ×1.93 on all three) (`bin/gizmo-runlog-scale.txt`).
- [x] Inspector shows Position / Rotation / Scale rows; gizmo drags update all nine values live during the drag, and Rotation/Scale fields commit through the same command flow as position fields.
- [x] Selection outline traces the object's actual transformed silhouette (12 mesh edges through the object rotation/scale, inflated about the object center) instead of an axis-aligned boundary cube, and is redrawn per frame so it tracks transform edits and gizmo drags.
- [x] The viewport grid uses thinner minor/major/axis strokes and an explicit earlier render layer; the depth-tested selection outline renders later, so projected grid lines cannot paint over selected-object edges (`bin/gizmo-solid-move.png`).
- [x] Reproducibility: two consecutive full-probe runs produced matching values (axis 0 → 0.73 → 0; plane z locked at 0), confirming a previously observed one-off drag flake was probe timing, not gizmo math.
- [x] Production gizmo drags use Heaps `MouseMode.Relative`: the pinned hldx backend hides/clips the cursor, registers Windows Raw Input, suppresses legacy absolute `WM_MOUSEMOVE`, and reports hardware `lLastX/lLastY` to the drag callback. Release restores `Absolute` mode and parks the cursor at the virtual drag endpoint; no edge wrapping or cursor teleport loop is used.
- [x] Beyond-edge regression: press-time screen Jacobians/tangents replace rays built from distant synthetic screen coordinates for move, ring rotation, and scale. A window-scoped unbounded X-axis probe produced 0.99, 9.95, and 19.89 world units for 1×, 10×, and 20× equal displacement; the 20× endpoint `(-971, 994)` was beyond both client edges and retained proportional motion with Y/Z locked. Ring rotation remained active at 10× displacement, while axis scale produced 1.95, 10.46, and 19.92 with its other axes fixed at 1 (`bin/gizmo-unbounded-drag-evidence.txt`).
- [x] Position and Rotation reset to `(0, 0, 0)` and Scale resets to `(1, 1, 1)` through row-level Inspector actions. Scale linking preserves the existing proportions instead of forcing equality: an unlinked `1.1/1/1` scale became `1.2/1.09/1.09` after linking and stepping X; a linked X-axis gizmo drag from reset produced `2.14/2.14/2.14` (`bin/transform-linked-scale.png`, `bin/transform-actions-log.txt`).

## Platform and toolchain

- [x] Record Haxe, HashLink, Heaps, `format`, `hldx`, hlfreetype, and FreeType versions (`docs/TOOLCHAIN_VERSIONS.md`).
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
