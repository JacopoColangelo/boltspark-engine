# M0 implementation report — native foundation (Windows 11 / DirectX 12)

Date: 2026-11-11. Scope: Master Development Plan M0 — a verified native HashLink + Heaps + DirectX 12 application with the initial BoltUI framework.

This report is factual: every claim below links to evidence (files, logs, screenshots) or is explicitly marked open.

## 1. Result summary

**M0 is achieved.** The project builds and runs on the pinned project-local toolchain with the DirectX 12 driver positively identified at runtime, the 3D+2D rendering gates passed, input verified (including automated Win32 click tests), and the first BoltUI modular slice in place with a working editor shell.

## 2. Toolchain (all project-local, nothing on C:)

| Component | Version | Location |
|---|---|---|
| Haxe compiler (pinned) | 5.0.0-preview.1+dcda605 (dev build 2025-10-23) | `toolchain/haxe-dev` |
| HashLink runtime | 1.16.0 official win64 binary | `toolchain/hashlink` |
| Heaps | 2.1.0 | `toolchain/haxelib` |
| hldx bindings | 1.16.0 | `toolchain/haxelib` |
| format | 3.8.0 | `toolchain/haxelib` |
| hlfreetype | 1.0.0 (`56c8aac`) | `third_party/hlfreetype` |
| FreeType | 2.14.3 | project-local source under `third_party/hlfreetype/vendor`, statically linked into `freetype.hdll` |
| Neko | (bundled) | `toolchain/neko` |

The user ratified the dev-compiler pin (2026-11-11) after a rigorous root-cause analysis (section 4). Full hashes: `docs/TOOLCHAIN_VERSIONS.md`.

Environment: user-level env vars point at the project toolchain (`HAXEPATH`, `HAXE_STD_PATH`, `HAXELIB_PATH`, `NEKO_INSTPATH`, user `PATH`). Two **stale machine-level** variables (`HAXEPATH`, `NEKO_INSTPATH` from the old installer, pointing at `C:\HaxeToolkit\...` which no longer exists) remain and require admin rights to remove; they are harmless dead paths, and user-level variables take precedence. Nothing else remains on C:.

## 3. What was implemented

### Application
- `src/Main.hx`: `hxd.App` bootstrap; sets window title/vsync; logs the actual renderer driver class (`h3d.impl.DX12Driver`); builds a static orange sample cube; wires BoltUI object and transform commands to engine objects; maintains camera aspect on resize.
- `AppIcon` decodes the embedded multi-resolution ICO for native hldx HWND branding and retained H2D rendering. Development and native-release windows receive the same icon at runtime, while the release executable embeds the original ICO as a Windows resource.
- Gizmo drags enter hldx-backed `MouseMode.Relative`, consume Windows Raw Input deltas through a hidden/clipped cursor, and park the restored cursor at the virtual drag endpoint on release. Transform solving uses press-time screen Jacobians/tangents rather than off-screen camera rays, keeping move/rotate/scale response linear across arbitrary accumulated motion.
- `WorldBounds` defines a ±8 km cube around the origin and constrains complete transformed geometry through every editor transform path. The old arbitrary ±1000 scale-factor cap is gone; the camera far plane covers the bounded world, boundary crossings clamp and log rather than deleting objects, and meshes enclosing the editor camera render two-sided while it remains inside. Numeric-field fractional stabilization avoids HashLink's 32-bit `Math.round` overflow that previously turned sufficiently large positive values negative.
- Editor camera navigation follows Unreal-style gesture ownership: RMB enables WASD/QE flight and speed controls, idle viewport-wheel input dollies in/out, MMB pans, corrected Alt+LMB input orbits, and the rebindable F command frames the primary selection from its complete world-space bounds while preserving view rotation.
- `compile.hxml`: `-lib heaps -lib format -lib hldx -D dx12 -D hl_ver=1.16.0 -debug -hl bin/boltspark.hl`.

### BoltUI framework slice (`src/boltspark/ui/`)
- Modular restructure: `Theme` (tokens), `UiContext` (shared state), `InputAdapter` (central keyboard/focus/pointer reporting — Gate 3), `EditorShell` (chrome layout + command callbacks), `widgets/` (`UiButton`, `Stepper`, `SwatchPicker`, `ConsolePanel`), with `BoltUI` as facade.
- Editor shell: compact square-edged top bar and toolbar, the embedded Boltspark icon in place of the old procedural mark/text, searchable hierarchy (clickable `sampleCube` item), **transparent 3D viewport** (starter bug fixed: it used to fill the whole window with an opaque background, hiding `s3d`), continuous Object/Transform inspector groups, row resets, ratio-preserving linked Scale, timestamped editor console, and a slim status bar. Resize-aware layout.
- UI edge quality: embedded Inter Regular, SemiBold, and Bold TTF faces are rasterized by FreeType at each exact requested UI size (11/13/15px), with native TrueType hinting, correct pen advances and an on-demand internal glyph atlas. JetBrains Mono Regular now follows the same runtime path at its existing 12px size for console lines and numeric values, preserving the former 17px line height, 13px baseline, 7px digit advance, and fixed-width behavior. Small icons and symbols remain texture-free analytic signed-distance shapes, now rasterized at their exact integer size with pixel-grid-fitted 1/1.5/2px optical weights and derivative anti-aliasing on curves and diagonals.
- Command flow: widgets → shell callbacks → `Main` → engine objects (no direct widget→engine mutation).
- Viewport transform snapping now has independent translation/rotation/scale toggles and preset ramps. V temporarily bypasses translation snapping, Ctrl+End performs an explicit absolute grid snap, and File → Editor Settings → Editor Keybindings opens a separate native top-level hldx/DX12 application window for persisted, conflict-checked shortcuts with defaults 1/E/R for Move/Rotate/Scale and Ctrl+Z/Ctrl+Y for Undo/Redo. Changes synchronize back to the running editor. Both HWNDs use native dark title bars; close/reopen hides and restores the same keybindings host rather than rebuilding its process, device, and font cache. The host HWND is owned by the launching editor and explicitly activated on show, so its first open cannot be placed behind the editor.

### Build tools
- The initial M0 scripts were consolidated into `tools/build.ps1`. It supports environment validation (`-Check`), explicit dependency installation (`-InstallDependencies`), development/release builds (default), and running the development build (`-Run`).
- Native release generation adds a resource script to the generated Visual C++ project so Explorer and the taskbar can read the same multi-size `src/res/boltspark.ico` directly from `Boltspark.exe`.
- The project-local DirectX window patch distinguishes Win32 movement from sizing: `WM_MOVING` leaves DWM to move the existing surface without invoking a blocking DX12/vsync frame, while `WM_SIZING` retains live redraws. The same patch supplies the owner/activation calls needed by cross-process editor windows.
- The environment check verifies the OS, pinned compiler, HashLink 1.16.0, native modules + hashes, Haxelib packages, exact hlfreetype/FreeType pins, and build configuration. The default build compiles `freetype.hdll` project-locally before the bytecode/native targets. The incorrect Agility SDK hard-requirement was removed: the official HashLink 1.16.0 binary is a standard DX12 build, verified by runtime evidence.

### Tests / docs
- `tests/native-foundation-acceptance.md`: executed checklist with results and evidence links.
- `docs/TOOLCHAIN_VERSIONS.md`: filled with the full pin record + hashes + rationale.
- `docs/README.md` (starter): corrected Agility section, prerequisites, install/run instructions.
- `README.md` (new), `docs/ARCHITECTURE.md` (new), `docs/AI_AGENT_GUIDELINES.md` (new), `.gitattributes` (new).
- `tests/repro/DxCArrayRepro.hx`: isolation repro kept as regression documentation.

## 4. Root-cause analysis: the DX12 startup failure (and why the compiler pin exists)

Symptom: with Haxe 4.3.7 + HashLink 1.16.0 + Heaps 2.1.0 + `-D dx12`, the app threw `Primitive or library is missing` at `h3d.impl.DX12Driver.reset` (DX12Driver.hx:480, a `hl.CArray` struct-field write).

Evidence chain:
1. `dx12.hdll` was fine: all 99 `DEFINE_PRIM` names from the binding source are exported (198 total); binding source byte-identical to the 1.16 tag.
2. Isolation repro (`tests/repro/DxCArrayRepro.hx`) failed at `hl.CArray.alloc` — the missing primitive resolves from `libhl.dll` (`?std`).
3. `libhl.dll` PE export table: only `hl_alloc_carray` + `hl_carray_blit` (+ `hlp_` wrappers). No `carray_get`/`carray_length`.
4. HashLink 1.16 and master C source (`src/std/array.c`): only those two primitives exist — Haxe 4.3.7's std `hl/CArray.hx` references primitives **no HashLink release provides**.
5. Haxe 4.3.7 compiler source (`genhl.ml`): zero `ACArray` support. Native `hl_carray` codegen exists only in development builds.
6. Haxe dev compiler + own std runs the exact failing code correctly against the same runtime (repro passes, read-back verified).
7. Dev builds newer than 2025-10-23 fail on the full project: Haxe commit `70820f1` (2025-10-25, "Refactor event loops") removes `EventLoop.progress` used by Heaps 2.1.0 (`hxd/System.hl.hx:157`). Bracketed precisely by testing builds 2025-10-23 (pass) and 2025-10-29 (fail).

Conclusion: Haxe 4.3.x stable is technically incompatible with Heaps 2.1.0's DX12 driver; the pinned dev build 2025-10-23 (`dcda605`) is the newest working compiler for this library set. Documented in `docs/TOOLCHAIN_VERSIONS.md`; ratified by the user.

Also fixed during diagnosis: `h3d.scene.DirLight` was removed from `Main.hx` (classic lights no longer exist in Heaps 2.x; the starter targeted an older Heaps API).

## 5. Verification evidence

| Requirement | Evidence |
|---|---|
| DX12 driver positively identified | `bin/runlog.txt`: `[M0] renderer driver = h3d.impl.DX12Driver` |
| Native window + chrome + cube | `bin/m0_window.png` (1440x900) |
| Application/editor icon branding | `bin/app-icon-editor.png` (live HWND plus in-editor title strip), `bin/app-icon-executable.png` (icon extracted from `release/Boltspark.exe`), and `bin/app-icon-runtime.log` / `bin/app-icon-release.log` (successful DX12 development/release launches) |
| Input (clicks, transform fields/actions, focus, resize) | `bin/m0_input_test.png`, `bin/transform-linked-scale.png`, `bin/transform-actions-log.txt`, `bin/numeric-outside-capture-evidence.txt`, `bin/numeric-unbounded-scrub-evidence.txt`, `bin/negative-scale-evidence.txt` (native clicks, focus, transform arrow edits, outside-window scrubbing, raw-input continuation at desktop edges, signed/mirrored scale through fields and gizmos, linked scale, row resets, and live resize) |
| Compact editor visual refresh | `bin/ui-compact-editor.png`, `bin/ui-compact-palette.png`, `bin/ui-compact-release-1280.png` (native DX12 development/release renders and live resize) |
| Editor text/icon anti-aliasing | `bin/ui-freetype-native-hint.png`, `bin/ui-freetype-release.png`, `bin/console-freetype.png`, `bin/numeric-freetype.png`, `bin/hierarchy-alignment.png`, `bin/ui-icon-grid-hint.png`, and `bin/ui-icon-release.png` (exact-size native-hinted Inter and JetBrains Mono faces; aligned hierarchy rows; full 25-icon sheet; matching pixel-grid-fitted analytic icons in DX12 development/native-release renders); `bin/freetype-runtime-repro.log` proves dynamic glyph caching and preserved JetBrains Mono metrics, while `bin/text-freetype-evidence.txt` records the matching source/resource hash and 75,080 pixel-identical development/release text-region pixels |
| Focused Output Log | `bin/quiet-console.png`, `bin/quiet-console-stdout.txt`, `bin/verbose-console-probe-stdout.txt` (normal launch/tool/selection activity leaves the editor log empty and stdout at the single required renderer line; probe or `BOLTSPARK_VERBOSE_LOGS` mode restores detailed command telemetry without weakening warning/error reporting) |
| Wheel/scrollbar routing regression | `bin/wheel-property-focused-after-down.png`, `bin/wheel-scrollbar-after-down.png`, `bin/wheel-hierarchy-after-down.png`, `bin/wheel-console-after-up.png`, `bin/thumb-inspector-after-down.png`, `bin/thumb-hierarchy-after-up.png` (property-focus routing plus wheel and thumb direction across all scrollable panels) |
| Native cursor state regression | `bin/cursor-regression.txt`, `bin/numeric-cursor-dismiss-regression.txt` (Win32 `GetCursorInfo`: Arrow for ordinary controls, IBeam for text values, SizeWE/SizeNS for splitters, SizeAll only for draggable palette content; numeric scrubbing uses SizeWE only while hovered/dragging and restores Arrow after leaving or an outside release) |
| Unbounded raw gizmo drag | `bin/gizmo-unbounded-drag-evidence.txt` (window-scoped 1×/10×/20× displacement produced move 0.99/9.95/19.89 and axis scale 1.95/10.46/19.92; ring rotation remained active at 10×; final pointer coordinate was beyond two client edges with no slowdown) |
| Transform reset + linked scale | `bin/transform-linked-scale.png`, `bin/transform-actions-log.txt` (linked non-uniform scale changed 1.1/1/1 to 1.2/1.09/1.09; reset restored canonical values; linked X-axis gizmo drag produced 2.14/2.14/2.14) |
| ±8 km transformed world bounds | `bin/world-bounds-stdout.txt`, `bin/world-bounds-scale-1200.png`, `bin/world-bounds-scale-negative-1200.png` (DX12 runtime retained ±1200 uniform scale with the object still present in the hierarchy and visible from the enclosed camera; in centimetre-based world units, a unit cube requested at positions ±900000 was constrained to ±799999.5 by its full geometry; scales ±2000000 were constrained to ±1600000; no delete command or runtime error occurred) |
| Grid-consistent rotation axes | `bin/gizmo-solid-rotate.png`, `bin/ring-axis-picks-log.txt`, `bin/gizmo-runlog-rotate.txt` (editor Rotation X/Z consistently map to Heaps Z/X across fields, rendered rings, picking, and quaternion application; isolated red/blue arcs resolve to rotation.x/rotation.z) |
| Camera-facing rotation arcs | `bin/gizmo-front-facing-rotate.png`, `bin/gizmo-front-pick-visible.txt`, `bin/gizmo-front-pick-hidden.txt` (DX12 fragment clipping hides each torus's rear hemisphere; matching CPU pick filtering selects the visible `+Y` crossing and rejects the clipped opposite crossing) |
| Normalized arc-ball Rotator display | `tests/repro/RotationEulerRepro.hx`, `bin/rotation-euler-repro.log`, `bin/gizmo-arcball-normalized-rotator.txt` (persistent per-object hints choose a stable equivalent Euler branch internally while Details/Inspector values normalize to Unreal's `(-180°, 180°]` presentation; boundary inputs from -725° through +725° pass, and native accumulated rotation wraps from +174.13° to -168.43° without altering quaternion motion) |
| Continuous, unbounded arc-ball response | `tests/repro/ArcballRotationRepro.hx`, `bin/arcball-rotation-repro.log` (the shared production solver verifies the C1 Bell cap/sheet join, bounded coalesced-event subdivision, equal coarse/fine radial results at 1/5/20 trackball radii, and exact out-and-back reversal; linear pointer travel supplies angle after Bell-surface geometry supplies the axis, so the outside sheet cannot damp a long relative-mode drag) |
| Camera-relative arc-ball direction | `tests/repro/ArcballRotationRepro.hx`, `bin/arcball-rotation-repro.log`, `bin/arcball-direction-runtime.txt` (camera-facing Bell vectors accumulate through `previous x current` before direct projection onto the camera right/up/toward-scene basis; center, quadrant, diagonal, angled-camera, and outside-rim roll cases pass, and a native off-center `rotation.omni` drag completed at `(9.1, -5.48, -22.03)` with empty stderr) |
| Grid/selection separation | `bin/gizmo-solid-move.png`, `bin/selection-outline-scale-7000.png` (thinner grid strokes render on layer -10; the depth-tested selection outline renders later on layer 10 and remains unobscured; exact transformed edges retain a two-pixel screen-space width at extreme non-uniform scale, with camera-plane clipping preventing oversized line polygons) |
| Compact hierarchy creation workflow | `bin/ui-no-delete-button.png`, `bin/context-viewport-no-menu.png`, `bin/context-hierarchy-compact.png`, `bin/compact-add-hierarchy-button.png`, `bin/compact-toolbar-row-click-fixed.png`, `bin/compact-add-drag-created.png`, `bin/delete-key-object-removed.png` (hierarchy-only context menu, dense item row, click/drag creation, keyboard deletion) |
| Add-object palette outside dismissal | `bin/palette-dismiss-open.png`, `bin/palette-dismiss-viewport.png`, `bin/palette-dismiss-inspector-selected-open.png`, `bin/palette-dismiss-inspector-selected.png`, `bin/palette-dismiss-console.png`, `bin/palette-dismiss-hierarchy.png` (an open hierarchy context palette closes on left-clicked empty viewport, visible inspector content, console, and hierarchy space) |
| Hierarchy background focus/selection | `bin/hierarchy-empty-body-deselect.png`, `bin/hierarchy-empty-header-deselect.png`, `bin/hierarchy-search-preserves-selection.png` (empty hierarchy chrome blurs and deselects; actual controls preserve selection) |
| Numeric property interaction | `bin/numeric-drag-fields.png`, `bin/numeric-axis-scrub-right.png`, `bin/numeric-click-edit-focus.png`, `bin/transform-linked-scale.png` (compact up/down arrows, transform scrubbing, click-to-edit, and ratio-preserving scale linkage) |
| Grid snapping + keybindings | `bin/keybindings-native-window.png`, `bin/keybindings-native-window-rebound.png`, `bin/main-dark-titlebar.png`, `bin/native-window-evidence.txt`, `bin/keybindings-v-held.png`, `bin/keybindings-evidence.txt`, `bin/snap-hold-on.log`, `bin/snap-hold-bypass.log`, `bin/gizmo-arcball-freeform-snap-on.txt`, `bin/gizmo-ring-snap-still-on.txt` (dark native title bars, separate HWND in development and release, same-PID/HWND cached reopen, live Ctrl+T synchronization/command routing, persistence, modifier-safe V release, snapped `x=1` versus held-V unsnapped `x=0.8`, and freeform omni rotation versus a still-snapped 30° axis-ring result) |
| Viewport camera navigation | `tests/repro/EditorCameraControllerRepro.hx` and `tests/native/Test-NativeSmoke.ps1` (production controller verifies RMB-only flight, immediate release stop, hover-wheel dolly direction, RMB-wheel speed gating, corrected Alt+LMB orbit signs, and aspect-aware selection framing; development and packaged DX12 editors both launch and close cleanly) |
| Smooth move + first-open window order | `bin/window-behavior-evidence.txt` from tracked `tests/native/historical/verify-move-loop.ps1` and `tests/native/historical/verify-first-keybindings-open.ps1` (move-loop timers skip interactive DX12 redraw while resize timers retain it; the first keybindings HWND reports the editor HWND as `GW_OWNER`) |
| Environment check | `tools/build.ps1 -Check` exit 0 |
| Build | `tools/build.ps1` creates the development build and `release\Boltspark.exe` |
| Clean shutdown | run exit code 0 on window close |

## 6. Deviations from the plan

1. **Compiler pin deviation (user-ratified):** the plan specified "Haxe 4.3.x". Proven impossible for DX12 with Heaps 2.1.0 (section 4); pinned to the dev build instead, with the constraint documented in the toolchain lock and enforced by `tools/build.ps1 -Check`.
2. **Agility SDK:** the starter's docs/scripts required it; the official HashLink 1.16.0 binary does not. Requirement removed (was wrong), documented with rationale.
3. **D3D12 feature level:** recorded from hardware class (12_1) rather than a runtime query; Heaps' DX12Driver exposes no feature-level query at M0. Open item if a later milestone needs it.
4. `-D hl_ver=1.16.0` added to `compile.hxml` (required by the DX12 driver's `hl.CArray` version guard).

## 7. Known issues / open items

- **Performance baseline captured 2026-11-15:** 15-minute idle/resize run found
  no unbounded process memory/handle growth; exact frame, CPU, GPU, and memory
  observations are in `docs/PERFORMANCE_BASELINE.md`.
- The input adapter's historical `u4` key-up observation is now explicit:
  backend-independent input state tracks physical downs and reports unmatched
  releases as `orphanUp`, including releases after focus-loss clears held keys.
  It remains diagnostic and does not trigger editor commands.
- Second-machine confirmation is unavailable and explicitly deferred until M9
  by `tests/validation-policy.json`; it remains open rather than passed.
- Stale machine-level env vars on C: (dead paths) need admin to remove.
- A cosmetic artifact: cube bottom edge shows slight z-fighting speckle at some angles (unlit cube, default renderer). Harmless at M0; will be revisited with the renderer work.

## 8. Files created or changed (M0)

- Changed: `compile.hxml`, `src/Main.hx`, `src/boltspark/ui/BoltUI.hx`, `docs/README.md`, `tests/native-foundation-acceptance.md`, all four `tools/*.ps1`.
- Created: `README.md`, `docs/ARCHITECTURE.md`, `docs/M0_IMPLEMENTATION_REPORT.md`, `docs/AI_AGENT_GUIDELINES.md`, `docs/TOOLCHAIN_VERSIONS.md` (filled), `tests/repro/DxCArrayRepro.hx`, `.gitattributes`, evidence files under `bin/`.
- Removed: `CheckDefines.hx` (diagnostic leftover), `toolchain/haxe-nightly` (superseded by the ratified pin — 5.0 nightly could not compile the project).
- Untouched: `docs/DEVELOPMENT_PLAN.md`, `docs/FOUNDATION_ARCHITECTURE.md`, `docs/IMPLEMENTATION_SEQUENCE.md`.

## 9. Next steps (M1 entry points)

This historical M0 queue has advanced substantially. Gate 4 foundations and
Gate 5 viewport embedding are implemented, while project/scene integration is
now the next product-facing boundary. Current priorities are:

1. Integrate the renderer-independent editor session with the versioned
   project/scene contracts for project open/save and scene loading. Concrete
   create/delete/rename/transform edits now use command history and expose
   Undo/Redo.
2. Follow project/scene loading with asset registry/import metadata.
3. Continue incremental BoltUI widget migration onto stable IDs, generic layout,
   and pooled draw commands.
4. Keep genuine driver-triggered DXGI device removal, physical mixed-DPI, and
   second-machine confirmation open but non-blocking under the tracked
   `ignoreExternalHardwareValidation` policy until M9 release hardening; the
   explicit Heaps context-loss/recreation path remains covered automatically.

## 10. Post-M0 foundation update — 2026-11-15

- `tools/test.ps1` is the tracked regression entry point. Its portable mode
  compiles the complete project and runs GPU-independent tests on hosted Windows
  CI; native mode adds HashLink/CArray, FreeType, and optional HWND/DX12 probes.
- Native smoke, resize/maximize/restore, dock-splitter + picking, current-monitor
  DPI awareness, command-history Undo/Redo, and forced DX12 context recreation
  now have tracked probes in `tests/native/`. Machine-specific outputs remain
  under `bin/test-results/`.
- BoltUI now has explicit frame boundaries, scoped stable IDs, persistent state,
  an input snapshot with unmatched-key-up diagnostics, row/column/stack layout,
  contract diagnostics, and pooled draw commands used by editor chrome.
- Viewport render-zone and input coordinate conversion moved into
  `editor/EditorViewport.hx`, providing one mapping for rendering, picking, and
  gizmos after panel or backbuffer resizing.
- Initial M3 data foundations now include versioned project/scene schemas,
  durable IDs, safe relative paths, unknown-field preservation, reference and
  cycle validation, atomic saves with backup, fixtures, and command history.
  A pure editor session now integrates concrete create/delete/rename/transform
  commands with Undo/Redo. User-facing project open/save is not yet claimed.
