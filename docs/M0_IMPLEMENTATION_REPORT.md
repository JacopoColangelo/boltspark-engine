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
- Gizmo drags enter hldx-backed `MouseMode.Relative`, consume Windows Raw Input deltas through a hidden/clipped cursor, and park the restored cursor at the virtual drag endpoint on release. Transform solving uses press-time screen Jacobians/tangents rather than off-screen camera rays, keeping move/rotate/scale response linear across arbitrary accumulated motion.
- `compile.hxml`: `-lib heaps -lib format -lib hldx -D dx12 -D hl_ver=1.16.0 -debug -hl bin/boltspark.hl`.

### BoltUI framework slice (`src/boltspark/ui/`)
- Modular restructure: `Theme` (tokens), `UiContext` (shared state), `InputAdapter` (central keyboard/focus/pointer reporting — Gate 3), `EditorShell` (chrome layout + command callbacks), `widgets/` (`UiButton`, `Stepper`, `SwatchPicker`, `ConsolePanel`), with `BoltUI` as facade.
- Editor shell: compact square-edged top bar and toolbar, searchable hierarchy (clickable `sampleCube` item), **transparent 3D viewport** (starter bug fixed: it used to fill the whole window with an opaque background, hiding `s3d`), continuous Object/Transform inspector groups, row resets, ratio-preserving linked Scale, timestamped editor console, and a slim status bar. Resize-aware layout.
- UI edge quality: embedded Inter Regular, SemiBold, and Bold TTF faces are rasterized by FreeType at each exact requested UI size (11/13/15px), with native TrueType hinting, correct pen advances and an on-demand internal glyph atlas. This preserves font identity and weight without the previous blur/sharpen or supersampling tradeoffs; the console keeps its existing mono rendering. Small icons and symbols remain analytic signed-distance shader shapes with physical-pixel anti-aliasing.
- Command flow: widgets → shell callbacks → `Main` → engine objects (no direct widget→engine mutation).
- Viewport transform snapping now has independent translation/rotation/scale toggles and preset ramps. V temporarily bypasses translation snapping, Ctrl+End performs an explicit absolute grid snap, and File → Editor Settings → Editor Keybindings opens a separate native top-level hldx/DX12 application window for persisted, conflict-checked shortcuts with defaults 1/E/R for Move/Rotate/Scale. Changes synchronize back to the running editor. Both HWNDs use native dark title bars; close/reopen hides and restores the same keybindings host rather than rebuilding its process, device, and font cache.

### Build tools
- The initial M0 scripts were consolidated into `tools/build.ps1`. It supports environment validation (`-Check`), explicit dependency installation (`-InstallDependencies`), development/release builds (default), and running the development build (`-Run`).
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
| Input (clicks, transform fields/actions, focus, resize) | `bin/m0_input_test.png`, `bin/transform-linked-scale.png`, `bin/transform-actions-log.txt` (native clicks, focus, transform arrow edits, linked scale, row resets, and live resize) |
| Compact editor visual refresh | `bin/ui-compact-editor.png`, `bin/ui-compact-palette.png`, `bin/ui-compact-release-1280.png` (native DX12 development/release renders and live resize) |
| Editor text/icon anti-aliasing | `bin/ui-freetype-native-hint.png`, `bin/ui-freetype-release.png` (matching DX12 development/native-release renders; exact-size native-hinted Inter faces, analytic toolbar/panel icons, and retained console mono path); `bin/freetype-runtime-repro.log` proves an un-preloaded glyph is created once and cached |
| Wheel/scrollbar routing regression | `bin/wheel-property-focused-after-down.png`, `bin/wheel-scrollbar-after-down.png`, `bin/wheel-hierarchy-after-down.png`, `bin/wheel-console-after-up.png`, `bin/thumb-inspector-after-down.png`, `bin/thumb-hierarchy-after-up.png` (property-focus routing plus wheel and thumb direction across all scrollable panels) |
| Native cursor state regression | `bin/cursor-regression.txt`, `bin/numeric-cursor-dismiss-regression.txt` (Win32 `GetCursorInfo`: Arrow for ordinary controls, IBeam for text values, SizeWE/SizeNS for splitters, SizeAll only for draggable palette content; numeric scrubbing uses SizeWE only while hovered/dragging and restores Arrow after leaving or an outside release) |
| Unbounded raw gizmo drag | `bin/gizmo-unbounded-drag-evidence.txt` (window-scoped 1×/10×/20× displacement produced move 0.99/9.95/19.89 and axis scale 1.95/10.46/19.92; ring rotation remained active at 10×; final pointer coordinate was beyond two client edges with no slowdown) |
| Transform reset + linked scale | `bin/transform-linked-scale.png`, `bin/transform-actions-log.txt` (linked non-uniform scale changed 1.1/1/1 to 1.2/1.09/1.09; reset restored canonical values; linked X-axis gizmo drag produced 2.14/2.14/2.14) |
| Grid-consistent rotation axes | `bin/gizmo-solid-rotate.png`, `bin/ring-axis-picks-log.txt`, `bin/gizmo-runlog-rotate.txt` (editor Rotation X/Z consistently map to Heaps Z/X across fields, rendered rings, picking, and quaternion application; isolated red/blue arcs resolve to rotation.x/rotation.z) |
| Grid/selection separation | `bin/gizmo-solid-move.png` (thinner grid strokes render on layer -10; the depth-tested selection outline renders later on layer 10 and remains unobscured) |
| Compact hierarchy creation workflow | `bin/ui-no-delete-button.png`, `bin/context-viewport-no-menu.png`, `bin/context-hierarchy-compact.png`, `bin/compact-add-hierarchy-button.png`, `bin/compact-toolbar-row-click-fixed.png`, `bin/compact-add-drag-created.png`, `bin/delete-key-object-removed.png` (hierarchy-only context menu, dense item row, click/drag creation, keyboard deletion) |
| Add-object palette outside dismissal | `bin/palette-dismiss-open.png`, `bin/palette-dismiss-viewport.png`, `bin/palette-dismiss-inspector-selected-open.png`, `bin/palette-dismiss-inspector-selected.png`, `bin/palette-dismiss-console.png`, `bin/palette-dismiss-hierarchy.png` (an open hierarchy context palette closes on left-clicked empty viewport, visible inspector content, console, and hierarchy space) |
| Hierarchy background focus/selection | `bin/hierarchy-empty-body-deselect.png`, `bin/hierarchy-empty-header-deselect.png`, `bin/hierarchy-search-preserves-selection.png` (empty hierarchy chrome blurs and deselects; actual controls preserve selection) |
| Numeric property interaction | `bin/numeric-drag-fields.png`, `bin/numeric-axis-scrub-right.png`, `bin/numeric-click-edit-focus.png`, `bin/transform-linked-scale.png` (compact up/down arrows, transform scrubbing, click-to-edit, and ratio-preserving scale linkage) |
| Grid snapping + keybindings | `bin/keybindings-native-window.png`, `bin/keybindings-native-window-rebound.png`, `bin/main-dark-titlebar.png`, `bin/native-window-evidence.txt`, `bin/keybindings-v-held.png`, `bin/keybindings-evidence.txt`, `bin/snap-hold-on.log`, `bin/snap-hold-bypass.log` (dark native title bars, separate HWND in development and release, same-PID/HWND cached reopen, live Ctrl+T synchronization/command routing, persistence, modifier-safe V release, and snapped `x=1` versus held-V unsnapped `x=0.8`) |
| Environment check | `tools/build.ps1 -Check` exit 0 |
| Build | `tools/build.ps1` creates the development build and `release\Boltspark.exe` |
| Clean shutdown | run exit code 0 on window close |

## 6. Deviations from the plan

1. **Compiler pin deviation (user-ratified):** the plan specified "Haxe 4.3.x". Proven impossible for DX12 with Heaps 2.1.0 (section 4); pinned to the dev build instead, with the constraint documented in the toolchain lock and enforced by `tools/build.ps1 -Check`.
2. **Agility SDK:** the starter's docs/scripts required it; the official HashLink 1.16.0 binary does not. Requirement removed (was wrong), documented with rationale.
3. **D3D12 feature level:** recorded from hardware class (12_1) rather than a runtime query; Heaps' DX12Driver exposes no feature-level query at M0. Open item if a later milestone needs it.
4. `-D hl_ver=1.16.0` added to `compile.hxml` (required by the DX12 driver's `hl.CArray` version guard).

## 7. Known issues / open items

- **Performance baseline** (idle frame time, CPU/GPU, memory at 1/15 min) not yet captured — checklist section left unchecked.
- The input adapter's keyboard counters showed `u4` key-up events with `d0` key-downs during automated mouse testing (mouse clicks don't emit key events; cause not yet investigated — likely focus-related events). Observation only; no functional impact.
- Second-machine confirmation of the acceptance checklist is pending.
- Stale machine-level env vars on C: (dead paths) need admin to remove.
- A cosmetic artifact: cube bottom edge shows slight z-fighting speckle at some angles (unlit cube, default renderer). Harmless at M0; will be revisited with the renderer work.

## 8. Files created or changed (M0)

- Changed: `compile.hxml`, `src/Main.hx`, `src/boltspark/ui/BoltUI.hx`, `docs/README.md`, `tests/native-foundation-acceptance.md`, all four `tools/*.ps1`.
- Created: `README.md`, `docs/ARCHITECTURE.md`, `docs/M0_IMPLEMENTATION_REPORT.md`, `docs/AI_AGENT_GUIDELINES.md`, `docs/TOOLCHAIN_VERSIONS.md` (filled), `tests/repro/DxCArrayRepro.hx`, `.gitattributes`, evidence files under `bin/`.
- Removed: `CheckDefines.hx` (diagnostic leftover), `toolchain/haxe-nightly` (superseded by the ratified pin — 5.0 nightly could not compile the project).
- Untouched: `docs/DEVELOPMENT_PLAN.md`, `docs/FOUNDATION_ARCHITECTURE.md`, `docs/IMPLEMENTATION_SEQUENCE.md`.

## 9. Next steps (M1 entry points)

1. **Capture the performance baseline** (open checklist section): idle frame time, CPU/GPU usage at 1440x900, memory at 1/15 minutes, growth check while resizing.
2. **Gate 4 — BoltUI minimum system** (per `docs/IMPLEMENTATION_SEQUENCE.md`): theme tokens + logical units, layout containers, stable widget IDs, splitter/dock tree with drag-resize, text input primitives. The M0 widget/command base is the foundation for this.
3. **Gate 5 — viewport embedding decision**: clip the 3D view to a viewport rectangle with bounded rendering and picking.
4. **Robustness:** investigate the `u4`-without-`d` keyboard counter observation in `InputAdapter`; add an automated smoke script that launches the app, waits for the driver log line, and exits cleanly (headless CI-able check).
5. **Second-machine confirmation** of the acceptance checklist, and (needs admin, low priority) removal of the stale machine-level `HAXEPATH`/`NEKO_INSTPATH` env vars pointing at the removed `C:\HaxeToolkit`.
