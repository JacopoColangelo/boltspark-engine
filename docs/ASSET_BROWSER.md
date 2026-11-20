# Asset Browser — implementation report

## Scope decision: adapt to the engine, not to Unity/Unreal

The first implementation phase inspected the existing architecture. The engine
has exactly **one loadable on-disk asset format**: `.boltscene`, scanned by
`ProjectSession` and registered in the project manifest as an asset record of
type `scene`. Mesh and material "assets" referenced by `MeshRenderer` come from
the **built-in primitive catalog** (`PrimitiveMeshes`, default material) and are
never loaded from arbitrary files. There is no texture, audio, model, or image
importer, and no asset metadata payload beyond the manifest record, file size,
and timestamps.

The browser therefore:

- treats `.boltscene` as the only loadable asset kind;
- still lists every other non-internal file as a **generic file** with a
  type-specific icon, so the pane mirrors the real filesystem without
  pretending the engine can import it;
- hides internal documents (`.boltproject`, `*.bak`, `*.tmp`, dot files) because
  they are engine storage, not user assets;
- does not add any new importer, resource system, thumbnail pipeline, or
  dependency.

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
  labeled **Filter** and **Sort** buttons (each with its own short menu, so
  neither becomes a catch-all as options grow), a Settings popover that holds
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
- Hover tooltips were removed as noise. A plain click never shows the floating
  drag label — it only appears once the pointer moves past the drag threshold.
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
- Filter menu: all files, scenes, generic files, favorites, recent.
- Sort menu: name / type / size / modified, ascending or descending. It is a
  separate button and menu so future filter or sort options grow independently.

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
| `tools/test.ps1` | Registers `AssetBrowserRepro` in portable and native test lists. |
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

None. Only existing Heaps `h2d`, `hxd.Key`, project-local `ProjectSession`,
BoltUI widgets, and the system shell for Explorer/clipboard integration are
used. No third-party library, web technology, or new asset format was added.

## Build and testing results

All commands were run with the pinned project-local toolchain on Windows 11 Pro
build 26300 x64:

- `haxe compile.hxml` — success (also via `tools/build.ps1 -Build`, including
  the packaged `release\Boltspark.exe` native release).
- `tools/test.ps1 -Portable` — pass; includes `[asset-browser-repro] all 41
  checks passed`.
- `tools/test.ps1 -AssetBrowser` — pass; original native probe (Add/Rename/Open,
  folder create + F2, clipboard, drag-drop, scroll, collapse/expand) still
  passes.
- `tools/test.ps1 -Build -NativeSmoke -CommandHistory -RotationHandoff
  -ProjectFiles -AssetBrowser` — pass; all requested native and release checks
  succeeded.
- Visual verification: DX12 `PrintWindow` capture at
  `bin/test-results/asset-browser-visual/asset-browser.png`; the redesigned
  view (plus open filter and size-slider popovers) is captured as
  `asset-browser-redesign.png`, `asset-browser-filter-menu.png`, and
  `asset-browser-settings.png` in the same folder.

## Remaining limitations

- **No filesystem watcher.** External changes are picked up by manual refresh
  (Ctrl+R, the context-menu Refresh entry, or tab activation). The project had no watcher
  infrastructure to reuse, avoiding a background rescan that could block the
  render loop.
- **No OS drag-in.** Dragging files from Windows Explorer into the dock is not
  wired; the existing editor has no generic file-drop payload for it. Internal
  multi-asset and folder drags are supported.
- **No cross-panel asset drop.** Assets use an internal path-array payload, but
  no other editor panel currently consumes it.
- **No real image/texture thumbnails.** The engine cannot load image files, so
  previews for `.boltscene` and generic files are Tabler icon stand-ins rather
  than rendered content. They scale with the thumbnail-size slider instead of
  staying a fixed 16px atlas icon.
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
