# Handoff prompt — external asset import + Windows Explorer drag-in

This document is a self-contained task prompt for the next agent working on
`D:\Giochi\BoltSpark Engine`. It records all findings from the current
investigation so the work can continue without re-deriving the map.

---

## 0. Role and mission

Act as a senior Haxe/Heaps/Windows-native engineer working on an existing,
working Windows 11 / DirectX 12 editor. Extend the existing architecture; do
not replace it. Implement the **first real external asset import path** and
**Windows Explorer drag-in to the main editor window** for the Boltspark
engine. Textures come first (PNG/JPG/TGA). This is the prerequisite for the
later PBR/renderer work: without imported textures there are no real material
maps and no real Asset Browser thumbnails.

Work in bounded milestones. Keep the project compiling after each milestone.
Do not write placeholder or fake implementations. Do not claim anything works
without running the tests and recording evidence.

## 1. Non-negotiable repo rules (read `docs/AI_AGENT_GUIDELINES.md` first)

1. **Native only.** Windows target is HashLink + `hldx` + `-D dx12`. Never
   introduce Electron, NW.js, CEF, Chromium, Tauri, Wails, WebView, DOM, HTML,
   CSS, Node, `hlsdl`, SDL, or OpenGL. `-D dx12` must stay in `compile.hxml`.
2. **Never touch the locked toolchain** (`toolchain/`, Haxe, HashLink, Heaps,
   `format`, `hldx`, hlfreetype, FreeType) without an explicit user decision.
   Compiler pin: `5.0.0-preview.1+dcda605`; HashLink 1.16.0; Heaps 2.1.0.
3. **Do not modify `docs/DEVELOPMENT_PLAN.md`.** Propose changes to the user.
4. Toolchain is project-local; nothing installed system-wide or on `C:`.
5. Follow Heaps 2.x APIs. When unsure, read the pinned source under
   `toolchain/haxelib/heaps/2,1,0/` before coding.
6. Widgets issue commands through callbacks; they never mutate engine state
   directly.
7. PowerShell `Set-Content` writes UTF-16 by default — use `-Encoding ascii`
   or UTF-8 for source files.
8. Every "working" claim needs evidence: exit codes, log lines, screenshots,
   or acceptance-checklist entries.
9. Run `.\tools\tests\test.ps1 -Portable` for every source change. Before
   claiming native integration complete, run `-Build -NativeSmoke` plus the
   relevant native probes. Kill lingering `hl.exe` processes before runtime
   tests. Use `PrintWindow` for screenshots (screen-copy grabs the wrong
   monitor on multi-monitor setups).
10. Keep reusable probes under `tests/native/`, generated evidence under
    ignored `bin/test-results/`.
11. Deferred hardware checks in `tests/validation-policy.json` remain open;
    do not mark them passed.

## 2. Current repository state — important context

- Branch `main`. Play/Stop runtime mode (M4's final gap) was just implemented
  but **is not yet committed**. Expect roughly 24 modified/untracked files in
  `git status`, covering both the Play mode work and an earlier second-machine
  evidence update. **Do not revert or overwrite these changes.**
- The Play mode work added: `src/boltspark/runtime/PlayModeSession.hx`,
  `tests/repro/PlayModeRepro.hx`, `tests/native/Test-PlayMode.ps1`, a
  `canEdit()` guard on all editor mutation callbacks in `Main.hx`, rebindable
  F5/F6/F7 actions, keybindings schema v7 (20 actions / 7 categories), and
  `-PlayMode` in `tools/tests/test.ps1`.
- Committing that work is the recommended first action of this task so the
  import work starts from a clean rollback point. Confirm with the user before
  committing if they have not explicitly approved it.
- All portable tests and the native probe set (`-NativeSmoke -PlayMode
  -CommandHistory -ComponentRemoval -WindowLifecycle -FocusSelection
  -KeybindingsList -ProjectFiles -AssetBrowser`) passed after Play mode.

## 3. Scope decided by the user

- **Formats:** textures first — PNG/JPG/TGA. Meshes (OBJ/glTF) are a later
  milestone and must not be attempted here.
- **Explorer support:** native Import dialog **plus** drag files from Windows
  Explorer into the main editor window. Windows shell context-menu/file
  association integration is out of scope.
- **Deferred:** Explorer drops into a *floating* Asset Browser window (requires
  native `winfloat.c` work); PBR material texture slots (next milestone);
  filesystem watcher; OS drag-in of non-image generic file types beyond
  registering them as generic files.

Recommended defaults unless the user overrides:
- Import destination: `Content/Textures/` inside the project.
- Copy files into the project (do not reference external paths).
- Register imported textures as `AssetRecord(type:"texture")` in the manifest.

## 4. Investigation findings — exact code map

### 4.1 Asset type registry
`src/boltspark/project/AssetTypeRegistry.hx` (94 lines)
- `AssetTypeInfo` typedef lines 18–27: `kind`, `label`, `extension`, `loadable`.
- Constants lines 30–36; `SCENE_INFO` 38–43, `ENGINE_INFO` 44–49, `FILE_INFO` 50–55.
- `infoFor(fileName)` lines 57–60 returns `SCENE_INFO` only for `.boltscene`,
  otherwise `FILE_INFO`. `kindFor()` 62–65, `engineInfo()` 67–68,
  `filterKinds()` 70–73 returns `[SCENE, ENGINE, FILE]`.
- `isInternal(fileName)` 75–87 rejects dotfiles and `boltproject`/`bak`/`tmp`.
- `extensionOf()` 89–93 lowercases via `haxe.io.Path.ext`.

Change needed: add `KIND_TEXTURE`, `TEXTURE_INFO` for `png/jpg/jpeg/tga`
(`loadable: true`), extend `infoFor()` and `filterKinds()`.

### 4.2 ProjectSession — the central gap
`src/boltspark/project/ProjectSession.hx` (1129 lines)
- `AssetFileInfo` typedef 6–21; `AssetDetails` 23–40.
- `scanAssets()` 177–192; `scanFolders()` 226–247; `scanAllAssets()` 255–270;
  `collectAllAssets()` 272–298 (calls `AssetTypeRegistry.infoFor()` at 285,
  so new kinds appear automatically).
- `assetDetails()` 301–336; `engineAssetDetails()` 338–364.
- Existing generic operations that can be reused:
  `renameAnyAsset()` 395–413, `deleteAnyAsset()` 415–425,
  `moveAnyAsset()` 427–445, `copyAnyAsset()` 447–462,
  `duplicateAnyAsset()` 465–468, `uniqueAssetPath()` 606–619,
  `sanitizeAssetName()` 621–628, `safeFileName()` 1111–1124.
- `createFolder()` 652–664; folder move/rename rewrite asset paths at
  550–573 and 667–702.
- `moveScene()`/`copyScene()` 704–726 / 728–752; `copyScene()` pushes
  `new AssetRecord(document.id, "scene", destination)` at 747 — use as the
  template for registering imported textures.
- `sceneSources()` 755–763; `renameScene()`/`deleteScene()` 788–846.
- `resolvePath()` 895–898; `saveDocuments()` 928–937;
  `bindSceneAsset()` 944–969 registers **only scenes**.
- `projectRootDir()` 1041–1043; `relativeToProject()` 1067–1078.
- **There is no `importAssets`/`addAsset` method today.** Add
  `importAssets(paths:Array<String>, targetFolder:String):Array<String>`:
  validate extension, reject unsafe paths, compute a unique project-relative
  destination with `uniqueAssetPath()`, copy with `sys.io.File.copy`, push an
  `AssetRecord`, `DocumentStore.saveProject()`, fire `stateChanged()`.

### 4.3 Schema and storage — no changes required
- `ProjectDocument.hx` 3–21: `SCHEMA_VERSION = 1`, `assets:Array<AssetRecord>`.
- `AssetRecord.hx` 3–18: `id`, `type`, `source`, `importSettings:Dynamic`,
  `extraFields:Dynamic`. Arbitrary type strings are already allowed.
- `ProjectCodec.hx` 4–55: known fields include `id/type/source/importSettings`;
  extras preserved.
- `ProjectValidator.hx` 4–26: requires valid unique id, non-empty type,
  normalized relative source, object `importSettings`; `defaultSceneId` must
  resolve to a `scene` asset. A `texture` record passes unchanged.
- `DocumentStore.hx` 25–47: atomic `.tmp` → `.bak` → promote, with restore on
  failure. BOM stripped at 49–62.
- Therefore no migration or schema bump is needed for this milestone.

### 4.4 Asset Browser
`src/boltspark/ui/widgets/AssetBrowser.hx` (3093 lines)
- Query callbacks 58–79 — **no import callback yet**.
- `refresh()` 768–791 → `onQueryAssets()` → `EditorShell` → `BoltUI` →
  `Main.projectSession.scanAllAssets()` (`Main.hx:394`).
- Filters: `matchesFilter()` 1412–1417 (generic `case other` handles a new
  kind); `openFilterMenu()` 1026–1033 needs a new option.
- `drawPreview()` 2004–2052 and `drawAssetIcon()` 2183–2199 currently branch
  on `entry.kind == KIND_ENGINE`; a texture branch is needed.
- `folderAt(x,y)` 1795–1811 maps browser coordinates to a folder — reuse for
  Explorer drop placement.
- Add menu 404–426; `newMenuItems()` 2722–2740; `openEmptyAreaMenu()`
  2742–2772; context menu 2667–2718 — add `Import Asset…` to the Add menu and
  `newMenuItems()`.
- `openSelected()` 2839–2841 refuses `!loadable` files — a texture kind must
  be `loadable: true` to avoid this.
- Internal drags use `dragSources:Array<String>` (210) of project-relative
  paths; engine drags use `AssetDragPayload` (no filesystem payload exists).
- `emptyAreaHit` 254–269 handles wheel/right-click/deselect only — it is not
  an OS drop surface; Explorer drops arrive as window events.

### 4.5 Callback chain
- `EditorShell.hx`: callbacks around 247–277; InputAdapter wiring ~967–1094;
  AssetBrowser query forwarding ~1127–1180.
- `BoltUI.hx`: facade callbacks 70–135; shell forwarding ~142–375.
- `Main.hx`: all `boltUI.on*` assignments 249–440; add `onImportAssets` here.

### 4.6 Explorer drag-in — infrastructure already exists (key finding)
- `toolchain/haxelib/hldx/1,16,0/window.c:481–521` implements `WM_DROPFILES`:
  `DragQueryFileW`, `DragQueryPoint`, `DropStart`/`DropFile`/`DropEnd` events,
  `malloc`'d UCS-2 buffers, `DragFinish()`.
- `window.c:854–856` `winSetDragAcceptFiles()` calls `DragAcceptFiles`.
- `dx/Window.hx:299` setter and `:431` native binding.
- `hxd/Window.hl.hx`: `NativeDroppedFile` 33–37, `dropTargets`/`dropFiles`
  46–47, `addDragAndDropTarget()` 198–207 (first target sets
  `dragAndDropEnabled = true`, which enables `DragAcceptFiles`), removal
  209–219, `DropStart/DropFile/DropEnd` handling 535–555 builds
  `new DropFileEvent(dropFiles, e.mouseX, e.mouseY)` in client coordinates.
- `hxd/DropFileEvent.hx:9–31` `DroppedFile.file` is the full path; `:39–67`
  exposes `files`, `file`, `dropX`, `dropY`.
- **No use of any of these under `src/`.** The smallest main-window solution
  is one `nativeWindow.addDragAndDropTarget(...)` call in `Main.init()` near
  line 198 (or next to `registerViewportDropTargets()` at ~417).
- Floating-window drops are NOT available: `tools/native/winfloat.c` has no
  `WM_DROPFILES`, no `DragAcceptFiles`, its `WF_*` event enum is at 80–100,
  `WndProc` at 117–311, callback signature is `Int->Int->Int->Int->Void`
  (677–702). Adding float drops needs a new native primitive delivering a
  path buffer — defer.

### 4.7 Native file dialogs and probe hooks
`src/Main.hx`
- `withNativeDialogTimeout()` 3085–3095.
- `probeFileChoice()` 3097–3113 reads `BOLTSPARK_PROBE_OPEN_FILE`,
  `BOLTSPARK_PROBE_SAVE_FILE`, or `BOLTSPARK_PROBE_FILE`; `"cancel"` → null;
  logs `[probe] file dialog <kind> title="…" choice=…`.
- `pickOpenFile(title,extension,label)` 3115–3123 uses `hl.UI.loadFile({title,
  filters:[{name:label, exts:[extension]}]})` — returns **one** path.
- `pickSaveFile()` 3125–3135.
- `confirmDiscardChanges()` 3060–3083, `confirmDestructive()` 3360–3371,
  `revealAsset()` uses `explorer.exe /select,<native path>` and
  `hl.UI.setClipboardText()` at 3328.
- `inputProbeMode` at 186; `canEdit()` guard from Play mode must also reject
  drops during Play.

### 4.8 Texture decoding path (verified in pinned Heaps source)
- `hxd/res/Image.hx`: `ImageFormat` includes `Jpg, Png, Gif, Tga, Dds, Raw,
  Hdr` (3–40); `Image extends Resource` 63; `getInfo()` 93;
  `toTexture()` 638–668 (note the DX12 texture-array caveat at 662–666).
- `hxd/res/Resource.hx:10` constructor takes an `hxd.fs.FileEntry`.
- `hxd/fs/BytesFileEntry.hx:5–59` is public and takes `(path, bytes)`.
- Therefore: `new hxd.res.Image(new hxd.fs.BytesFileEntry(path, bytes)).toTexture()`
  is the runtime loading path. Headless tests can only assert `getInfo()`
  (width/height/format) because `toTexture()` needs a live `h3d.Engine`.
- `h3d/mat/Material.hx:33–35` already exposes `texture`, `specularTexture`,
  `normalMap` — useful next milestone, do not implement material slots here.
- `ThumbnailLoader.hx`: `get()` 22–45, `fromResource()` 47–51, `fromFile()`
  53–56, `fromBytes()` 58–88, `decodeMips()` 95–137, `clear()` 143–149,
  `uploadAll()` 151–... , `decodePng()` 158–171.
- `PrimitiveThumbnails.hx`: `draw()` 20–43, `tileFor()` 50–71.

### 4.9 Tests
- `tests/repro/AssetBrowserRepro.hx` (271 lines): `testRegistry()` 35–48,
  `testEngineAssets()` 50–92, `testDiscoveryAndMetadata()` 93–132,
  `testGenericOperations()` 134–160, `testFolderOperations()` 162–223,
  `testStore()` 225–253, `assertTrue()` 255–258, `deleteRecursively()` 260–270.
  Extend this file rather than adding a new repro.
- Registered in `tools/tests/test.ps1`: portable list at 138, full HL list at
  183; native switches around 240–275.
- `tests/native/Test-AssetBrowser.ps1` (508 lines): seeds project JSON
  19–45, P/Invoke helpers 51–110, launches with `BOLTSPARK_PROBE=1` 112–149,
  Add→Scene 175–187, folder ops 262–279, internal drag/drop 345–381,
  Delete 467–487. **Adding an Import row shifts Add-menu row offsets** —
  update those computations.
- `tests/native/Test-RevealRoot.ps1` (123 lines) is the pattern for shell
  integration assertions without opening an OS dialog.
- `tests/native/Test-FloatAssetDrag.ps1` (447 lines) is relevant only if
  floating drops are later added.
- Probe env vars: `BOLTSPARK_PROBE`, `BOLTSPARK_PROBE_LOG`,
  `BOLTSPARK_PROBE_CLOSE_ANSWER`, `BOLTSPARK_PROBE_OPEN_FILE`,
  `BOLTSPARK_PROBE_SAVE_FILE`, `BOLTSPARK_PROBE_FILE`.

### 4.10 Documentation to update
- `docs/ASSET_BROWSER.md` "Remaining limitations" 227–256: remove/replace
  line 233–235 ("No OS drag-in") and 240–243 ("No real image/texture
  thumbnails"). Keep the filesystem-watcher and cross-panel notes accurate.
- `docs/PROJECT_FORMAT.md` 87–112: add a paragraph about non-scene
  `AssetRecord(type:"texture")` entries.
- `tests/native-foundation-acceptance.md`: add an import/Explorer section
  linked to the new probe evidence.
- `README.md` and `docs/TESTING.md` if a new native switch is introduced.

## 5. Implementation plan (in order)

### Milestone A — import core
1. Extend `AssetTypeRegistry.hx` with texture kinds/extensions.
2. Add `ProjectSession.importAssets(paths, targetFolder)`:
   - reject unsupported extensions and unsafe paths,
   - copy with `sys.io.File.copy`,
   - unique destination via `uniqueAssetPath()`,
   - push `new AssetRecord(StableId.create("asset"), "texture", source,
     importSettings)` into `project.assets`,
   - `DocumentStore.saveProject()` and `stateChanged()`.
3. Extend `tests/repro/AssetBrowserRepro.hx`: external temp file → import →
   assert copy, `scanAllAssets()` kind `texture`, and manifest JSON record.
4. Run `.\tools\tests\test.ps1 -Portable`.

### Milestone B — Import command wiring
1. `onImportAssets` callback through `AssetBrowser` → `EditorShell` →
   `BoltUI` → `Main`.
2. `Import Asset…` in Add menu (404–426) and `newMenuItems()` (2722–2740).
3. `Main.importAssets()` reuses `pickOpenFile()` with a texture filter and
   probe substitution; refresh the browser after import.
4. Add `tests/native/Test-ImportFiles.ps1` (new `-ImportFiles` switch in
   `test.ps1`) asserting the probe dialog line, on-disk copy, and manifest
   record. Update `Test-AssetBrowser.ps1` menu offsets.
5. Run `.\tools\build.ps1` then the relevant native probes.

### Milestone C — Explorer drag-in to the main window
1. `nativeWindow.addDragAndDropTarget(...)` in `Main.init()`; route
   `hxd.DropFileEvent.files` into the same `importAssets()` path.
2. Use `event.dropX/dropY` with `boltUI`/shell → `AssetBrowser.folderAt()`
   to choose the target folder; fall back to `Content/Textures/`.
3. Reject drops while `!canEdit()` (Play mode).
4. Native probe: synthesize `WM_DROPFILES` (0x0233) with an `HDROP` built from
   `GlobalAlloc` + `DROPFILES` via P/Invoke; assert multi-file import and
   folder placement. If synthetic messages prove unreliable, add a documented
   probe hook rather than faking success.
5. Verify with `-NativeSmoke -PlayMode -ProjectFiles -AssetBrowser -ImportFiles`.

### Milestone D — real thumbnails and texture cache
1. New `src/boltspark/engine/TextureCache.hx`: load via `BytesFileEntry` +
   `hxd.res.Image.toTexture()`, cache by project-relative source, clear on
   project switch, rely on Heaps `realloc` for device reset.
2. Add a path→tile loader reusing `ThumbnailLoader.decodePng()` for PNG and
   `hxd.res.Image` for JPG/TGA; cap thumbnail resolution to avoid loading
   huge textures for grid cards.
3. Branch in `AssetBrowser.drawPreview()` / `drawAssetIcon()` on texture kind.
4. Headless test asserts `getInfo()` dimensions/format only; native probe
   asserts a rendered thumbnail (PrintWindow evidence).

### Milestone E — next task (do not implement here)
Extend `Material` + `MeshRenderer` component data (v1→v2 migration) with an
albedo texture reference and bind it in `SceneRendererView`. That is the
bridge into PBR.

## 6. Acceptance criteria for this task

- `.\tools\tests\test.ps1 -Portable` passes after every source change.
- `.\tools\build.ps1` succeeds (dev bytecode + native release).
- Native: import dialog command, Explorer multi-file drag-in, on-disk files,
  manifest records, and browser refresh verified with probe stdout and
  `PrintWindow` evidence under `bin/test-results/`.
- `docs/ASSET_BROWSER.md` no longer claims OS drag-in and real image
  thumbnails are unsupported; `docs/PROJECT_FORMAT.md` documents texture
  records; acceptance checklist linked to evidence.
- No toolchain, backend define, or `DEVELOPMENT_PLAN.md` changes.
- All deferred hardware checks remain visibly open.

## 7. Reporting back

End with: files changed, exact verification commands and results, evidence
paths, any decisions you made where this prompt left a choice, and what you
deliberately did not do. Never claim a feature works without the test output.
