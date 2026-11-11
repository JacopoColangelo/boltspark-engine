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
- [x] Cube visibly rotates without application logic errors (rotation rate editable live from the inspector stepper).
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
- [x] Numeric properties use compact up/down arrows instead of separate +/- buttons; arrow clicks apply the configured step (`bin/numeric-drag-fields.png`, `bin/numeric-spin-arrow-up.png`).
- [x] Horizontal click-drag scrubbing changes bounded spin values in both directions and transform-axis values in 0.1 steps, with each change flowing through editor commands (`bin/numeric-spin-scrub-right.png`, `bin/numeric-spin-scrub-left.png`, `bin/numeric-axis-scrub-right.png`).
- [x] Clicking a numeric value without dragging focuses and selects its text for direct keyboard editing (`bin/numeric-click-edit-focus.png`).
- [x] Focus loss/regain does not leave stuck visual/input state (input adapter reports focus transitions; button color restored on release-outside).
- [x] Native cursor policy is stable: ordinary editor controls use Arrow, text values use IBeam, splitters use SizeWE/SizeNS, and the draggable palette item uses SizeAll; numeric scrub regions use SizeWE while hovered but restore Arrow after leaving or releasing a drag outside (`bin/cursor-regression.txt`, `bin/numeric-cursor-dismiss-regression.txt`, captured with Win32 `GetCursorInfo`).
- [x] Keyboard event reporting flows through the central input adapter (status bar shows `key ... | dN uN mvN focus G/L` live; `boltspark/ui/InputAdapter.hx`).

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
