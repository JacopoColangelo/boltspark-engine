# Asset Browser — implementation report

## Scope decision: adapt to the engine, not to Unity/Unreal

The first implementation phase inspected the existing architecture. Scenes
(`.boltscene`) are scanned by `ProjectSession` and registered in the project
manifest as `scene` assets. Mesh and material "assets" referenced by
`MeshRenderer` come from the **built-in primitive catalog** (`PrimitiveMeshes`,
default material) and are never loaded from arbitrary files. External textures
are now a second real on-disk kind: PNG/JPG/JPEG/TGA files imported through the
Asset Browser or dropped from Windows Explorer are copied into the project,
registered as `texture` assets, and decoded into real thumbnails through Heaps.

The browser therefore:

- treats `.boltscene` and imported images as loadable asset kinds;
- still lists every other non-internal file as a **generic file** with a
  type-specific icon, so the pane mirrors the real filesystem without
  pretending the engine can import it;
- hides internal documents (`.boltproject`, `*.bak`, `*.tmp`, dot files) because
  they are engine storage, not user assets;
- keeps mesh/material resources in the built-in catalog rather than inventing
  an external mesh importer.

This matches the requirement to build on existing capabilities rather than
recreating Unreal/Unity asset infrastructure.

## Completed features

### Layout and visuals
- Charcoal/graphite dark theme using the existing `Theme` tokens, square
  surfaces, one-pixel borders, restrained teal accent, and no gradients or
  heavy rounding.
- Two panes: a full project asset hierarchy (left) and the Asset Panel (center).
  The left pane mirrors Unreal's Content Browser: folders **and the assets
  inside them** are shown as one collapsible tree. Direct child folders are
  also first-class items in the main panel, alongside assets. There is
  deliberately no per-asset inspector panel; metadata is in the detail list.
- Responsive toolbar: back / forward / parent, breadcrumb, live search, separate
  icon-only **Filter** and **Sort** dropdowns (each with its own short menu, so
  neither becomes a catch-all as options grow; either button lights up when its
  choice differs from the default), a Settings popover that holds
  both the grid / compact-list / detail-list view switcher and the shared
  `UiSlider` (thin rail, teal fill, tiny rectangular handle, value in an inset
  field), and the original Add menu. The inert Refresh button was removed;
  Ctrl+R and the context-menu Refresh entry remain. Favorites moved to a
  compact star in the folder header. Without an inspector the grid uses the
  full remaining width.
- Right-clicking empty space or a folder opens a compact context menu whose
  first item is a **New…** submenu (Folder first, then Scene). This keeps the
  menu short so more creation actions can be added later. Paste, Select All,
  Refresh, folder actions, and the `+` button remain available.
  Any left-click outside an open menu dismisses it, while clicking a row still
  runs that row's action.
- Wheel scrolling works over tiles, empty space, and the scrollbar. hldx reports
  a physical wheel-down as a positive delta after `hxd.Window` negation, so the
  handler adds it to the scroll position; the native probe verifies direction.
- Hovering a card or row for about half a second shows a tooltip with the item's
  name and project-relative path (folders show their folder path). Hover uses a
  lighter surface; a single click switches to the same teal selection highlight
  used by the Scene Hierarchy. A plain click never shows the floating drag label
  — it only appears once the pointer moves past the drag threshold.
- The hierarchy pane has a draggable splitter, and its width persists alongside
  the view preferences. Child folders and assets use a fixed chevron gutter and
  a depth-based indent so nested items are always visibly deeper than parents.
  The tree scrolls independently with its own thin scrollbar.

### Folder navigation
- Expand/collapse with chevrons in the hierarchy and single-click folder rows
  in the tree; double-click a folder in the Asset Panel to enter it.
  Selected-folder highlighting, right-click menu (new scene, new subfolder,
  rename, delete, move-to, copy path, reveal, favorite), drag-and-drop target,
  and automatic refresh from `scanFolders()` are all preserved. Folders are
  draggable onto folders in either pane to nest/reparent them, with a live
  drop-target highlight and cycle prevention. `Add → Folder` creates at the
  Content root; nested folders are an explicit right-click choice.

### Browsing
- Grid with large, size-adaptive thumbnails using Tabler's `outline/photo`
  scene glyph for loadable assets and a neutral document preview for generic
  files, compact list, and
  detail list (Name / Type / Size / Modified), adaptive columns, lazy on-demand
  metadata for size and date, single / Ctrl / Shift multi-selection, hover
  feedback, a small ACTIVE dot, and a favorite marker. The old per-tile type
  caption and the persistent status sentence were removed as clutter; transient
  errors still appear briefly at the bottom of the pane.

### Search / sort / filter
- Search matches name, file name, relative path, folder, extension, kind and
  type label, updating on every keystroke.
- Filter menu: all files, scenes, engine assets, generic files, favorites, recent.
- Sort menu: name / type / size / modified, ascending or descending. It is a
  separate button and menu so future filter or sort options grow independently.

### Engine assets
- Primitives and built-in materials are engine-provided assets, not files.
  `EngineAssetCatalog` synthesizes AssetFileInfo records with a reserved
  `engine://` source scheme so the browser can list, search, sort, favorite, and
  filter them exactly like filesystem assets. They live in a virtual **Engine**
  folder at the Content root and never appear at the root itself; the folder is
  only materialized when engine assets are enabled. They are exposed in the
  **Engine Asset** filter (which shows only them) and, when the **Show Engine
  Assets** checkbox is enabled in the Settings popover, alongside "All assets" /
  favorites / recent. The preference persists in `asset-browser.json`. The
  Engine folder is browsable but cannot be renamed, moved, or deleted.
- Engine assets cannot be renamed, duplicated, moved, or deleted on disk: those
  commands are guarded and instead show a status hint.
- Each asset preview is an offline-baked, mipmapped bundle under
  `res/thumbnails/bundles/` (not generated at runtime). The bake renders the
  mesh at 1024x1024 with FXAA and a tent resolve pass, then stores a complete
  premultiplied-linear mip pyramid as PNG-compressed levels. `ThumbnailLoader`
  uploads the levels into one trilinearly filtered texture and
  `PrimitiveThumbnails` reuses that tile in grid tiles, compact/detail rows,
  the folder tree, and the framed Inspector slot, so the size slider stays
  crisp at every step. Primitives are framed tightly with soft top-right
  studio lighting on a transparent background; White Material and Orange Material each have their own
  zoomed-in sphere preview through the same path.
- Dragging an engine asset out of the browser starts a typed drag session. Mesh
  assets only drop onto the Mesh slot of a MeshRenderer Inspector and material
  assets only onto its Material slot. The picker is a framed slot: a compatible
  drop highlights it, applies the asset through the normal Inspector change
  path, and refreshes both the picker label and the dropdown selection.

### Operations
- Open, rename, duplicate, copy, cut, paste, delete (single confirm for a whole
  multi-selection), reveal in Explorer, and copy asset path.
- Create / rename / delete (empty or recursive) / move folders with manifest
  path repointing, last-scene protection, and unique-name conflict resolution.
- Drag assets onto folders to **move immediately** (no confirmation menu); hold
  **Ctrl** while dropping to copy instead. Multiple selected assets move
  together. Folder rows use the same direct-drop gesture to reparent. Moves
  resolve name conflicts with a unique suffix instead of failing. Folder
  deletion has an up-front validation: when a folder holds the project's last
  remaining scene, the command is rejected with an explicit dialog and log
  message instead of silently failing after confirmation.
- All destructive commands require confirmation and never silently overwrite.

### Navigation, favorites, and persistence
- History stack with back / forward / parent and clickable breadcrumbs. Folder
  rows, breadcrumbs, and keyboard navigation all go through one state path, so
  history is always recorded and the breadcrumb text is rebuilt on every move.
- Favorites and a bounded recent list, plus view preferences, persist to
  `%LOCALAPPDATA%\Boltspark Engine\asset-browser.json`.

### Keyboard
- Ctrl+F search, Ctrl+A select all, Ctrl+R refresh, Backspace parent,
  Enter open, Alt+Left/Right history, Escape clear selection, and the existing
  Ctrl+C/Ctrl+X/Ctrl+V/Ctrl+D/F2 commands. Delete targets the selected assets,
  or the selected folder when no asset is selected. All are guarded so text
  fields keep their own shortcuts, and none were added to the rebindable
  keybindings registry (they are contextual to the browser tab).

## Files created

| File | Purpose |
|---|---|
| `src/boltspark/project/AssetTypeRegistry.hx` | Central registry of recognized extensions and internal-file exclusions. |
| `src/boltspark/ui/widgets/AssetBrowserStore.hx` | JSON persistence for favorites, recent, folder width, and view preferences. |
| `src/boltspark/ui/widgets/UiSlider.hx` | Reusable editor slider: thin rail, accent fill, small rectangular handle, inset value field. |
| `tests/repro/AssetBrowserRepro.hx` | Headless assertions covering registry, discovery, metadata, generic file/folder operations, root-level folder creation, asset-root resolution, and store persistence. |

## Files modified

| File | Change |
|---|---|
| `src/boltspark/ui/widgets/AssetBrowser.hx` | Rewritten as a two-pane browser with direct drag/drop; preserves the core geometry and probe strings used by the native interaction test. |
| `src/boltspark/ui/widgets/MenuDropdown.hx` | Full-window dismiss catch so any outside left-click closes a context menu. |
| `src/boltspark/project/ProjectSession.hx` | `scanAllAssets`, `assetDetails`, generic rename/copy/move/delete/duplicate, folder delete/move, path helpers; kept all existing scene APIs. |
| `src/boltspark/ui/EditorShell.hx` | Forwards new callbacks, routes contextual shortcuts, updates the browser each frame, and extends Escape. |
| `src/boltspark/ui/InputAdapter.hx` | Raw key-down notification for contextual shortcuts (no hardcoded action keys added). |
| `src/boltspark/ui/BoltUI.hx` | Facade forwarding for the new callbacks. |
| `src/Main.hx` | Wires commands to `ProjectSession`, adds one-shot confirm for batch delete, prompts project creation for shell actions with no project, and launches Explorer detached with native path separators. |
| `src/boltspark/ui/widgets/SearchField.hx` | Exposed `focusInput()` for Ctrl+F. |
| `tools/tests/test.ps1` | Registers `AssetBrowserRepro` in portable and native test lists. |
| `tests/native/Test-AssetBrowser.ps1` | Waits for the real startup-completion log marker instead of a fixed delay, removing a race where the probe read stdout before the command-line project finished loading. |
| `tests/native/Test-RevealRoot.ps1` | Regression probe for Reveal in Explorer on the empty-path root folder with no project loaded. |
| `docs/TESTING.md`, `tests/native-foundation-acceptance.md` | Test/evidence documentation. |

## Architectural decisions

- **Data/UI separation.** `ProjectSession` owns all discovery and filesystem
  work; the browser owns only view state and issues callbacks. No widget writes
  to disk.
- **One registry.** Extension knowledge lives in `AssetTypeRegistry` and is
  shared by scanning and display, so recognition can never drift.
- **Lazy metadata.** `scanAllAssets` stores only path/kind; size and modified
  date are fetched by `assetDetails` when the inspector or sort needs them and
  cached per refresh.
- **No new render pipeline.** Thumbnails are Tabler alpha-mask PNGs tinted
  through `UiIcons`: the exact-size 6-16px atlas for small controls and a 64px
  `outline/photo` mask for scene preview tiles. The engine has no image assets
  to decode, and no model or audio previews exist to reuse.
- **Probe stability.** Existing tile/folder geometry, Add menu layout, context
  menu row order, and `[probe]` lines were retained so the tracked native test
  still drives the real UI unchanged.
- **Generic payload for drag/drop.** The browser carries an array of source
  paths during a drag rather than coupling to a specific consumer; the
  existing folder-drop workflow is preserved.

## Dependencies added

None. Texture import uses the already-pinned Heaps `hxd.res.Image` decoder and
`h3d.mat.Texture`, the tracked `format` library, project-local `ProjectSession`,
BoltUI widgets, and the native Win32/HashLink shell APIs already in use. No new
third-party library, web technology, or backend define was introduced.

## Build and testing results

All commands were run with the pinned project-local toolchain on Windows 11 Pro
build 26300 x64:

- `haxe compile.hxml` — success (also via `tools/build.ps1 -Build`, including
  the packaged `release\Boltspark.exe` native release).
- `tools/tests/test.ps1 -Portable` — pass; includes `[asset-browser-repro] all 112
  checks passed`.
- `tools/tests/test.ps1 -AssetBrowser` — pass; original native probe (Add/Rename/Open,
  folder create + F2, clipboard, drag-drop, scroll, collapse/expand) still
  passes with the appended Import menu row.
- `tools/tests/test.ps1 -Build -NativeSmoke -PlayMode -ProjectFiles -AssetBrowser
  -ImportFiles -ExplorerDrop` — pass; all requested native and release checks
  succeeded. Image-header coverage is `[texture-cache-repro] all 5 checks passed`.
- Visual verification: DX12 `PrintWindow` capture at
  `bin/test-results/asset-browser-visual/asset-browser.png`; the redesigned
  view (plus open filter and size-slider popovers) is captured as
  `asset-browser-redesign.png`, `asset-browser-filter-menu.png`, and
  `asset-browser-settings.png` in the same folder.

## External texture import and Explorer drag-in

The Add menu (and the empty-space New… submenu) gained **Import Asset...**. It
opens a **multi-select** native picker (`tools/native/multifile.c`, built as
`bin/multifile.hdll`) with a single **image-only filter** covering all
registered extensions (PNG, JPG, JPEG, TGA) — no All Files option and no
PNG-only single-file filter that used to hide real-world JPG texture sets. Choose
several maps in one dialog; every selected path is forwarded to
`ProjectSession.importAssets()`. The main window also registers an
`hxd.Window` drag-and-drop target, so Explorer
files land through the same write path; the drop point is mapped to a browser
folder with `AssetBrowser.folderAtWindowPoint()` and falls back to the
`Content` root (no extra `Textures` subfolder). Both paths are editor-only
mutations and are refused while Play mode is running.

`importAssets()` validates every path before copying anything, rejects
unsupported extensions and paths that escape the project root, sanitizes and
de-duplicates destination names, copies with `sys.io.File.copy`, appends an
`AssetRecord(type:"texture")` with `{ format }` import settings, saves the
manifest atomically, and fires `stateChanged()`. External paths are never
persisted. Non-image Explorer drops are ignored with a probe line rather than
failing the whole drop.

Grid cards and list icons for texture assets use **real decoded thumbnails**.
`src/boltspark/engine/TextureCache.hx` decodes PNG/JPG/TGA with
`hxd.res.Image`, downsamples to at most 256 px on the CPU before upload, caches
by absolute path, keeps a `realloc` callback for DX12 device resets, and is
cleared when the project changes. Scene and generic-file previews remain
vector glyph stand-ins.

## Untitled sessions are usable

Without a saved `.boltproject`, the Asset Browser scans a scratch **Content/**
folder under the working directory instead of returning an empty list. Add →
Folder, Import Asset, New Scene, rename/move/copy/delete, and Explorer drops all
work in this mode; asset records and the scene graph live in memory and scene
documents are written into the scratch folder. Manifest writes are skipped
until Save Project As, and the scratch folder itself cannot be deleted while it
holds the active scene. Reveal in Explorer and Copy Path still prompt for a
project because they need a real filesystem root to expose. Scratch content is
not migrated when a project is later created — it is a testing sandbox, not a
project stub.

## Mesh import

OBJ, glTF/GLB, and FBX files are imported through **Add → Import Mesh…** or
Explorer drops. `ProjectSession.importMeshAssets()` copies them into the project
and registers `type:"mesh"` asset records. `ImportedMeshLibrary` parses each file
into renderer-independent geometry; `ImportedMeshBinding` registers the result
with `PrimitiveMeshes` and `HeapsMeshFactory`, so imported meshes appear in the
mesh picker and can be dragged onto mesh slots or the viewport like built-ins.
Mesh ids are deterministic hashes of the project-relative source, so scene
references survive save/load. Rename/move/copy/delete keep the manifest record
in sync with the file.

## External-change watcher

`AssetWatcher` re-snapshots the asset root from `Main.update()` and refreshes
the browser when a path appears, disappears, or changes size/mtime. The walk is
capped at 4096 paths / 24 levels and skips build/VCS/dependency folders; the
root follows project/untitled switches and external changes appear within
roughly 0.35 s without a manual refresh. It deliberately uses polling rather
than `hl.uv.Fs`: on Windows that primitive's persistent directory handle blocks
renaming or deleting watched folders, which the folder-reparent native probe
reproduced as a `SysError`.

## Explorer drops on floating browsers

`winfloat.c` calls `DragAcceptFiles` for each floating panel and handles
`WM_DROPFILES` in its own `WndProc`. Paths are copied from the shell `HDROP`
into GC-owned UCS-2 buffers and latched on the panel; `takeDrops()` drains the
latch from `FloatWindowManager.update()` after the native pump has unwound, so
the VM is never re-entered from a window-procedure stack. The float resolves the
drop point with its own `AssetBrowser.folderAtWindowPoint()`, then the existing
import command performs validation, copy, manifest write, and refresh. Drops are
refused in Play mode just like main-window drops. A probe hook feeds the same
native latch via numbered instruction files because a cross-process synthetic
`WM_DROPFILES` cannot marshal its `HGLOBAL`.

## Remaining limitations

- **Cross-panel drop is limited to engine assets.** The path-array payload used
  by filesystem assets is still browser-local; only engine assets (primitives
  and materials) carry a typed drag payload that the MeshRenderer Inspector
  slots consume.
- **Textures, materials, and meshes have real importers.** OBJ/glTF/FBX meshes
  are copied into the project, parsed into assignable engine meshes, and can be
  dragged onto mesh slots or the viewport. Audio and other binary files remain
  generic files. Project material assets can be created and edited, and their
  albedo texture is bound to the viewport renderer; `MeshRenderer` still stores
  only a material reference — it has no per-slot texture data.
- **Explorer integration is Windows-shell based.** Reveal launches
  `explorer.exe /select,<native path>`; project paths use forward slashes
  internally, so the handler converts them to Windows separators before the
  call (Explorer silently ignores `/select` for forward-slash paths). Copy Path
  uses the native `hl.UI.setClipboardText` from the bundled `ui.hdll`. Both
  require a Windows desktop session and are no-ops in headless runs. With no
  project loaded they prompt project creation instead of resolving a meaningless
  working directory.
- **Folder tree is height-clipped** rather than independently scrollable; very
  deep trees may hide lower rows until the bottom dock is enlarged.
- **Detail-list metadata** is fetched on first display/sort and cached per
  refresh; extremely large projects will see a short synchronous cost on the
  first size/date sort.
