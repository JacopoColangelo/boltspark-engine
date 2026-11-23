import boltspark.editor.EditorAction;
import boltspark.editor.EditorAxisGizmoRenderer;
import boltspark.editor.EditorCameraController;
import boltspark.editor.EditorGridRenderer;
import boltspark.editor.GridSnapping;
import boltspark.editor.EditorViewport;
import boltspark.editor.EditorObject;
import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.editor.Keybindings;
import boltspark.editor.MeshPicking;
import boltspark.editor.MultiInspectorData;
import boltspark.editor.RotationEuler;
import boltspark.editor.ScalePolicy;
import boltspark.editor.SceneObject;
import boltspark.editor.SelectionClick;
import boltspark.editor.SelectionOutlineEdges;
import boltspark.editor.SharedGizmoDelta;
import boltspark.editor.TransformGizmo;
import boltspark.editor.TransformMatrix;
import boltspark.editor.WorldBounds;
import boltspark.engine.ComponentRegistry;
import boltspark.engine.Component;
import boltspark.engine.TextureCache;
import boltspark.engine.MeshRenderer;
import boltspark.engine.Mesh3D;
import boltspark.engine.inspector.AssetType;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.engine.PrimitiveMeshes;
import boltspark.engine.PrimitiveSettings;
import boltspark.diagnostics.RuntimeProbes;
import boltspark.platform.InteractiveResize;
import boltspark.platform.NativeMultiFilePicker;
import boltspark.project.AssetTypeRegistry;
import boltspark.project.AssetWatcher;
import boltspark.project.EngineAssetCatalog;
import boltspark.project.MaterialDocument;
import boltspark.project.ProjectPath;
import boltspark.project.ProjectSession;
import boltspark.project.SceneSerializer;
import boltspark.runtime.PlayModeSession;
import boltspark.engine.Material;
import boltspark.ui.AppIcon;
import boltspark.ui.AssetDragPayload;
import boltspark.ui.AssetDragSession;
import boltspark.ui.AssetDropRect;
import boltspark.ui.AssetDropTarget;
import boltspark.ui.BoltUI;
import boltspark.ui.HierarchyEntry;
import boltspark.ui.Theme;
import boltspark.ui.windows.ApplicationWindowKind;
import boltspark.ui.windows.ApplicationWindowManager;
import boltspark.ui.windows.DockPanelWindowApp;
import boltspark.ui.windows.KeybindingsWindowApp;

/**
 * Windows-first native Boltspark bootstrap.
 *
 * hxd.App owns the Heaps application lifecycle and creates the default 2D and
 * 3D scenes. The HashLink target is launched by the HashLink VM; hldx supplies
 * Heaps' native DirectX backend. This project selects the DirectX 12 driver
 * with `-D dx12`. No browser, WebView, Electron, NW.js, CEF, or SDL backend
 * is part of this Windows-first application target.
 */
class Main extends hxd.App {
    /** Set by main() when a .boltproject path arrives from the command line. */
    static var startupProjectPath:Null<String> = null;

    var boltUI:BoltUI;
    var editorViewport:EditorViewport;
    var nativeWindow:hxd.Window;
    /** Independent editor grid pass; never a node in the world scene. */
    var gridRenderer:EditorGridRenderer;
    /** Independent viewport orientation gizmo overlay. */
    var axisGizmo:EditorAxisGizmoRenderer;
    /** Editor free-fly camera navigation (RMB look, WASDQE, pan, orbit). */
    var cameraController:EditorCameraController;
    var selectionOutline:h3d.scene.Graphics;
    var viewportDropOutline:h3d.scene.Graphics;
    /** Asset drags from the browser can drop onto the 3D viewport. */
    var viewportMeshDropTarget:Null<AssetDropTarget>;
    var viewportMaterialDropTarget:Null<AssetDropTarget>;
    /** 0 = none, 1 = mesh, 2 = material; set by drop-target highlight. */
    var viewportDragKind:Int = 0;
    var viewportHoverObject:Null<SceneObject>;
    var viewportHoverMaterialIndex:Int = 0;
    var viewportDropOutlineDrawn:Bool = false;
    /** Reused inverse world matrix for local-space silhouette classification. */
    final outlineInverse:h3d.Matrix = new h3d.Matrix();
    /** Heaps render views synchronized from the renderer-independent session. */
    final sceneObjects:Array<SceneObject> = [];
    final sceneObjectsById:Map<Int, SceneObject> = [];
    var editorSession:EditorSession;
    /** Owns project/scene documents, paths, and dirty state. */
    var projectSession:ProjectSession;
    /** Watches the asset root for external edits and refreshes the browser. */
    var assetWatcher:AssetWatcher;
    /**
     * Detached Play-mode scene copy. While non-null, component lifecycle runs
     * only here and the editor session is frozen; Stop destroys it so the
     * authored editor state is always restored exactly.
     */
    var playSession:Null<PlayModeSession> = null;
    /** Editor grid preference preserved across a Play/Stop cycle. */
    var playSavedGridVisible:Bool = true;

    inline function isPlaying():Bool return playSession != null;

    /** Session whose objects are currently projected into the Heaps scene. */
    inline function activeSession():EditorSession {
        return playSession == null ? editorSession : playSession.session;
    }

    /** Loading replaces the whole session; its change notifications are not edits. */
    var suppressProjectDirty:Bool = false;
    var gizmo:TransformGizmo;
    /** Root-space proxy lets the gizmo edit nested objects in world space. */
    var gizmoProxy:h3d.scene.Object;
    /** Unreal-style snap manager driving the toolbar, gizmo drags, and inspector commits. */
    var snap:GridSnapping;
    /** Rebindable editor keybindings registry (also persisted to disk). */
    var keybindings:Keybindings;
    /** Owns native top-level editor windows launched outside the main surface. */
    var applicationWindows:ApplicationWindowManager;
    final runtimeProbes:RuntimeProbes = new RuntimeProbes();
    var currentTool:Int = 0;
    var localTransformSpace:Bool = false;
    var scaleProportionsLinked:Bool = false;
    var gizmoDragging:Bool = false;
    var gizmoWorldBounded:Bool = false;
    var gizmoHandle:Int = -1;
    var dragStartScaleX:Float = 1;
    var dragStartScaleY:Float = 1;
    var dragStartScaleZ:Float = 1;
    // Transform captured when a gizmo drag begins. Incremental snapping
    // re-applies quantized deltas to these values, so enabling snapping or
    // starting a drag never jumps the object onto the grid.
    var dragStartPos:h3d.Vector;
    var dragStartQuat:h3d.Quat;
    var dragStartTransform:EditorTransform;
    var dragStartWorldTransform:EditorTransform;
    var dragPreviewTransform:EditorTransform;
    var inspectorEditObjectId:Int = -1;
    var inspectorEditRow:Int = -1;
    var inspectorEditAxis:Int = -1;
    var inspectorEditBefore:Null<EditorTransform>;
    // Multi-selection gesture snapshots: one history entry for every object
    // edited by a single scrub/type gesture (mirrors the single-object path).
    final inspectorEditIds:Array<Int> = [];
    final inspectorEditBefores:Array<EditorTransform> = [];
    /** World + parent-world snapshots for multi-selection Inspector gestures. */
    final inspectorEditWorldBefores:Array<EditorTransform> = [];
    final inspectorEditParentWorldBefores:Array<Null<TransformMatrix>> = [];
    // Primitive-settings gesture snapshots. Numeric fields bracket every edit
    // (scrub, typed commit, arrow step) with onEditBegin/onEditEnd; history is
    // committed at gesture end so a drag never rebuilds the Inspector
    // mid-capture, exactly like the transform path above.
    var settingsEditPropertyId:String = "";
    var settingsEditObjectId:Int = -1;
    var settingsEditBefore:Null<PrimitiveSettings>;
    final settingsEditIds:Array<Int> = [];
    final settingsEditBefores:Array<PrimitiveSettings> = [];
    // Per-object anchors captured when a shared gizmo drag begins.
    final gizmoDragAnchors:Array<GizmoDragAnchor> = [];
    // Gizmo drag pointer tracking. During a drag the window enters
    // relative mouse mode: the OS cursor is hidden and locked while raw
    // hardware deltas drive a virtual pointer, so drags continue
    // indefinitely past screen edges with no cursor wrapping or jumping.
    // On release the mode switches back to Absolute, which unhides the
    // cursor and restores it to the position it had when the drag began.
    var dragLastX:Float = 0;
    var dragLastY:Float = 0;
    var dragVirtualX:Float = 0;
    var dragVirtualY:Float = 0;
    var dragRelative:Bool = false;
    // Viewport camera gesture tracking. Only one gesture owns the pointer at
    // a time; RMB free-look may switch the window into relative mouse mode
    // (shared with gizmo drags — see onRelativeMouseMove).
    var cameraGesture:Int = -1;
    var lookRelative:Bool = false;
    var cameraGestureLastX:Float = 0;
    var cameraGestureLastY:Float = 0;
    // Camera-speed overlay change detection, so steady frames allocate
    // nothing.
    var lastSpeedValue:Float = -1;
    var lastSpeedModifierState:Int = -1;
    // Probe telemetry: at most one camera position line per second.
    var cameraTelemetryTimer:Float = 0;
    // Synthetic-input verification probes drive drags with WM_MOUSEMOVE,
    // which relative mode ignores; probes keep Absolute mode.
    var inputProbeMode:Bool = Sys.getEnv("BOLTSPARK_PROBE") != null;
    // Deterministic Explorer-drop probe hook. A synthetic WM_DROPFILES sent
    // from another process cannot marshal its HGLOBAL into the editor, so the
    // native probe writes a numbered instruction file instead. The hook feeds
    // the exact same handler as hldx's real DropFileEvent.
    var dropProbeDir:String = "";
    var dropProbeNext:Int = 1;
    /** Numbered picker answers let a probe drive several imports in one session. */
    var pickerProbeDir:String = "";
    var pickerProbeNext:Int = 1;
    // Routine interaction telemetry is useful to automated probes and during
    // focused diagnosis, but it should not flood the user's Output Log.
    var verboseLogging:Bool = Sys.getEnv("BOLTSPARK_PROBE") != null
        || Sys.getEnv("BOLTSPARK_VERBOSE_LOGS") != null;

    override function init():Void {
        InteractiveResize.install();
        // Fonts, icons, and vector UI surfaces are compiled into both the HL
        // bytecode and native release executable; no runtime asset folder is
        // required beside Boltspark.exe.
        hxd.Res.initEmbed();
        nativeWindow = hxd.Window.getInstance();
        AppIcon.applyToWindow(nativeWindow);
        nativeWindow.title = "Boltspark Engine";
        nativeWindow.vsync = true;
        #if hldx
        @:privateAccess nativeWindow.window.setDarkMode(true);
        #end
        applicationWindows = new ApplicationWindowManager();
        nativeWindow.onClose = function() {
            if (!confirmDiscardChanges()) return false;
            if (playSession != null) {
                playSession.destroy();
                playSession = null;
            }
            runtimeProbes.shutdown();
            if (assetWatcher != null) assetWatcher.stop();
            if (boltUI != null) boltUI.shutdown();
            if (editorSession != null) editorSession.destroy();
            applicationWindows.shutdown();
            InteractiveResize.uninstall();
            return true;
        };

        // M0 evidence: log which Heaps driver backend is actually running.
        var engine = h3d.Engine.getCurrent();
        engine.backgroundColor = 0xFF000000 | Theme.APP_BG;
        var driverName = Type.getClassName(Type.getClass(engine.driver));
        Sys.println('[M0] renderer driver = ${driverName}');
        runtimeProbes.start(nativeWindow, engine);

        setupViewportScene();
        gizmoProxy = new h3d.scene.Object(s3d);
        gizmoProxy.name = "TransformGizmoProxy";
        gizmo = new TransformGizmo(s3d);
        projectSession = new ProjectSession();
        editorSession = new EditorSession();
        var initialEditorObject = editorSession.addInitialObject("sampleCube",
            null, null, PrimitiveGameObjects.cubeComponents());
        // The starter cube is captured as the first untitled scene so Save
        // Project can persist exactly what the user sees.
        projectSession.captureScene(editorSession);
        synchronizeSceneObjects();

        s3d.camera.pos.set(5.8, 4.2, 6.4);
        s3d.camera.target.set(0, 0, 0);
        // The transform boundary is ±8 km on every axis. Extend the default
        // Heaps far plane so every corner remains renderable from the current
        // near-origin editor camera.
        s3d.camera.zFar = WorldBounds.CAMERA_FAR;
        // Boltspark's scene editing logic is Y-up (ground placement intersects
        // y = 0), while Heaps defaults its camera to Z-up.
        s3d.camera.up.set(0, 1, 0);
        // Editor free-fly navigation adopts the scene setup as its starting
        // framing; every later camera motion flows through the controller.
        cameraController = new EditorCameraController(s3d.camera);

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        // Inter and JetBrains Mono UI fonts are rasterized from their embedded
        // TTF faces by FreeType at the exact requested size and cached on
        // demand. Everything else defaults to pixel-exact sampling; Tabler UI
        // icons use dedicated, pre-rasterized atlas entries at each UI size.
        s2d.defaultSmooth = false;
        snap = new GridSnapping();
        keybindings = new Keybindings();
        boltUI = new BoltUI(s2d, nativeWindow, snap, keybindings);
        // Independent editor render components: the grid owns a dedicated
        // h3d.scene.Scene pass and the gizmo owns a 2D overlay object graph.
        // Neither is ever parented into the world scene.
        gridRenderer = new EditorGridRenderer();
        axisGizmo = new EditorAxisGizmoRenderer(s3d.camera, s2d,
            boltUI.viewportFont(), function() return boltUI.getViewportRect());
        editorViewport = new EditorViewport(nativeWindow, s3d, s2d,
            function() return boltUI.getViewportRect(), gridRenderer, axisGizmo);
        boltUI.onViewportClick = onViewportClick;
        boltUI.onCreatePrimitive = createPrimitive;
        boltUI.onAddEmptyObjectInFront = createEmptyObjectInFront;
        boltUI.onDropPrimitive = createPrimitiveAtViewport;
        boltUI.onCreatePrimitiveInHierarchy = createPrimitiveInHierarchy;
        boltUI.onDeleteObjects = deleteSceneObjects;
        boltUI.onObjectsSelected = selectSceneObjects;
        boltUI.onInspectorNumberChanged = applyInspectorNumberChange;
        boltUI.onInspectorTextChanged = applyInspectorTextChange;
        boltUI.onInspectorAssetChanged = applyInspectorAssetChange;
        boltUI.onQueryNativeInspector = buildNativeInspectorSnapshot;
        boltUI.onInspectorBoolChanged = applyInspectorBoolChange;
        boltUI.onInspectorEditBegin = beginComponentInspectorEdit;
        boltUI.onInspectorEditEnd = endComponentInspectorEdit;
        boltUI.onInspectorReset = resetInspectorProperty;
        boltUI.onInspectorLinkChanged = setInspectorPropertyLinked;
        boltUI.onAddComponent = addSelectedComponent;
        boltUI.onRemoveComponent = removeSelectedComponent;
        boltUI.onToolChanged = setEditorTool;
        boltUI.onTransformSpaceChanged = setTransformSpace;
        boltUI.onViewportHover = onViewportHover;
        boltUI.onViewportPush = onViewportPush;
        boltUI.onViewportDrag = onViewportDrag;
        boltUI.onViewportRelease = onViewportRelease;
        boltUI.onSnapChanged = onSnapChanged;
        boltUI.onSnapToGrid = snapSelectionToGrid;
        boltUI.onUndo = undoEditorCommand;
        boltUI.onRedo = redoEditorCommand;
        boltUI.onPlayPressed = playScene;
        boltUI.onPausePressed = togglePlaybackPause;
        boltUI.onStopPressed = stopScene;
        boltUI.onHierarchyObjectNameChanged = function(id, name) {
            if (!canEdit()) return;
            var trimmed = StringTools.trim(name);
            if (trimmed.length == 0) {
                boltUI.log("hierarchy: object name cannot be empty");
                return;
            }
            editorSession.renameObject(id, trimmed);
        };
        boltUI.onCreateChildObject = createHierarchyObject;
        boltUI.onCreateChildPrimitive = createHierarchyPrimitive;
        boltUI.onCreateEmptyParent = function(ids) {
            if (!canEdit()) return;
            editorSession.createEmptyParent(ids, "GameObject");
        };
        boltUI.onDuplicateObjects = function(ids) {
            if (canEdit()) editorSession.duplicateObjects(ids);
        };
        boltUI.onCopyObjects = function(ids) {
            if (canEdit()) editorSession.copyObjects(ids);
        };
        boltUI.onPasteObjects = function(parentId) {
            if (canEdit()) editorSession.pasteObjects(parentId);
        };
        boltUI.onQueryObjectClipboard = function() return canEdit() && editorSession.hasClipboard();
        boltUI.onUnparentObjects = function(ids) {
            if (!canEdit()) return;
            editorSession.unparentObjects(ids, true);
        };
        boltUI.onToggleObjectVisibility = function(id) {
            if (!canEdit()) return;
            var object = editorSession.findObject(id);
            if (object != null) editorSession.setObjectVisible(id, !object.visible);
        };
        boltUI.onSetObjectEnabled = function(id, value) {
            if (!canEdit()) return;
            if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
                Sys.println('[probe] inspector object enabled=${value}');
            }
            editorSession.setObjectEnabled(id, value);
        };
        boltUI.onSelectSubtree = function(id) {
            if (canEdit()) editorSession.selectSubtree(id);
        };
        boltUI.onCanHierarchyDrop = function(ids, parentId) {
            return canEdit() && editorSession.canReparentObjects(ids, parentId);
        };
        boltUI.onHierarchyDrop = function(ids, parentId, siblingIndex, preserveWorld) {
            if (!canEdit()) return;
            editorSession.reparentObjects(ids, parentId, siblingIndex, preserveWorld);
        };
        boltUI.onOpenApplicationWindow = function(kind) {
            var message = applicationWindows.open(kind);
            if (message.indexOf("could not") >= 0) {
                boltUI.log(message);
            } else {
                logActivity(message);
            }
        };
        boltUI.onPrepareApplicationWindow = function(kind) {
            var error = applicationWindows.prepare(kind);
            if (error != null) boltUI.log(error);
        };
        boltUI.onSnapHoldChanged = function(active:Bool) {
            snap.holdTranslationOff = active;
            logActivity(active
                ? "snapping: translation snapping suspended (key held)"
                : "snapping: translation snapping resumed");
        };
        // Viewport camera navigation and editor-only visibility.
        boltUI.onViewportWheel = onViewportWheel;
        boltUI.onViewportCameraBegin = onViewportCameraBegin;
        boltUI.onViewportCameraMove = onViewportCameraMove;
        boltUI.onViewportCameraEnd = onViewportCameraEnd;
        boltUI.onViewportFocusChanged = function(focused:Bool) {
            cameraController.viewportFocused = focused;
        };
        boltUI.onWindowFocusLost = function() {
            cameraController.onWindowFocusLost();
        };
        boltUI.onToggleGrid = toggleEditorGrid;
        boltUI.onQueryGridVisible = function() return gridRenderer.visible;
        boltUI.onFovChanged = function(value) {
            printActivity('[viewport] fov=${Math.round(value)}°');
        };
        boltUI.onFocusSelection = focusSelection;
        boltUI.onFileNewProject = fileNewProject;
        boltUI.onFileOpenProject = fileOpenProject;
        boltUI.onFileSaveProject = fileSaveProject;
        boltUI.onFileSaveProjectAs = fileSaveProjectAs;
        boltUI.onFileSaveScene = fileSaveScene;
        boltUI.onFileSaveAll = fileSaveAll;
        boltUI.onQueryAssets = function() return projectSession.scanAllAssets();
        boltUI.onQueryEngineAssets = function() return EngineAssetCatalog.all();
        boltUI.onQueryAssetDetails = function(source) return projectSession.assetDetails(source);
        boltUI.onOpenAsset = openAsset;
        boltUI.onSaveMaterial = saveMaterialAsset;
        boltUI.onNewMaterial = createMaterialAsset;
        boltUI.onDeleteMaterial = deleteMaterialAsset;
        boltUI.onNewScene = createAssetScene;
        boltUI.onRenameAsset = renameAsset;
        boltUI.onDeleteAsset = deleteAsset;
        boltUI.onQueryFolders = function() return projectSession.scanFolders();
        boltUI.onRenameFolder = renameAssetFolder;
        boltUI.onNewFolder = createAssetFolder;
        boltUI.onMoveAsset = moveAsset;
        boltUI.onCopyAsset = copyAsset;
        boltUI.onDeleteAssets = deleteAssets;
        boltUI.onDuplicateAsset = duplicateAsset;
        boltUI.onDeleteFolder = deleteAssetFolder;
        boltUI.onMoveFolder = moveAssetFolder;
        boltUI.onRevealAsset = revealAsset;
        boltUI.onCopyAssetPath = copyAssetPath;
        boltUI.onImportAssets = importAssets;
        boltUI.onFloatFilesDropped = handleFloatDroppedPaths;
        boltUI.onQueryTextureTile = function(source) {
            return TextureCache.get(projectSession.absoluteAssetPath(source));
        };
        // The browser is already the active bottom tab on startup, so no tab
        // click will trigger a refresh. Populate it only after every query
        // callback above exists; refreshing earlier silently yields an empty
        // list and hides engine assets even with the preference enabled.
        boltUI.refreshAssetBrowser();
        registerViewportDropTargets();
        // hldx turns WM_DROPFILES into DropFile events once a target exists.
        // The same handler serves the Import dialog and Explorer drags, so
        // native drops get the same validation, copy, and manifest write.
        nativeWindow.addDragAndDropTarget(onFilesDroppedFromShell);
        var probeDir = inputProbeMode ? Sys.getEnv("BOLTSPARK_PROBE_DROP_DIR") : null;
        dropProbeDir = probeDir == null ? "" : probeDir;
        var pickerDir = inputProbeMode ? Sys.getEnv("BOLTSPARK_PROBE_PICKER_DIR") : null;
        pickerProbeDir = pickerDir == null ? "" : pickerDir;
        logActivity('renderer driver: ${driverName}');
        logActivity("editor shell ready — hierarchy, inspector, console live");
        if (keybindings.lastError != "") {
            boltUI.log("keybindings: " + keybindings.lastError);
        }
        editorSession.onChanged = onEditorSessionChanged;
        projectSession.onStateChanged = function() {
            var title = projectSession.title();
            boltUI.setProjectTitle(title);
            printActivity('[project] title=${title}');
        };
        boltUI.setProjectTitle(projectSession.title());
        // Re-scan the browser when files change outside the editor. The root
        // is re-checked every frame so project open/Save As retargets it.
        assetWatcher = new AssetWatcher(function() {
            printActivity('[watcher] external asset change detected');
            boltUI.refreshAssetBrowser();
        });
        assetWatcher.setRoot(projectSession.assetWatchRoot());
        refreshHierarchy();
        suppressProjectDirty = true;
        editorSession.selectObject(initialEditorObject.id);
        suppressProjectDirty = false;

        boltUI.onObjectNameChanged = function(name:String) {
            if (!canEdit()) return;
            // A multi-selection has no single name to rename.
            if (editorSession.selectedObjectIds.length > 1) {
                refreshSelectionInspector();
                return;
            }
            var selected = getSelectedObject();
            if (selected == null) return;
            var trimmedName = StringTools.trim(name);
            if (trimmedName.length == 0) {
                boltUI.log("inspector: object name cannot be empty");
                refreshSelectionInspector();
                return;
            }
            if (editorSession.renameObject(selected.id, trimmedName)) {
                logActivity("command: object name = " + trimmedName);
            }
        };

        // A .boltproject passed on the command line (double-click / file
        // association) replaces the untitled starter scene at startup.
        if (startupProjectPath != null) {
            var path = startupProjectPath;
            startupProjectPath = null;
            try {
                projectSession.openProject(path);
                reloadEditorSession();
                boltUI.log('project: opened ${projectSession.projectPath}');
            } catch (e:Dynamic) {
                boltUI.log('startup project failed: ${Std.string(e)}');
            }
        }
    }

    override function update(dt:Float):Void {
        runtimeProbes.update(dt, h3d.Engine.getCurrent());
        applicationWindows.update();
        if (playSession != null) {
            // Component lifecycle ticks the detached copy only. The editor
            // session is deliberately frozen for the whole Play/Stop cycle.
            playSession.update(dt);
        } else {
            editorSession.update(dt);
        }
        if (keybindings.pollExternalChanges()) {
            logActivity("keybindings: synchronized changes from the settings window");
        }
        if (dropProbeDir != "") pollDropProbe();
        assetWatcher.setRoot(projectSession.assetWatchRoot());
        assetWatcher.update();
        // Camera navigation stays live in Play mode so the running scene can
        // be inspected; it never mutates either scene graph.
        cameraController.keyboardEnabled = !gizmoDragging;
        var viewport = boltUI.getViewportRect();
        cameraController.setViewportSize(viewport.width, viewport.height);
        cameraController.update(dt);
        boltUI.update(dt);
        axisGizmo.update();
        if (playSession == null) updateViewportDropHover();
        updateDragLabel();
        refreshCameraSpeedLabel();
        if (verboseLogging) {
            cameraTelemetryTimer += dt;
            if (cameraTelemetryTimer >= 1.0) {
                cameraTelemetryTimer = 0;
                var cam = s3d.camera;
                printActivity('[camera] pos=(${round2(cam.pos.x)}, '
                    + '${round2(cam.pos.y)}, ${round2(cam.pos.z)})');
            }
        }
        if (playSession == null) {
            gizmo.follow();
            // A very large object can enclose the editor camera. Render that
            // mesh two-sided only while inside it so it remains visibly present
            // rather than looking as though a transform command deleted it.
            for (sceneObject in sceneObjects) {
                var model = editorSession.findObject(sceneObject.id);
                if (model != null) sceneObject.synchronizeComponents(model);
                refreshScaleRendering(sceneObject);
            }
            refreshSelectionOutline();
        } else {
            // Runtime components may move their own Transform between frames.
            // Replay the detached model's local transform into its Heaps view
            // and keep culling correct; editor outline/gizmo stay hidden.
            for (sceneObject in sceneObjects) {
                var model = playSession.findObject(sceneObject.id);
                if (model == null) continue;
                sceneObject.synchronizeComponents(model);
                sceneObject.applyTransform(model.transform.value);
                refreshScaleRendering(sceneObject);
            }
        }
    }

    override function onContextLost():Void {
        super.onContextLost();
        runtimeProbes.contextRestored();
    }

    override function render(engine:h3d.Engine):Void {
        editorViewport.render(engine, Theme.VIEWPORT_BG);
    }

    /** Build a scene ray from viewport-local pointer coordinates. */
    function viewportRay(viewX:Float, viewY:Float):h3d.col.Ray {
        return editorViewport.ray(viewX, viewY);
    }

    /** Engine-space pointer coordinates matching camera.project output. */
    function viewportPointer(viewX:Float, viewY:Float):h3d.Vector {
        return editorViewport.pointer(viewX, viewY);
    }

    static inline function degToRad(degrees:Float):Float {
        return degrees * Math.PI / 180;
    }

    static inline function radToDeg(radians:Float):Float {
        return radians * 180 / Math.PI;
    }

    static function round2(value:Float):Float {
        return Math.round(value * 100) / 100;
    }

    /**
     * Editor Euler degrees read from an engine quaternion. Boltspark's editor
     * rotation convention maps editor X/Z to Heaps Z/X; Y is shared.
     */
    function rotationDegrees(sceneObject:SceneObject):h3d.Vector {
        var reference = sceneObject.rotationHintValid
            ? sceneObject.rotationHint
            : null;
        var result = RotationEuler.degrees(
            sceneObject.mesh.getRotationQuat(), reference);
        // Retain the continuous representation only as an internal branch
        // hint. Match Unreal's Details panel by presenting wrapped Rotator
        // values while leaving the accumulated quaternion untouched.
        sceneObject.rotationHint.load(result);
        sceneObject.rotationHintValid = true;
        return RotationEuler.normalized(result);
    }

    /** Route generic Inspector metadata back into the Transform command path. */
    function applyInspectorNumberChange(componentIndex:Int, propertyId:String,
            axis:Int, value:Float):Void {
        if (!canEdit()) return;
        if (isSelectedTransform(componentIndex)) {
            var row = transformPropertyRow(propertyId);
            if (editorSession.selectedObjectIds.length > 1) {
                if (row >= 0) multiTransformEdit(row, axis, value)
                else boltUI.log('inspector: unsupported numeric property ${propertyId}');
                return;
            }
            switch (propertyId) {
                case "position": applyTransformChange(axis, value);
                case "rotation": applyRotationChange(axis, value);
                case "scale": applyScaleChange(axis, value);
                default:
                    boltUI.log('inspector: unsupported numeric property ${propertyId}');
            }
            if (row >= 0) refreshGizmoFromSelection();
            return;
        }
        if (editorSession.selectedObjectIds.length > 1) {
            for (id in editorSession.selectedObjectIds) {
                var component = multiComponentFor(id, componentIndex);
                if (component != null) {
                    component.setInspectorNumber(propertyId, axis, value);
                }
            }
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null) {
            component.setInspectorNumber(propertyId, axis, value);
        }
        // No synchronous Inspector refresh here: a rebuild would destroy the
        // drag field mid-gesture (Null access on release). The per-frame render
        // sync in update() applies the new geometry, and the field already
        // displays the committed value.
    }

    function applyInspectorTextChange(componentIndex:Int, propertyId:String,
            value:String):Void {
        if (!canEdit()) return;
        if (editorSession.selectedObjectIds.length > 1) {
            var edited = false;
            for (id in editorSession.selectedObjectIds) {
                var component = multiComponentFor(id, componentIndex);
                if (component != null && component.setInspectorText(propertyId, value)) {
                    editorSession.componentEdited(id);
                    edited = true;
                }
            }
            if (edited) refreshSelectionInspector();
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null && component.setInspectorText(propertyId, value)) {
            editorSession.componentEdited(editorSession.selectedObjectId);
        } else {
            boltUI.log('inspector: ${propertyId} is not directly editable');
            refreshSelectionInspector();
        }
    }

    /** Inspector rows for a floating Inspector hosted in its own HWND. */
    function buildNativeInspectorSnapshot():Dynamic {
        var rows:Array<Dynamic> = [];
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        if (selected == null) {
            return {title: "Inspector", rows: rows};
        }
        rows.push({id: "object", kind: "action",
            label: "Object: " + selected.name, depth: 0, selected: true});
        for (index in 0...selected.components.length) {
            var section = selected.components[index].inspectorData(index);
            rows.push({id: "section:" + index, kind: "action",
                label: section.title, depth: 0, selected: false});
            for (property in section.properties) {
                var id = "p:" + index + ":" + property.id;
                var kindText = Std.string(property.kind);
                if (kindText == "number") {
                    for (axis in 0...property.numberValues.length) {
                        var axisName = axis == 0 ? "X" : axis == 1 ? "Y" : "Z";
                        rows.push({
                            id: id + ":" + axis,
                            kind: "number",
                            label: property.label + " " + axisName,
                            value: property.numberValues[axis],
                            min: property.numberMin,
                            max: property.numberMax,
                            step: property.numberStep,
                            depth: 1,
                            selected: false
                        });
                    }
                } else if (kindText == "boolean") {
                    rows.push({
                        id: id, kind: "bool", label: property.label,
                        value: property.boolValue, depth: 1, selected: false
                    });
                } else {
                    var text = property.textValue;
                    if (kindText == "asset") text = property.assetId;
                    rows.push({
                        id: id, kind: "action",
                        label: property.label + ": " + text,
                        depth: 1, selected: false
                    });
                }
            }
        }
        return {title: "Inspector — " + selected.name, rows: rows};
    }

    /** Assign a shared mesh/material asset from a type-aware Inspector picker. */
    function applyInspectorAssetChange(componentIndex:Int, propertyId:String,
            assetId:String):Void {
        if (!canEdit()) return;
        var multi = editorSession.selectedObjectIds.length > 1;
        var ids = multi ? editorSession.selectedObjectIds.copy()
            : [editorSession.selectedObjectId];
        var applied:Array<Int> = [];
        var befores:Array<String> = [];
        var afters:Array<String> = [];
        for (id in ids) {
            var component = multi
                ? multiComponentFor(id, componentIndex)
                : selectedInspectorComponent(componentIndex);
            if (component == null || !Std.isOfType(component, MeshRenderer)) continue;
            var renderer = cast(component, MeshRenderer);
            var before = renderer.inspectorAssetId(propertyId);
            if (!component.setInspectorAsset(propertyId, assetId)) continue;
            applied.push(id);
            befores.push(before);
            afters.push(renderer.inspectorAssetId(propertyId));
        }
        if (applied.length == 0) {
            boltUI.log('inspector: could not assign ${propertyId} asset ${assetId}');
            return;
        }
        if (Sys.getEnv("BOLTSPARK_PROBE") != null) {
            Sys.println('[probe] inspector asset changed ${propertyId}=${assetId}');
        }
        var target = editorSession.findObject(applied[0]);
        var name = target == null ? "object" : target.name;
        var label = 'Assign ${assetId} to ${name} ${propertyId}';
        // Validated changes become one undoable history entry; multi-selections
        // are grouped exactly like transform and primitive-settings edits.
        if (!editorSession.commitMeshAssetAssignments(applied, propertyId,
                befores, afters, label)) {
            for (id in applied) editorSession.componentEdited(id);
        }
        if (multi) refreshSelectionInspector();
    }

    /** Apply a boolean Inspector toggle to the selected component(s). */
    function applyInspectorBoolChange(componentIndex:Int, propertyId:String,
            value:Bool):Void {
        if (!canEdit()) return;
        // Boolean toggles are discrete clicks: history commits immediately and
        // the resulting session notify may safely rebuild the Inspector (no
        // drag capture is active, same as the asset-picker path).
        var object = editorSession.findObject(editorSession.selectedObjectId);
        var renderer = object == null ? null : object.getComponent(MeshRenderer);
        if (renderer != null && renderer.isPrimitiveParameter(propertyId)) {
            if (editorSession.selectedObjectIds.length > 1) {
                var ids:Array<Int> = [];
                var befores:Array<PrimitiveSettings> = [];
                var afters:Array<PrimitiveSettings> = [];
                for (id in editorSession.selectedObjectIds) {
                    var candidate = editorSession.findObject(id);
                    var selected = candidate == null
                        ? null : candidate.getComponent(MeshRenderer);
                    if (selected == null) continue;
                    var before = selected.primitiveSettings.clone();
                    if (!selected.setInspectorBool(propertyId, value)) continue;
                    ids.push(id);
                    befores.push(before);
                    afters.push(selected.primitiveSettings.clone());
                }
                editorSession.commitAppliedPrimitiveSettings(ids, befores,
                    afters, 'Edit ${primitiveParameterLabel(propertyId)} '
                        + 'on ${ids.length} objects');
                return;
            }
            var before = renderer.primitiveSettings.clone();
            if (renderer.setInspectorBool(propertyId, value)) {
                editorSession.commitPrimitiveSettings(object.id, before,
                    renderer.primitiveSettings,
                    'Edit ${object.name} ${renderer.parameterLabel(propertyId)}');
            }
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null) {
            component.setInspectorBool(propertyId, value);
        }
    }

    function beginComponentInspectorEdit(componentIndex:Int,
            propertyId:String, axis:Int):Void {
        if (!isSelectedTransform(componentIndex)) {
            beginPrimitiveSettingsEdit(componentIndex, propertyId);
            return;
        }
        var row = transformPropertyRow(propertyId);
        if (row >= 0) beginInspectorTransformEdit(row, axis);
    }

    function endComponentInspectorEdit(componentIndex:Int,
            propertyId:String, axis:Int):Void {
        if (!isSelectedTransform(componentIndex)) {
            endPrimitiveSettingsEdit(propertyId);
            clearInspectorTransformEdit();
            return;
        }
        var row = transformPropertyRow(propertyId);
        if (row >= 0) endInspectorTransformEdit(row, axis);
    }

    // ------------------------------------------------------------------
    // Primitive-settings edit gestures. begin captures the MeshRenderer
    // settings before a scrub/type/arrow gesture; end commits one history
    // entry if the settings changed. No Inspector rebuild happens in between
    // (the release path stays safe), and the per-frame render sync applies
    // the geometry while the gesture is active.
    // ------------------------------------------------------------------

    function beginPrimitiveSettingsEdit(componentIndex:Int,
            propertyId:String):Void {
        var component = selectedInspectorComponent(componentIndex);
        if (component == null || !Std.isOfType(component, MeshRenderer)) return;
        var renderer = cast(component, MeshRenderer);
        if (!renderer.isPrimitiveParameter(propertyId)) return;
        settingsEditPropertyId = propertyId;
        if (editorSession.selectedObjectIds.length > 1) {
            for (id in editorSession.selectedObjectIds) {
                var object = editorSession.findObject(id);
                var selected = object == null
                    ? null : object.getComponent(MeshRenderer);
                if (selected == null) continue;
                settingsEditIds.push(id);
                settingsEditBefores.push(selected.primitiveSettings.clone());
            }
            return;
        }
        settingsEditObjectId = editorSession.selectedObjectId;
        settingsEditBefore = renderer.primitiveSettings.clone();
    }

    function endPrimitiveSettingsEdit(propertyId:String):Void {
        if (settingsEditPropertyId == "" || propertyId != settingsEditPropertyId) {
            clearPrimitiveSettingsEdit();
            return;
        }
        var editedPropertyId = settingsEditPropertyId;
        if (settingsEditIds.length > 0) {
            var ids:Array<Int> = [];
            var befores:Array<PrimitiveSettings> = [];
            var afters:Array<PrimitiveSettings> = [];
            for (index in 0...settingsEditIds.length) {
                var object = editorSession.findObject(settingsEditIds[index]);
                var renderer = object == null
                    ? null : object.getComponent(MeshRenderer);
                if (renderer == null) continue;
                ids.push(settingsEditIds[index]);
                befores.push(settingsEditBefores[index]);
                afters.push(renderer.primitiveSettings.clone());
            }
            clearPrimitiveSettingsEdit();
            if (ids.length == 0) return;
            var parameter = primitiveParameterLabel(editedPropertyId);
            var label = ids.length == 1
                ? 'Edit ${editorSession.findObject(ids[0]).name} ${parameter}'
                : 'Edit ${parameter} on ${ids.length} objects';
            editorSession.commitAppliedPrimitiveSettings(ids, befores, afters,
                label);
            return;
        }
        var objectId = settingsEditObjectId;
        var before = settingsEditBefore;
        clearPrimitiveSettingsEdit();
        if (objectId < 0 || before == null) return;
        var object = editorSession.findObject(objectId);
        var renderer = object == null ? null : object.getComponent(MeshRenderer);
        if (renderer == null) return;
        editorSession.commitPrimitiveSettings(objectId, before,
            renderer.primitiveSettings,
            'Edit ${object.name} ${renderer.parameterLabel(editedPropertyId)}');
    }

    function clearPrimitiveSettingsEdit():Void {
        settingsEditPropertyId = "";
        settingsEditObjectId = -1;
        settingsEditBefore = null;
        settingsEditIds.resize(0);
        settingsEditBefores.resize(0);
    }

    /** Display label of a primitive parameter, resolved from the selection. */
    function primitiveParameterLabel(propertyId:String):String {
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        var renderer = selected == null
            ? null : selected.getComponent(MeshRenderer);
        return renderer == null ? propertyId : renderer.parameterLabel(propertyId);
    }

    function resetInspectorProperty(componentIndex:Int, propertyId:String):Void {
        if (!canEdit()) return;
        if (isSelectedTransform(componentIndex)) {
            var row = transformPropertyRow(propertyId);
            if (row < 0) return;
            if (editorSession.selectedObjectIds.length > 1) {
                resetTransformRowMulti(row);
            } else {
                resetTransformRow(row);
            }
            return;
        }
        var selectedComponent = selectedInspectorComponent(componentIndex);
        if (selectedComponent != null
                && Std.isOfType(selectedComponent, MeshRenderer)
                && cast(selectedComponent, MeshRenderer)
                    .isPrimitiveParameter(propertyId)) {
            resetPrimitiveSettingsProperty(propertyId);
            return;
        }
        if (editorSession.selectedObjectIds.length > 1) {
            var edited = false;
            for (id in editorSession.selectedObjectIds) {
                var component = multiComponentFor(id, componentIndex);
                if (component != null && component.resetInspectorProperty(propertyId)) {
                    editorSession.componentEdited(id);
                    edited = true;
                }
            }
            if (edited) refreshSelectionInspector();
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null && component.resetInspectorProperty(propertyId)) {
            editorSession.componentEdited(editorSession.selectedObjectId);
        }
    }

    /** Reset one primitive parameter with an undoable history entry. */
    function resetPrimitiveSettingsProperty(propertyId:String):Void {
        var parameter = primitiveParameterLabel(propertyId);
        if (editorSession.selectedObjectIds.length > 1) {
            var ids:Array<Int> = [];
            var befores:Array<PrimitiveSettings> = [];
            var afters:Array<PrimitiveSettings> = [];
            for (id in editorSession.selectedObjectIds) {
                var object = editorSession.findObject(id);
                var renderer = object == null
                    ? null : object.getComponent(MeshRenderer);
                if (renderer == null) continue;
                var before = renderer.primitiveSettings.clone();
                if (!renderer.resetInspectorProperty(propertyId)) continue;
                ids.push(id);
                befores.push(before);
                afters.push(renderer.primitiveSettings.clone());
            }
            editorSession.commitAppliedPrimitiveSettings(ids, befores, afters,
                'Reset ${parameter} on ${ids.length} objects');
            return;
        }
        var object = editorSession.findObject(editorSession.selectedObjectId);
        var renderer = object == null ? null : object.getComponent(MeshRenderer);
        if (renderer == null) return;
        var before = renderer.primitiveSettings.clone();
        if (!renderer.resetInspectorProperty(propertyId)) return;
        editorSession.commitPrimitiveSettings(object.id, before,
            renderer.primitiveSettings,
            'Reset ${object.name} ${parameter}');
    }

    function setInspectorPropertyLinked(componentIndex:Int, propertyId:String,
            linked:Bool):Void {
        if (!canEdit()) return;
        if (isSelectedTransform(componentIndex) && propertyId == "scale") {
            setScaleProportionsLinked(linked);
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null
                && component.setInspectorLinked(propertyId, linked)) {
            editorSession.componentEdited(editorSession.selectedObjectId);
        }
    }

    function addSelectedComponent(typeId:String):Void {
        if (!canEdit()) return;
        if (editorSession.selectedObjectIds.length > 1) {
            boltUI.log("inspector: select a single object to add components");
            return;
        }
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        if (selected == null) return;
        try {
            var component = ComponentRegistry.create(typeId);
            if (editorSession.addComponent(selected.id, component)) {
                logActivity('component: added ${component.displayName} to ${selected.name}');
            }
        } catch (error:Dynamic) {
            boltUI.log('component: could not add ${typeId}: ${Std.string(error)}');
        }
    }

    /** Remove a component through history; the mandatory Transform is protected. */
    function removeSelectedComponent(componentIndex:Int):Void {
        if (!canEdit()) return;
        if (editorSession.selectedObjectIds.length > 1) {
            boltUI.log("inspector: select a single object to remove components");
            return;
        }
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        if (selected == null || componentIndex <= 0
                || componentIndex >= selected.components.length) return;
        var label = selected.components[componentIndex].displayName;
        if (editorSession.removeComponentAt(selected.id, componentIndex)) {
            logActivity('component: removed ${label} from ${selected.name}');
        }
    }

    function isSelectedTransform(componentIndex:Int):Bool {
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        return selected != null && componentIndex >= 0
            && componentIndex < selected.components.length
            && selected.components[componentIndex] == selected.transform;
    }

    function selectedInspectorComponent(componentIndex:Int):Null<Component> {
        var selected = editorSession.findObject(editorSession.selectedObjectId);
        return selected == null || componentIndex < 0
            || componentIndex >= selected.components.length
            ? null : selected.components[componentIndex];
    }

    /**
     * Resolve the component edited through a multi-selection Inspector row.
     * Merged sections keep the primary object's component index; other objects
     * are matched by component type so a different component order still maps
     * to the right instance.
     */
    function multiComponentFor(id:Int, componentIndex:Int):Null<Component> {
        var primary = editorSession.findObject(editorSession.selectedObjectId);
        if (primary == null || componentIndex < 0
                || componentIndex >= primary.components.length) return null;
        var typeId = primary.components[componentIndex].typeId;
        var object = editorSession.findObject(id);
        if (object == null) return null;
        for (component in object.components) {
            if (component.typeId == typeId) return component;
        }
        return null;
    }

    static function transformPropertyRow(propertyId:String):Int {
        return switch (propertyId) {
            case "position": 0;
            case "rotation": 1;
            case "scale": 2;
            default: -1;
        };
    }

    /** Capture one complete Inspector gesture so scrubbing creates one command. */
    function beginInspectorTransformEdit(row:Int, axis:Int):Void {
        var selected = getSelectedObject();
        if (selected == null || gizmoDragging) return;
        inspectorEditRow = row;
        inspectorEditAxis = axis;
        if (editorSession.selectedObjectIds.length > 1) {
            inspectorEditObjectId = -1;
            inspectorEditBefore = null;
            inspectorEditIds.resize(0);
            inspectorEditBefores.resize(0);
            inspectorEditWorldBefores.resize(0);
            inspectorEditParentWorldBefores.resize(0);
            for (id in editorSession.selectedObjectIds) {
                var sceneObject = findSceneObject(id);
                var model = editorSession.findObject(id);
                if (sceneObject == null || model == null) continue;
                inspectorEditIds.push(id);
                inspectorEditBefores.push(sceneObject.captureTransform());
                inspectorEditWorldBefores.push(
                    editorSession.hierarchy.worldTransform(model));
                inspectorEditParentWorldBefores.push(model.parent == null
                    ? null : editorSession.hierarchy.worldMatrix(model.parent));
            }
            return;
        }
        inspectorEditObjectId = selected.id;
        inspectorEditBefore = selected.captureTransform();
    }

    function endInspectorTransformEdit(row:Int, axis:Int):Void {
        if (row != inspectorEditRow || axis != inspectorEditAxis) {
            clearInspectorTransformEdit();
            return;
        }
        if (inspectorEditObjectId < 0 && inspectorEditIds.length > 1) {
            var ids:Array<Int> = [];
            var befores:Array<EditorTransform> = [];
            var afters:Array<EditorTransform> = [];
            for (index in 0...inspectorEditIds.length) {
                var sceneObject = findSceneObject(inspectorEditIds[index]);
                if (sceneObject == null) continue;
                ids.push(sceneObject.id);
                befores.push(inspectorEditBefores[index]);
                afters.push(sceneObject.captureTransform());
            }
            clearInspectorTransformEdit();
            if (ids.length == 0) return;
            var first = findSceneObject(ids[0]);
            var scope = ids.length > 1 ? '${ids.length} objects'
                : (first == null ? "object" : first.name);
            editorSession.commitAppliedTransforms(ids, befores, afters,
                inspectorTransformLabel(scope, row, axis));
            return;
        }
        if (inspectorEditObjectId < 0) {
            clearInspectorTransformEdit();
            return;
        }
        var selected = findSceneObject(inspectorEditObjectId);
        var before = inspectorEditBefore;
        clearInspectorTransformEdit();
        if (selected == null || before == null) return;
        editorSession.commitAppliedTransform(selected.id, before,
            selected.captureTransform(), inspectorTransformLabel(
                selected.name, row, axis));
    }

    function clearInspectorTransformEdit():Void {
        inspectorEditObjectId = -1;
        inspectorEditRow = -1;
        inspectorEditAxis = -1;
        inspectorEditBefore = null;
        inspectorEditIds.resize(0);
        inspectorEditBefores.resize(0);
        inspectorEditWorldBefores.resize(0);
        inspectorEditParentWorldBefores.resize(0);
    }

    function inspectorTransformLabel(name:String, row:Int, axis:Int):String {
        var rows = ["Position", "Rotation", "Scale"];
        return 'Edit ${name} ${rows[row]} ${axisName(axis).toUpperCase()}';
    }

    /** Capture an atomic transform callback that is not inside a UI gesture. */
    function atomicTransformStart(selected:SceneObject):Null<EditorTransform> {
        return inspectorEditObjectId == selected.id
            ? null
            : selected.captureTransform();
    }

    function commitAtomicTransform(selected:SceneObject,
            before:Null<EditorTransform>, description:String):Void {
        if (before == null) return;
        editorSession.commitAppliedTransform(selected.id, before,
            selected.captureTransform(), description);
    }

    // ------------------------------------------------------------------
    // Multi-selection Inspector edits. Each field edit is applied to every
    // selected object; the surrounding gesture (begin/end edit) commits one
    // shared history entry instead of one command per object.
    // ------------------------------------------------------------------

    static function containsObject(objects:Array<SceneObject>, id:Int):Bool {
        for (sceneObject in objects) if (sceneObject.id == id) return true;
        return false;
    }

    function gestureStartTransform(id:Int):Null<EditorTransform> {
        for (index in 0...inspectorEditIds.length) {
            if (inspectorEditIds[index] == id) return inspectorEditBefores[index];
        }
        return null;
    }

    function gestureStartWorld(id:Int):Null<EditorTransform> {
        for (index in 0...inspectorEditIds.length) {
            if (inspectorEditIds[index] == id) return inspectorEditWorldBefores[index];
        }
        return null;
    }

    function gestureStartParentWorld(id:Int):Null<TransformMatrix> {
        for (index in 0...inspectorEditIds.length) {
            if (inspectorEditIds[index] == id) return inspectorEditParentWorldBefores[index];
        }
        return null;
    }

    static function transformRotationDegrees(t:EditorTransform):h3d.Vector {
        var quat = new h3d.Quat();
        quat.set(t.rotationX, t.rotationY, t.rotationZ, t.rotationW);
        var reference = t.rotationHintValid
            ? new h3d.Vector(t.rotationHintX, t.rotationHintY, t.rotationHintZ)
            : null;
        return RotationEuler.normalized(RotationEuler.degrees(quat, reference));
    }

    static function transformAxisValue(t:EditorTransform, row:Int,
            axis:Int):Float {
        return switch (row) {
            case 0: axis == 0 ? t.positionX : axis == 1 ? t.positionY : t.positionZ;
            case 1:
                var euler = transformRotationDegrees(t);
                axis == 0 ? euler.x : axis == 1 ? euler.y : euler.z;
            default: axis == 0 ? t.scaleX : axis == 1 ? t.scaleY : t.scaleZ;
        };
    }

    /** Build a local transform with one authored axis replaced by `value`. */
    function transformWithAxisValue(source:EditorTransform, row:Int, axis:Int,
            value:Float):EditorTransform {
        var result = source.clone();
        switch (row) {
            case 0:
                switch (axis) {
                    case 0: result.positionX = value;
                    case 1: result.positionY = value;
                    default: result.positionZ = value;
                }
            case 1:
                var euler = transformRotationDegrees(source);
                switch (axis) {
                    case 0: euler.x = value;
                    case 1: euler.y = value;
                    default: euler.z = value;
                }
                var quat = new h3d.Quat();
                quat.initRotation(degToRad(euler.z), degToRad(euler.y),
                    degToRad(euler.x));
                result.rotationX = quat.x;
                result.rotationY = quat.y;
                result.rotationZ = quat.z;
                result.rotationW = quat.w;
                result.rotationHintX = euler.x;
                result.rotationHintY = euler.y;
                result.rotationHintZ = euler.z;
                result.rotationHintValid = true;
            default:
                var previous = switch (axis) {
                    case 0: source.scaleX;
                    case 1: source.scaleY;
                    default: source.scaleZ;
                };
                var clamped = clampedScale(value, previous);
                if (scaleProportionsLinked) {
                    var ratio = clamped / ScalePolicy.nonZero(previous, clamped);
                    result.scaleX = clampedScale(result.scaleX * ratio, result.scaleX);
                    result.scaleY = clampedScale(result.scaleY * ratio, result.scaleY);
                    result.scaleZ = clampedScale(result.scaleZ * ratio, result.scaleZ);
                } else {
                    switch (axis) {
                        case 0: result.scaleX = clamped;
                        case 1: result.scaleY = clamped;
                        default: result.scaleZ = clamped;
                    }
                }
        }
        return result;
    }

    /**
     * Multi-selection Inspector sliders use the same world-space delta as the
     * gizmo. Editing a selected parent and child together must not apply the
     * parent's motion twice to the child, so every target world is converted
     * back to local against the parent's previewed world matrix.
     */
    function multiTransformEdit(row:Int, axis:Int, value:Float):Void {
        var objects = selectedSceneObjects();
        if (objects.length == 0) return;
        var primary = getSelectedObject();
        if (primary == null || !containsObject(objects, primary.id)) primary = objects[0];

        var primaryBeforeLocal = gestureStartTransform(primary.id);
        if (primaryBeforeLocal == null) primaryBeforeLocal = primary.captureTransform();
        var primaryBeforeWorld = gestureStartWorld(primary.id);
        if (primaryBeforeWorld == null) {
            var primaryModel = editorSession.findObject(primary.id);
            primaryBeforeWorld = primaryModel == null ? null
                : editorSession.hierarchy.worldTransform(primaryModel);
        }
        if (primaryBeforeWorld == null) return;

        var desiredPrimaryWorld = localTransformSpace
            ? SharedGizmoDelta.worldFromParent(
                transformWithAxisValue(primaryBeforeLocal, row, axis, value),
                gestureStartParentWorld(primary.id), primaryBeforeWorld)
            : transformWithAxisValue(primaryBeforeWorld, row, axis, value);
        var mode = switch (row) {
            case 0: SharedGizmoDelta.MOVE;
            case 1: SharedGizmoDelta.ROTATE;
            default: SharedGizmoDelta.SCALE;
        };

        // Resolve all desired worlds first so a selected parent is projected
        // with its previewed matrix when its children are converted to local.
        var desiredWorldById:Map<Int, EditorTransform> = new Map();
        for (sceneObject in objects) {
            var beforeWorld = gestureStartWorld(sceneObject.id);
            if (beforeWorld == null) {
                var model = editorSession.findObject(sceneObject.id);
                beforeWorld = model == null ? null
                    : editorSession.hierarchy.worldTransform(model);
            }
            if (beforeWorld == null) continue;
            desiredWorldById.set(sceneObject.id, SharedGizmoDelta.apply(
                beforeWorld, primaryBeforeWorld, desiredPrimaryWorld, mode));
        }

        for (sceneObject in objects) {
            var desired = desiredWorldById.get(sceneObject.id);
            if (desired == null) continue;
            var model = editorSession.findObject(sceneObject.id);
            var parentWorld = gestureStartParentWorld(sceneObject.id);
            if (model != null && model.parent != null
                    && desiredWorldById.exists(model.parent.id)) {
                parentWorld = desiredWorldById.get(model.parent.id).toMatrix();
            }
            var beforeLocal = gestureStartTransform(sceneObject.id);
            if (beforeLocal == null) beforeLocal = sceneObject.captureTransform();
            var local = SharedGizmoDelta.localForWorld(
                desired, parentWorld, beforeLocal);
            var previous = sceneObject.captureTransform();
            if (row == 2) {
                var bounded = WorldBounds.fitScale(sceneObject.mesh,
                    local.scaleX, local.scaleY, local.scaleZ,
                    function(x, y, z) applySceneObjectScale(sceneObject, x, y, z));
                local.scaleX = bounded.x;
                local.scaleY = bounded.y;
                local.scaleZ = bounded.z;
            }
            sceneObject.applyTransform(local);
            if (!containSceneObject(sceneObject)) {
                sceneObject.applyTransform(previous);
                continue;
            }
            refreshScaleRendering(sceneObject);
        }
        refreshGizmoFromSelection();
        pushSelectionInspectorTransform();
    }

    function resetTransformRowMulti(row:Int):Void {
        var objects = selectedSceneObjects();
        if (objects.length == 0) return;
        var ids:Array<Int> = [];
        var befores:Array<EditorTransform> = [];
        var afters:Array<EditorTransform> = [];
        var rowName = row == 0 ? "position" : row == 1 ? "rotation" : "scale";
        for (sceneObject in objects) {
            var before = sceneObject.captureTransform();
            var desired = before.clone();
            switch (row) {
                case 0:
                    desired.positionX = 0;
                    desired.positionY = 0;
                    desired.positionZ = 0;
                case 1:
                    desired.rotationX = 0;
                    desired.rotationY = 0;
                    desired.rotationZ = 0;
                    desired.rotationW = 1;
                    desired.rotationHintX = 0;
                    desired.rotationHintY = 0;
                    desired.rotationHintZ = 0;
                    desired.rotationHintValid = true;
                default:
                    desired.scaleX = 1;
                    desired.scaleY = 1;
                    desired.scaleZ = 1;
            }
            sceneObject.applyTransform(desired);
            if (!containSceneObject(sceneObject)) sceneObject.applyTransform(before);
            if (row == 2) refreshScaleRendering(sceneObject);
            ids.push(sceneObject.id);
            befores.push(before);
            afters.push(sceneObject.captureTransform());
        }
        pushSelectionInspectorTransform();
        var scope = ids.length > 1 ? '${ids.length} objects' : "object";
        editorSession.commitAppliedTransforms(ids, befores, afters,
            'Reset ${scope} ${rowName}');
    }

    /**
     * Apply one Inspector axis edit in the active WORLD/LOCAL space. World edits
     * on a rotated nested object change several local channels at once, so the
     * full desired local transform must be composed rather than one axis value.
     */
    function applyInspectorAxisEdit(row:Int, axis:Int, value:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var model = editorSession.findObject(selected.id);
        if (model == null) return;
        var commandBefore = atomicTransformStart(selected);
        var localBefore = selected.captureTransform();
        var localDesired = localTransformSpace
            ? transformWithAxisValue(localBefore, row, axis, value)
            : SharedGizmoDelta.localForWorld(
                transformWithAxisValue(worldTransformForLocal(model, localBefore),
                    row, axis, value),
                model.parent == null ? null
                    : editorSession.hierarchy.worldMatrix(model.parent),
                localBefore);
        var previous = localBefore.clone();
        if (row == 2) {
            var bounded = WorldBounds.fitScale(selected.mesh,
                localDesired.scaleX, localDesired.scaleY, localDesired.scaleZ,
                function(x, y, z) applySceneObjectScale(selected, x, y, z));
            localDesired.scaleX = bounded.x;
            localDesired.scaleY = bounded.y;
            localDesired.scaleZ = bounded.z;
        }
        selected.applyTransform(localDesired);
        if (!containSceneObject(selected)) {
            selected.applyTransform(previous);
            logWorldBound(selected);
        }
        refreshScaleRendering(selected);
        pushInspectorTransform(selected);
        // Keep the shared gizmo at the live value while the slider is dragged;
        // otherwise it stays at the drag-start pivot and snaps on release.
        refreshGizmoFromSelection();
        commitAtomicTransform(selected, commandBefore,
            inspectorTransformLabel(selected.name, row, axis));
        var axisNameText = axisName(axis);
        var applied = displayedTransform(selected);
        var actual = switch (row) {
            case 0: axis == 0 ? applied.positionX
                : axis == 1 ? applied.positionY : applied.positionZ;
            case 1:
                var euler = displayedRotationDegrees(selected);
                axis == 0 ? euler.x : axis == 1 ? euler.y : euler.z;
            default:
                axis == 0 ? applied.scaleX
                    : axis == 1 ? applied.scaleY : applied.scaleZ;
        };
        logActivity('command: ${selected.name} ${["position", "rotation", "scale"][row]}.'
            + '${axisNameText} = ${round2(actual)}'
            + (row == 1 ? " deg" : ""));
    }

    function applyTransformChange(axis:Int, value:Float):Void {
        applyInspectorAxisEdit(0, axis, value);
    }

    function applyRotationChange(axis:Int, degrees:Float):Void {
        applyInspectorAxisEdit(1, axis, degrees);
    }

    function applyScaleChange(axis:Int, value:Float):Void {
        applyInspectorAxisEdit(2, axis, value);
    }

    static inline function clampedScale(value:Float, fallbackSign:Float = 1):Float {
        return ScalePolicy.clamp(value, fallbackSign);
    }

    function scaleDescription(mesh:h3d.scene.Object):String {
        return '(${round2(mesh.scaleX)}, ${round2(mesh.scaleY)}, ${round2(mesh.scaleZ)})';
    }

    function setScaleProportionsLinked(linked:Bool):Void {
        scaleProportionsLinked = linked;
        logActivity('inspector: scale proportions ${linked ? "linked" : "unlinked"}');
    }

    /** Reset Position/Rotation/Scale to their canonical transform values. */
    function resetTransformRow(row:Int):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var commandBefore = selected.captureTransform();
        var desired = commandBefore.clone();
        var rowName:String;
        switch (row) {
            case 0:
                desired.positionX = 0;
                desired.positionY = 0;
                desired.positionZ = 0;
                rowName = "position";
            case 1:
                desired.rotationX = 0;
                desired.rotationY = 0;
                desired.rotationZ = 0;
                desired.rotationW = 1;
                desired.rotationHintX = 0;
                desired.rotationHintY = 0;
                desired.rotationHintZ = 0;
                desired.rotationHintValid = true;
                rowName = "rotation";
            default:
                desired.scaleX = 1;
                desired.scaleY = 1;
                desired.scaleZ = 1;
                rowName = "scale";
        }
        selected.applyTransform(desired);
        if (!containSceneObject(selected)) {
            selected.applyTransform(commandBefore);
            logWorldBound(selected);
        }
        if (row == 2) refreshScaleRendering(selected);
        pushInspectorTransform(selected);
        editorSession.commitAppliedTransform(selected.id, commandBefore,
            selected.captureTransform(), 'Reset ${selected.name} ${rowName}');
        logActivity('command: ${selected.name} reset ${rowName}');
    }

    static function axisName(axis:Int):String {
        return axis == 0 ? "x" : axis == 1 ? "y" : "z";
    }

    static inline function different(a:Float, b:Float):Bool {
        return !Math.isFinite(a) || !Math.isFinite(b) || Math.abs(a - b) > 0.0001;
    }

    /** Routine command telemetry, disabled in normal editor sessions. */
    function logActivity(message:String):Void {
        if (verboseLogging) boltUI.log(message);
    }

    /** Process-level diagnostic telemetry paired with logActivity(). */
    function printActivity(message:String):Void {
        if (verboseLogging) Sys.println(message);
    }

    function logWorldBound(selected:SceneObject):Void {
        boltUI.log('world bounds: ${selected.name} constrained to ±8 km');
    }

    /** Toolbar/shortcut tool switch: every tool drives its viewport gizmo. */
    function setEditorTool(tool:Int):Void {
        currentTool = tool;
        gizmo.setTool(tool);
        var selected = getSelectedObject();
        attachGizmo(selected);
        if (verboseLogging) {
            var toolNames = ["Move", "Rotate", "Scale"];
            logActivity('viewport tool: ${toolNames[tool]} gizmo active');
        }
    }

    /** Apply the viewport World/Local axis-space toggle through Main. */
    function setTransformSpace(local:Bool):Void {
        localTransformSpace = local;
        gizmo.setSpace(local ? TransformGizmo.SPACE_LOCAL : TransformGizmo.SPACE_WORLD);
        // The Inspector shows the active space too, so refresh its values as
        // soon as the mode changes rather than waiting for another edit.
        if (editorSession.selectedObjectIds.length > 1) {
            pushSelectionInspectorTransform();
        } else {
            var selected = getSelectedObject();
            if (selected != null) pushInspectorTransform(selected);
        }
        if (verboseLogging) {
            logActivity('viewport transform space: ${local ? "Local" : "World"}');
            var xAxis = gizmo.getAxisDirection(TransformGizmo.HANDLE_AXIS_X);
            printActivity('[gizmo] transform space=${local ? "Local" : "World"}'
                + ' xAxis=(${round2(xAxis.x)}, ${round2(xAxis.y)}, ${round2(xAxis.z)})');
        }
    }

    function onViewportHover(x:Float, y:Float):Void {
        if (!canEdit() || gizmoDragging) return;
        var pointer = viewportPointer(x, y);
        gizmo.setHover(gizmo.pick(viewportRay(x, y), pointer.x, pointer.y));
    }

    function onViewportPush(x:Float, y:Float):Bool {
        if (!canEdit()) return false;
        // A camera gesture owns the pointer; gizmo picking stays silent
        // until the gesture ends (Unreal-style navigation priority).
        if (cameraGesture >= 0) return false;
        var selected = getSelectedObject();
        if (selected == null) return false;
        var world = selectionPivotWorld();
        if (world == null) return false;
        applyGizmoProxy(world);
        var pointer = viewportPointer(x, y);
        var handle = gizmo.pick(viewportRay(x, y), pointer.x, pointer.y);
        if (handle < 0) return false;
        gizmoHandle = handle;
        gizmoDragging = true;
        gizmoWorldBounded = false;
        dragLastX = x;
        dragLastY = y;
        dragVirtualX = x;
        dragVirtualY = y;
        dragStartScaleX = world.scaleX;
        dragStartScaleY = world.scaleY;
        dragStartScaleZ = world.scaleZ;
        // Capture the full starting transform for incremental snapping.
        dragStartPos = new h3d.Vector(world.positionX, world.positionY, world.positionZ);
        dragStartQuat = new h3d.Quat();
        dragStartQuat.set(world.rotationX, world.rotationY,
            world.rotationZ, world.rotationW);
        dragStartWorldTransform = world.clone();
        // Snapshot every selected object so one gizmo drag can move them all.
        gizmoDragAnchors.resize(0);
        for (id in editorSession.selectedObjectIds) {
            var model = editorSession.findObject(id);
            var sceneObject = findSceneObject(id);
            if (model == null || sceneObject == null) continue;
            gizmoDragAnchors.push(new GizmoDragAnchor(sceneObject, model,
                model.transform.clone(), model.worldTransform.clone()));
        }
        var primaryAnchor = anchorFor(selected.id);
        dragStartTransform = primaryAnchor == null
            ? selected.captureTransform() : primaryAnchor.startLocal.clone();
        dragPreviewTransform = dragStartTransform.clone();
        gizmo.beginDrag(handle, gizmoProxy, viewportRay(x, y), pointer.x, pointer.y);
        // Capture all gizmo anchors before raw input can invoke its callback.
        beginRelativeDrag();
        if (verboseLogging) {
            var handleName = gizmo.describe(handle);
            var scope = gizmoDragAnchors.length > 1
                ? '${gizmoDragAnchors.length} objects' : selected.name;
            logActivity('gizmo: drag ${scope} ${handleName}');
            printActivity('[gizmo] drag start objects=${gizmoDragAnchors.length}'
                + ' primary=${selected.name} handle=${handleName}'
                + ' space=${localTransformSpace ? "Local" : "World"}'
                + ' at=(${round2(world.positionX)}, ${round2(world.positionY)},'
                + ' ${round2(world.positionZ)})');
        }
        return true;
    }

    function anchorFor(id:Int):Null<GizmoDragAnchor> {
        for (anchor in gizmoDragAnchors) {
            if (anchor.sceneObject.id == id) return anchor;
        }
        return null;
    }

    function onViewportDrag(x:Float, y:Float):Void {
        if (!canEdit() || !gizmoDragging) return;
        var selected = getSelectedObject();
        if (selected == null) {
            cancelGizmoDrag();
            return;
        }
        // Absolute path (verification probes only): fold pixel motion into
        // the virtual pointer. Relative-mode drags are driven by
        // onRelativeMouseMove instead; hxd delivers no EMove then.
        dragVirtualX += x - dragLastX;
        dragVirtualY += y - dragLastY;
        dragLastX = x;
        dragLastY = y;
        applyDragTransform(selected);
    }

    /**
     * Relative mouse mode for gizmo drags: the OS cursor is hidden and
     * locked while raw hardware deltas drive the virtual drag pointer, so
     * drags keep going however far the hand moves - no stalls, no cursor
     * wrapping. Switching back to Absolute on drag end unhides the cursor
     * and parks it where the drag ended (Unreal-style): the release point
     * in virtual pointer space, not the drag-start position.
     */
    function beginRelativeDrag():Void {
        dragRelative = false;
        if (inputProbeMode) return;
        try {
            nativeWindow.mouseMode =
                hxd.impl.MouseMode.Relative(onRelativeMouseMove, true);
            dragRelative = switch (nativeWindow.mouseMode) {
                case Relative(_, _): true;
                case _: false;
            };
            if (!dragRelative) {
                Sys.println('[gizmo] relative mouse mode was rejected; using absolute fallback');
            }
        } catch (error:Dynamic) {
            Sys.println('[gizmo] relative mouse mode unavailable: ${Std.string(error)}');
        }
    }

    function endRelativeDrag():Void {
        if (!dragRelative) return;
        dragRelative = false;
        try {
            nativeWindow.mouseMode = hxd.impl.MouseMode.Absolute;
            // The hldx path of set_mouseMode skips the position restore, so
            // park the cursor by hand. Unreal-style: it stays where the
            // drag ended rather than snapping back to the drag start. The
            // virtual drag pointer is viewport-local, so convert it back to
            // window client coordinates before warping.
            var rect = boltUI.getViewportRect();
            nativeWindow.setCursorPos(
                Math.round(dragVirtualX + rect.x),
                Math.round(dragVirtualY + rect.y));
        } catch (error:Dynamic) {
            Sys.println('[gizmo] mouse mode restore failed: ${Std.string(error)}');
        }
    }

    /**
     * Raw hardware deltas from the hidden-cursor relative mouse mode drive
     * both consumers: gizmo drags and RMB free-look. The window has one
     * relative callback at a time, so both sessions route through here and
     * only the active one acts. Callbacks are never turned back into
     * absolute EMove events, which would run the capture path twice.
     */
    function onRelativeMouseMove(event:hxd.Event):Void {
        if (gizmoDragging && dragRelative) {
            if (event.relX == 0 && event.relY == 0) return;
            event.propagate = false;
            dragVirtualX += event.relX;
            dragVirtualY += event.relY;
            var selected = getSelectedObject();
            if (selected == null) {
                cancelGizmoDrag();
                return;
            }
            applyDragTransform(selected);
            return;
        }
        if (cameraGesture == EditorCameraController.GESTURE_LOOK
                && lookRelative) {
            if (event.relX == 0 && event.relY == 0) return;
            event.propagate = false;
            cameraController.addLookDelta(event.relX, event.relY);
        }
    }

    /** Abort a drag safely if its selected object disappears mid-capture. */
    function cancelGizmoDrag():Void {
        gizmoDragging = false;
        gizmoHandle = -1;
        gizmoWorldBounded = false;
        dragStartTransform = null;
        dragStartWorldTransform = null;
        dragPreviewTransform = null;
        gizmoDragAnchors.resize(0);
        endRelativeDrag();
        gizmo.endDrag();
    }

    /** Apply the current virtual drag pointer to the gizmo and the inspector. */
    function applyDragTransform(selected:SceneObject):Void {
        var model = editorSession.findObject(selected.id);
        if (model == null || dragStartWorldTransform == null) return;
        var pointer = viewportPointer(dragVirtualX, dragVirtualY);
        var next = gizmo.dragTo(pointer.x, pointer.y);
        if (next == null) return;
        var desiredWorld = dragStartWorldTransform.clone();
        switch (next) {
            case MovePosition(nx, ny, nz):
                // Unreal-style incremental snapping: the drag delta is
                // quantized onto step multiples relative to the drag-start
                // position, so enabling snapping or starting a drag never
                // teleports the object onto the grid. In Local space the
                // delta quantizes along the object's own axes (the captured
                // drag-start rotation); in World space it uses the grid axes.
                var snapped = snap.snapPositionIncremental(dragStartPos,
                    new h3d.Vector(nx, ny, nz),
                    localTransformSpace ? dragStartQuat : null);
                desiredWorld.positionX = WorldBounds.clampCoordinate(snapped.x);
                desiredWorld.positionY = WorldBounds.clampCoordinate(snapped.y);
                desiredWorld.positionZ = WorldBounds.clampCoordinate(snapped.z);
                if (different(desiredWorld.positionX, snapped.x)
                        || different(desiredWorld.positionY, snapped.y)
                        || different(desiredWorld.positionZ, snapped.z)) {
                    gizmoWorldBounded = true;
                }
            case RotateAxis(axisX, axisY, axisZ, radians):
                // Snap only the torus' scalar angle, then compose that
                // press-time world-axis increment with the complete start
                // quaternion. An arbitrary prior arcball orientation must not
                // be decomposed into three coupled Euler deltas.
                var targetRotation = snap.snapAxisRotationIncremental(
                    dragStartQuat, new h3d.Vector(axisX, axisY, axisZ), radians);
                desiredWorld.rotationX = targetRotation.x;
                desiredWorld.rotationY = targetRotation.y;
                desiredWorld.rotationZ = targetRotation.z;
                desiredWorld.rotationW = targetRotation.w;
                desiredWorld.rotationHintValid = false;
            case RotateQuat(q):
                // The center arcball remains freeform even while ring snapping
                // is enabled; stepping camera-space tumble feels discontinuous.
                desiredWorld.rotationX = q.x;
                desiredWorld.rotationY = q.y;
                desiredWorld.rotationZ = q.z;
                desiredWorld.rotationW = q.w;
                desiredWorld.rotationHintValid = false;
            case ScaleValues(sx, sy, sz):
                if (scaleProportionsLinked) {
                    var ratio = linkedGizmoScaleRatio(sx, sy, sz);
                    sx = dragStartScaleX * ratio;
                    sy = dragStartScaleY * ratio;
                    sz = dragStartScaleZ * ratio;
                }
                // Unreal-style incremental scale snapping: per-axis deltas
                // quantized against the scale step. Signed dead-zone clamping
                // allows mirror crossing without a singular zero transform.
                var snapped = snap.snapScaleIncremental(
                    dragStartScaleX, dragStartScaleY, dragStartScaleZ, sx, sy, sz);
                var targetX = clampedScale(snapped.x, dragStartScaleX);
                var targetY = clampedScale(snapped.y, dragStartScaleY);
                var targetZ = clampedScale(snapped.z, dragStartScaleZ);
                desiredWorld.scaleX = targetX;
                desiredWorld.scaleY = targetY;
                desiredWorld.scaleZ = targetZ;
        }
        // One pivot delta, applied to every object in the selection. The
        // proxy already sits at the desired pivot, so each object's own world
        // transform is derived from its drag-start world transform.
        var mode = switch (currentTool) {
            case TransformGizmo.TOOL_MOVE: SharedGizmoDelta.MOVE;
            case TransformGizmo.TOOL_ROTATE: SharedGizmoDelta.ROTATE;
            default: SharedGizmoDelta.SCALE;
        };
        // Compute every desired world transform first. A selected parent must be
        // projected with its *previewed* world matrix, not the session's stale
        // model world (which only updates when the drag is committed) — otherwise
        // a selected child gets the parent's delta applied twice.
        var desiredByAnchor:Map<GizmoDragAnchor, EditorTransform> = new Map();
        for (anchor in gizmoDragAnchors) {
            desiredByAnchor.set(anchor, SharedGizmoDelta.apply(anchor.startWorld,
                dragStartWorldTransform, desiredWorld, mode));
        }
        for (anchor in gizmoDragAnchors) {
            var desired = desiredByAnchor.get(anchor);
            var local:EditorTransform = desired;
            var parent = anchor.model.parent;
            if (parent != null) {
                var parentAnchor = anchorFor(parent.id);
                var parentWorld:Null<TransformMatrix> = null;
                if (parentAnchor != null) {
                    var parentDesired = desiredByAnchor.get(parentAnchor);
                    if (parentDesired != null) parentWorld = parentDesired.toMatrix();
                }
                if (parentWorld == null) {
                    parentWorld = editorSession.hierarchy.worldMatrix(parent);
                }
                local = SharedGizmoDelta.localForWorld(
                    desired, parentWorld, anchor.startLocal);
            }
            anchor.sceneObject.applyTransform(local);
            if (!containSceneObject(anchor.sceneObject)) {
                anchor.sceneObject.applyTransform(anchor.previewLocal);
                gizmoWorldBounded = true;
                continue;
            }
            anchor.previewLocal = anchor.sceneObject.captureTransform();
            refreshScaleRendering(anchor.sceneObject);
        }
        var primaryAnchor = anchorFor(selected.id);
        dragPreviewTransform = primaryAnchor == null
            ? dragStartTransform : primaryAnchor.previewLocal;
        applyGizmoProxy(desiredWorld);
        pushSelectionInspectorTransform();
    }

    /**
     * Ctrl+End: the one absolute snap. Round the selected object's world
     * position onto the nearest translation grid point, independent of the
     * translation enable flag — this is an explicit user command.
     */
    function snapSelectionToGrid():Void {
        if (!canEdit()) return;
        var selected = getSelectedObject();
        if (selected == null || gizmoDragging) return;
        if (editorSession.selectedObjectIds.length > 1) {
            snapSelectionToGridMulti();
            return;
        }
        var model = editorSession.findObject(selected.id);
        if (model == null) return;
        var commandBefore = model.transform.clone();
        var worldBefore = model.worldTransform;
        var step = snap.translationStep;
        var grid = snap.snapPositionToGrid(
            new h3d.Vector(worldBefore.positionX,
                worldBefore.positionY, worldBefore.positionZ));
        if (worldBefore.positionX == grid.x && worldBefore.positionY == grid.y
                && worldBefore.positionZ == grid.z) {
            logActivity('snapping: ${selected.name} already on the ${round2(step)} grid');
            return;
        }
        var desired = worldBefore.clone();
        desired.positionX = WorldBounds.clampCoordinate(grid.x);
        desired.positionY = WorldBounds.clampCoordinate(grid.y);
        desired.positionZ = WorldBounds.clampCoordinate(grid.z);
        var local = editorSession.hierarchy.localTransformForWorld(
            model, desired, model.parent);
        selected.applyTransform(local);
        var placed = containSceneObject(selected);
        if (!placed) {
            selected.applyTransform(commandBefore);
            logWorldBound(selected);
            return;
        }
        local = selected.captureTransform();
        var actualWorld = worldTransformForLocal(model, local);
        var constrained = different(actualWorld.positionX, grid.x)
            || different(actualWorld.positionY, grid.y)
            || different(actualWorld.positionZ, grid.z);
        pushInspectorTransform(selected);
        editorSession.commitAppliedTransform(selected.id, commandBefore,
            local, 'Snap ${selected.name} to Grid');
        if (constrained) logWorldBound(selected);
        logActivity('snapping: ${selected.name} to grid (step ${round2(step)}) '
            + 'position = (${round2(actualWorld.positionX)}, ${round2(actualWorld.positionY)},'
            + ' ${round2(actualWorld.positionZ)})');
    }

    /** Ctrl+End with several objects selected: snap each world position. */
    function snapSelectionToGridMulti():Void {
        if (!canEdit()) return;
        var step = snap.translationStep;
        var ids:Array<Int> = [];
        var befores:Array<EditorTransform> = [];
        var afters:Array<EditorTransform> = [];
        for (sceneObject in selectedSceneObjects()) {
            var model = editorSession.findObject(sceneObject.id);
            if (model == null) continue;
            var before = model.transform.clone();
            var world = model.worldTransform;
            var grid = snap.snapPositionToGrid(new h3d.Vector(
                world.positionX, world.positionY, world.positionZ));
            if (grid.x == world.positionX && grid.y == world.positionY
                    && grid.z == world.positionZ) continue;
            var desired = world.clone();
            desired.positionX = WorldBounds.clampCoordinate(grid.x);
            desired.positionY = WorldBounds.clampCoordinate(grid.y);
            desired.positionZ = WorldBounds.clampCoordinate(grid.z);
            var local = editorSession.hierarchy.localTransformForWorld(
                model, desired, model.parent);
            sceneObject.applyTransform(local);
            if (!containSceneObject(sceneObject)) {
                sceneObject.applyTransform(before);
                logWorldBound(sceneObject);
                continue;
            }
            ids.push(sceneObject.id);
            befores.push(before);
            afters.push(sceneObject.captureTransform());
        }
        if (ids.length == 0) return;
        pushSelectionInspectorTransform();
        editorSession.commitAppliedTransforms(ids, befores, afters,
            'Snap ${ids.length} objects to Grid');
        logActivity('snapping: ${ids.length} objects to grid (step ${round2(step)})');
    }

    /** Optional diagnostic feedback for viewport snap toggle/preset changes. */
    function onSnapChanged(mode:Int):Void {
        if (!verboseLogging) return;
        var modeNames = ["translation", "rotation", "scale"];
        var enabled = snap.isEnabled(mode);
        logActivity('snapping: ${modeNames[mode]} ${enabled ? "enabled" : "disabled"}'
            + ' · step ${round2(snap.stepFor(mode))}');
    }

    // ------------------------------------------------------------------
    // Viewport camera navigation. Gesture state lives in Main so gizmo
    // presses can reject navigation and vice versa (one pointer owner at a
    // time); all motion math lives in EditorCameraController.
    // ------------------------------------------------------------------

    /** Wheel hover dollies the camera; during RMB flight it adjusts speed. */
    function onViewportWheel(delta:Float):Void {
        if (gizmoDragging) return;
        if (cameraGesture == EditorCameraController.GESTURE_LOOK) {
            cameraController.adjustSpeedForWheel(delta);
            refreshCameraSpeedLabel();
            return;
        }
        if (cameraGesture < 0) cameraController.dollyForWheel(delta);
    }

    function onViewportCameraBegin(kind:Int, viewX:Float, viewY:Float):Bool {
        if (gizmoDragging || cameraGesture >= 0) return false;
        cameraGesture = kind;
        cameraGestureLastX = viewX;
        cameraGestureLastY = viewY;
        switch (kind) {
            case EditorCameraController.GESTURE_LOOK:
                cameraController.beginLook();
                lookRelative = false;
                beginRelativeLook();
            case EditorCameraController.GESTURE_PAN:
                cameraController.beginPan();
            case EditorCameraController.GESTURE_ORBIT:
                cameraController.beginOrbit(currentOrbitPivot());
            default:
                cameraGesture = -1;
                return false;
        }
        if (verboseLogging) {
            logActivity('camera: ${gestureName(kind)} gesture started');
            printActivity('[camera] gesture=${gestureName(kind)} begin');
        }
        return true;
    }

    function onViewportCameraMove(kind:Int, viewX:Float, viewY:Float):Void {
        if (cameraGesture != kind) return;
        // RMB free-look in relative mouse mode is driven by raw hardware
        // deltas in onRelativeMouseMove; the capture delivers no EMove
        // events then, but stay defensive against both firing.
        if (kind == EditorCameraController.GESTURE_LOOK && lookRelative) return;
        var dx = viewX - cameraGestureLastX;
        var dy = viewY - cameraGestureLastY;
        cameraGestureLastX = viewX;
        cameraGestureLastY = viewY;
        if (dx == 0 && dy == 0) return;
        switch (kind) {
            case EditorCameraController.GESTURE_LOOK:
                cameraController.addLookDelta(dx, dy);
            case EditorCameraController.GESTURE_PAN:
                cameraController.addPanDelta(dx, dy);
            case EditorCameraController.GESTURE_ORBIT:
                cameraController.addOrbitDelta(dx, dy);
        }
    }

    function onViewportCameraEnd(kind:Int, viewX:Float, viewY:Float):Void {
        if (cameraGesture != kind) return;
        switch (kind) {
            case EditorCameraController.GESTURE_LOOK:
                if (lookRelative) {
                    // Restore absolute mode only, no cursor parking: free
                    // look leaves the cursor wherever the view stopped, and
                    // Relative(restore) already keeps the pre-gesture spot
                    // out of the equation.
                    lookRelative = false;
                    try {
                        nativeWindow.mouseMode = hxd.impl.MouseMode.Absolute;
                    } catch (error:Dynamic) {
                        Sys.println('[camera] mouse mode restore failed: '
                            + Std.string(error));
                    }
                }
                cameraController.endLook();
            case EditorCameraController.GESTURE_PAN:
                cameraController.endPan();
            case EditorCameraController.GESTURE_ORBIT:
                cameraController.endOrbit();
        }
        cameraGesture = -1;
        if (verboseLogging) {
            logActivity('camera: ${gestureName(kind)} gesture ended');
            printActivity('[camera] gesture=${gestureName(kind)} end');
        }
    }

    /**
     * Relative mouse mode for RMB free-look: the cursor hides and locks so
     * the view can turn indefinitely without stalling at screen edges. The
     * single shared relative callback (onRelativeMouseMove) routes deltas
     * here while the look gesture is the active session.
     */
    function beginRelativeLook():Void {
        lookRelative = false;
        if (inputProbeMode) return;
        try {
            nativeWindow.mouseMode =
                hxd.impl.MouseMode.Relative(onRelativeMouseMove, true);
            lookRelative = switch (nativeWindow.mouseMode) {
                case Relative(_, _): true;
                case _: false;
            };
        } catch (error:Dynamic) {
            Sys.println('[camera] relative mouse mode unavailable: '
                + Std.string(error));
        }
    }

    /** Orbit pivot: the primary selection's world position, or world origin. */
    function currentOrbitPivot():h3d.Vector {
        var selected = getSelectedObject();
        if (selected != null) {
            var point = selected.mesh.localToGlobal(new h3d.col.Point());
            return new h3d.Vector(point.x, point.y, point.z);
        }
        return new h3d.Vector(0, 0, 0);
    }

    /**
     * F: frame every selected object and preserve the current view rotation.
     * This is a selection command rather than a viewport-navigation command,
     * so it is intentionally routed without requiring viewport focus.
     */
    function focusSelection():Void {
        if (gizmoDragging || cameraGesture >= 0) return;
        var ids = editorSession.selectedObjectIds;
        if (ids.length == 0) return;
        var focusBounds:Array<h3d.col.Bounds> = [];
        for (id in ids) {
            var selected = findSceneObject(id);
            if (selected == null) continue;
            var bounds = selected.mesh.getBounds();
            var populated = bounds.xMax >= bounds.xMin
                && bounds.yMax >= bounds.yMin && bounds.zMax >= bounds.zMin
                && Math.isFinite(bounds.xMin) && Math.isFinite(bounds.xMax)
                && Math.isFinite(bounds.yMin) && Math.isFinite(bounds.yMax)
                && Math.isFinite(bounds.zMin) && Math.isFinite(bounds.zMax);
            if (populated) {
                focusBounds.push(bounds);
            } else {
                // Empty GameObjects have no render bounds; include their world
                // pivot as a point so a selection made only of them still frames.
                var pivot = selected.mesh.localToGlobal(new h3d.col.Point());
                if (Math.isFinite(pivot.x) && Math.isFinite(pivot.y)
                        && Math.isFinite(pivot.z)) {
                    var point = new h3d.col.Bounds();
                    point.addPoint(pivot);
                    focusBounds.push(point);
                }
            }
        }
        if (focusBounds.length == 0) return;
        if (cameraController.focusOnBounds(focusBounds)) {
            var label = ids.length > 1
                ? '${ids.length} objects'
                : (findSceneObject(ids[0]) != null
                    ? findSceneObject(ids[0]).name : "selection");
            logActivity('camera: focused ${label}');
        }
    }

    /** G key: toggle the independent grid pass, nothing else changes. */
    function toggleEditorGrid():Void {
        gridRenderer.visible = !gridRenderer.visible;
        printActivity('[grid] visible=${gridRenderer.visible}');
        logActivity(gridRenderer.visible
            ? "viewport: editor grid shown"
            : "viewport: editor grid hidden");
    }

    function gestureName(kind:Int):String {
        return switch (kind) {
            case EditorCameraController.GESTURE_LOOK: "look";
            case EditorCameraController.GESTURE_PAN: "pan";
            case EditorCameraController.GESTURE_ORBIT: "orbit";
            default: "unknown";
        };
    }

    /**
     * Push the current speed to the viewport overlay. The label is only
     * rebuilt when the base speed or a modifier state actually changed, so
     * steady frames allocate nothing.
     */
    function refreshCameraSpeedLabel():Void {
        var base = cameraController.baseSpeedValue();
        var modifier = cameraController.modifierState();
        if (base == lastSpeedValue && modifier == lastSpeedModifierState) return;
        lastSpeedValue = base;
        lastSpeedModifierState = modifier;
        var label = cameraController.speedLabel();
        boltUI.setCameraSpeedLabel(label);
        printActivity('[camera] speed label=$label');
    }

    /** Ratio represented by the active scale handle's unlinked result. */
    function linkedGizmoScaleRatio(sx:Float, sy:Float, sz:Float):Float {
        return switch (gizmoHandle) {
            case TransformGizmo.HANDLE_AXIS_Y, TransformGizmo.HANDLE_PLANE_YZ:
                sy / ScalePolicy.nonZero(dragStartScaleY, sy);
            case TransformGizmo.HANDLE_AXIS_Z, TransformGizmo.HANDLE_PLANE_ZX:
                sz / ScalePolicy.nonZero(dragStartScaleZ, sz);
            default:
                sx / ScalePolicy.nonZero(dragStartScaleX, sx);
        };
    }

    /** Transform values as shown by the Inspector for the active space mode. */
    function displayedTransform(selected:SceneObject):EditorTransform {
        var local = selected.captureTransform();
        if (localTransformSpace) return local;
        var model = editorSession.findObject(selected.id);
        return model == null ? local : worldTransformForLocal(model, local);
    }

    function displayedRotationDegrees(selected:SceneObject):h3d.Vector {
        return localTransformSpace
            ? rotationDegrees(selected)
            : transformRotationDegrees(displayedTransform(selected));
    }

    /** Live inspector values while a gizmo drag is in progress. */
    function pushInspectorTransform(selected:SceneObject):Void {
        var model = editorSession.findObject(selected.id);
        if (model == null) return;
        var componentIndex = model.components.indexOf(model.transform);
        var displayed = displayedTransform(selected);
        var rotation = displayedRotationDegrees(selected);
        boltUI.updateInspectorVector(componentIndex, "position",
            displayed.positionX, displayed.positionY, displayed.positionZ);
        boltUI.updateInspectorVector(componentIndex, "rotation",
            rotation.x, rotation.y, rotation.z);
        boltUI.updateInspectorVector(componentIndex, "scale",
            displayed.scaleX, displayed.scaleY, displayed.scaleZ);
    }

    /** Live inspector values for every selected object, with mixed-axis hints. */
    function pushSelectionInspectorTransform():Void {
        var ids = editorSession.selectedObjectIds;
        if (ids.length <= 1) {
            var single = getSelectedObject();
            if (single != null) pushInspectorTransform(single);
            return;
        }
        var primary = findSceneObject(editorSession.selectedObjectId);
        var model = editorSession.findObject(editorSession.selectedObjectId);
        if (primary == null || model == null) return;
        var componentIndex = model.components.indexOf(model.transform);
        var rows = ["position", "rotation", "scale"];
        for (row in 0...rows.length) {
            var values = transformVectorFor(primary, row);
            var mixed = [false, false, false];
            for (id in ids) {
                if (id == editorSession.selectedObjectId) continue;
                var other = findSceneObject(id);
                if (other == null) continue;
                var candidate = transformVectorFor(other, row);
                for (axis in 0...3) {
                    if (different(candidate[axis], values[axis])) mixed[axis] = true;
                }
            }
            boltUI.updateInspectorVectorMixed(componentIndex, rows[row], values, mixed);
        }
    }

    function transformVectorFor(sceneObject:SceneObject, row:Int):Array<Float> {
        var displayed = displayedTransform(sceneObject);
        return switch (row) {
            case 0: [displayed.positionX, displayed.positionY, displayed.positionZ];
            case 1:
                var rotation = displayedRotationDegrees(sceneObject);
                [rotation.x, rotation.y, rotation.z];
            default: [displayed.scaleX, displayed.scaleY, displayed.scaleZ];
        };
    }

    function onViewportRelease(x:Float, y:Float):Void {
        if (!canEdit() || !gizmoDragging) return;
        gizmoDragging = false;
        endRelativeDrag();
        var handle = gizmoHandle;
        gizmoHandle = -1;
        gizmo.endDrag();
        var selected = getSelectedObject();
        if (selected == null || handle < 0) {
            gizmoWorldBounded = false;
            dragStartTransform = null;
            return;
        }
        if (gizmoWorldBounded) logWorldBound(selected);
        gizmoWorldBounded = false;
        var handleName = gizmo.describe(handle);
        var scope = gizmoDragAnchors.length > 1
            ? '${gizmoDragAnchors.length} objects' : selected.name;
        var commandName = switch (currentTool) {
            case TransformGizmo.TOOL_MOVE: 'Move ${scope}';
            case TransformGizmo.TOOL_ROTATE: 'Rotate ${scope}';
            default: 'Scale ${scope}';
        };
        if (gizmoDragAnchors.length > 0) {
            // One shared delta per object, but a single undo step for the
            // whole gesture (matching Unreal's transform behavior).
            var ids:Array<Int> = [];
            var befores:Array<EditorTransform> = [];
            var afters:Array<EditorTransform> = [];
            for (anchor in gizmoDragAnchors) {
                ids.push(anchor.sceneObject.id);
                befores.push(anchor.startLocal);
                afters.push(anchor.sceneObject.captureTransform());
            }
            editorSession.commitAppliedTransforms(ids, befores, afters, commandName);
        } else if (dragStartTransform != null && dragPreviewTransform != null) {
            editorSession.commitAppliedTransform(selected.id, dragStartTransform,
                dragPreviewTransform, commandName);
        }
        dragStartTransform = null;
        dragStartWorldTransform = null;
        dragPreviewTransform = null;
        gizmoDragAnchors.resize(0);
        if (!verboseLogging) return;
        var at = '(${round2(selected.mesh.x)}, ${round2(selected.mesh.y)},'
            + ' ${round2(selected.mesh.z)})';
        var rotation = rotationDegrees(selected);
        var rot = '(${round2(rotation.x)}, ${round2(rotation.y)}, ${round2(rotation.z)} deg)';
        var scl = '(${round2(selected.mesh.scaleX)}, ${round2(selected.mesh.scaleY)},'
            + ' ${round2(selected.mesh.scaleZ)})';
        switch (currentTool) {
            case TransformGizmo.TOOL_MOVE:
                logActivity('command: ${selected.name} ${handleName} position = ' + at);
                printActivity('[gizmo] drag end object=${selected.name} handle=${handleName} at=' + at);
            case TransformGizmo.TOOL_ROTATE:
                logActivity('command: ${selected.name} ${handleName} rotation = ' + rot);
                printActivity('[gizmo] drag end object=${selected.name} handle=${handleName} rotation=' + rot);
            default:
                logActivity('command: ${selected.name} ${handleName} scale = ' + scl);
                printActivity('[gizmo] drag end object=${selected.name} handle=${handleName} scale=' + scl);
        }
    }

    function onViewportClick(x:Float, y:Float):Void {
        if (!canEdit()) return;
        var pick = pickViewportObject(x, y);
        var nearestObject = pick.object;
        // Modifier semantics match the hierarchy: Ctrl toggles membership,
        // Shift adds to the current selection, a plain click replaces it.
        var mode = hxd.Key.isDown(hxd.Key.SHIFT) ? SelectionClickMode.Add
            : (hxd.Key.isDown(hxd.Key.CTRL) ? SelectionClickMode.Toggle
                : SelectionClickMode.Replace);
        var clickedId = nearestObject == null ? -1 : nearestObject.id;
        var next = SelectionClick.apply(editorSession.selectedObjectIds,
            editorSession.selectedObjectId, clickedId, mode);
        clearInspectorTransformEdit();
        editorSession.selectObjects(next.ids, next.primary);
        if (nearestObject == null) {
            logActivity("viewport: no object at pointer");
        } else {
            logActivity('viewport: ${mode == SelectionClickMode.Replace
                ? "selected" : "updated selection with"} ${nearestObject.name}');
        }
    }

    function createSceneObjectView(object:EditorObject):SceneObject {
        // Every GameObject has the same plain transform root. Renderable
        // geometry is supplied only by attached MeshRenderer components.
        var node = new h3d.scene.Object(s3d);
        node.name = object.name;
        var sceneObject = new SceneObject(object.id, node, object.persistentId);
        sceneObject.synchronizeComponents(object);
        sceneObject.applyTransform(object.transform.value);
        refreshScaleRendering(sceneObject);
        return sceneObject;
    }

    /** Mirror the pure EditorSession model into Heaps scene objects. */
    function synchronizeSceneObjects():Void {
        // Play mode projects the detached runtime copy instead of the editor
        // session; both use the same model -> h3d bridge below.
        var session = activeSession();
        var index = sceneObjects.length - 1;
        while (index >= 0) {
            if (session.findObject(sceneObjects[index].id) == null) {
                sceneObjectsById.remove(sceneObjects[index].id);
                sceneObjects[index].mesh.remove();
                sceneObjects.splice(index, 1);
            }
            index--;
        }

        // Ensure every renderer node exists before linking parent references.
        for (object in session.objects) {
            var sceneObject = findSceneObject(object.id);
            if (sceneObject == null) {
                sceneObject = createSceneObjectView(object);
                sceneObjectsById.set(object.id, sceneObject);
                sceneObjects.push(sceneObject);
            }
        }

        var ordered:Array<SceneObject> = [];
        for (object in session.hierarchy.flatten()) {
            var sceneObject = findSceneObject(object.id);
            var parentView = object.parent == null
                ? null : findSceneObject(object.parent.id);
            var desiredParent:h3d.scene.Object = parentView == null
                ? s3d : parentView.mesh;
            if (sceneObject.mesh.parent != desiredParent) {
                if (parentView == null) desiredParent.addChild(sceneObject.mesh);
                else desiredParent.addChildAt(sceneObject.mesh, object.siblingIndex);
            } else if (parentView != null
                    && desiredParent.getChildIndex(sceneObject.mesh) != object.siblingIndex) {
                desiredParent.addChildAt(sceneObject.mesh, object.siblingIndex);
            }
            sceneObject.name = object.name;
            // Hidden/disabled objects leave the scene graph intact but stop
            // contributing geometry to the viewport.
            sceneObject.mesh.visible = object.visible && object.enabled;
            sceneObject.synchronizeComponents(object);
            sceneObject.applyTransform(object.transform.value);
            refreshScaleRendering(sceneObject);
            ordered.push(sceneObject);
        }
        sceneObjects.resize(ordered.length);
        for (index in 0...ordered.length) sceneObjects[index] = ordered[index];
    }

    /** Refresh renderer and UI after execute, undo, redo, or selection. */
    function synchronizeEditorSession():Void {
        synchronizeSceneObjects();
        refreshHierarchy();
        refreshSelectionOutline();
        var selected = getSelectedObject();
        attachGizmo(selected);
        refreshSelectionInspector();
        boltUI.setHistoryState(editorSession.history.undoLabel,
            editorSession.history.redoLabel);
    }

    // ------------------------------------------------------------------
    // Play mode. The editor session is the authoritative authored state;
    // Play runs a serialized, detached copy and Stop discards it. No editor
    // command, selection, or history entry is ever created by runtime updates.
    // ------------------------------------------------------------------

    /** Editor mutations are rejected while the detached runtime is running. */
    inline function canEdit():Bool return !isPlaying();

    /** Remove every Heaps view without touching either session's model. */
    function clearSceneObjectViews():Void {
        for (sceneObject in sceneObjects) sceneObject.mesh.remove();
        sceneObjects.resize(0);
        sceneObjectsById.clear();
        selectionOutline.clear();
    }

    /** Capture the authored graph and start a detached runtime copy. */
    function playScene():Void {
        if (playSession != null) return;
        // Never switch modes from inside a live editable gesture or capture.
        if (gizmoDragging || cameraGesture >= 0 || keybindings.capturePending) return;
        clearInspectorTransformEdit();
        clearPrimitiveSettingsEdit();
        try {
            var scene = projectSession.scene;
            var snapshot = SceneSerializer.fromSession(editorSession,
                scene.id, scene.name);
            var runtime = new PlayModeSession(snapshot);
            playSavedGridVisible = gridRenderer.visible;
            playSession = runtime;
            gridRenderer.visible = false;
            axisGizmo.visible = false;
            clearSceneObjectViews();
            synchronizeSceneObjects();
            gizmo.attach(null);
            boltUI.setPlaybackState(true, false);
            printActivity('[probe] play started objects=${runtime.objects().length} '
                + 'revision=${editorSession.history.revision}');
            logActivity('play: started (${runtime.objects().length} objects)');
        } catch (error:Dynamic) {
            playSession = null;
            gridRenderer.visible = playSavedGridVisible;
            axisGizmo.visible = true;
            synchronizeEditorSession();
            boltUI.setPlaybackState(false, false);
            boltUI.log('play: could not start — ${Std.string(error)}');
        }
    }

    function togglePlaybackPause():Void {
        var runtime = playSession;
        if (runtime == null) return;
        var paused = runtime.togglePaused();
        boltUI.setPlaybackState(true, paused);
        printActivity('[probe] play paused=${paused}');
        logActivity(paused ? "play: paused" : "play: resumed");
    }

    /** Discard the runtime copy and restore the exact authored editor state. */
    function stopScene():Void {
        var runtime = playSession;
        if (runtime == null) return;
        playSession = null;
        runtime.destroy();
        gridRenderer.visible = playSavedGridVisible;
        axisGizmo.visible = true;
        clearSceneObjectViews();
        synchronizeEditorSession();
        boltUI.setPlaybackState(false, false);
        printActivity('[probe] play stopped elapsed=${round2(runtime.elapsed)} '
            + 'revision=${editorSession.history.revision}');
        logActivity("play: stopped - editor state restored");
    }

    /** Keep back-face culling aligned with a reflected transform's winding. */
    function refreshScaleRendering(sceneObject:SceneObject):Void {
        for (mesh in sceneObject.allRenderMeshes()) {
            var renderer = sceneObject.rendererFor(mesh);
            if (renderer == null) continue;
            var mirrored = mesh.getAbsPos().getDeterminant() < 0;
            // A camera inside a closed one-sided mesh sees only back faces.
            // Draw both sides only in that editor condition.
            var inside = cameraInsideMesh(mesh);
            for (index in 0...renderer.mesh.materials.length) {
                var material = renderer.mesh.materials[index];
                if (material == null) continue;
                var culling = inside
                    ? h3d.mat.Data.Face.None
                    : renderer.cullingForScale(mirrored, index);
                material.mainPass.culling = culling;
                var shadowPass = material.getPass("shadow");
                if (shadowPass != null) shadowPass.culling = culling;
            }
        }
    }

    /**
     * Rebuild SceneObject's exact affine correction after WorldBounds adjusts
     * editable local channels. A sheared nested object cannot be measured with
     * the old correction matrix left in place.
     */
    function containSceneObject(sceneObject:SceneObject):Bool {
        WorldBounds.contain(sceneObject.mesh);
        sceneObject.applyTransform(sceneObject.captureTransform());
        return WorldBounds.containsObject(sceneObject.mesh);
    }

    /** Scale one render view while preserving and rebuilding affine shear. */
    function applySceneObjectScale(sceneObject:SceneObject,
            x:Float, y:Float, z:Float):Void {
        var transform = sceneObject.captureTransform();
        transform.scaleX = x;
        transform.scaleY = y;
        transform.scaleZ = z;
        sceneObject.applyTransform(transform);
    }

    function cameraInsideMesh(mesh:h3d.scene.Mesh):Bool {
        if (mesh.primitive == null) return false;
        var bounds = mesh.primitive.getBounds();
        if (bounds == null) return false;
        var point = new h3d.col.Point(
            s3d.camera.pos.x, s3d.camera.pos.y, s3d.camera.pos.z);
        mesh.globalToLocal(point);
        return point.x >= bounds.xMin && point.x <= bounds.xMax
            && point.y >= bounds.yMin && point.y <= bounds.yMax
            && point.z >= bounds.zMin && point.z <= bounds.zMax;
    }

    /** Short object-name prefix ("Cube", "Sphere", ...) for a mesh asset id. */
    function primitiveName(meshId:String):String {
        var mesh = PrimitiveMeshes.find(meshId);
        var label = mesh == null ? "Primitive" : mesh.name;
        return StringTools.startsWith(label, "Primitive ")
            ? label.substr("Primitive ".length) : label;
    }

    /** Distance from the editor camera used by the Add menu's click action. */
    static inline var ADD_IN_FRONT_DISTANCE:Float = 6.0;

    function createPrimitive(meshId:String):Void {
        if (!canEdit()) return;
        var spot = pointInFrontOfCamera(ADD_IN_FRONT_DISTANCE);
        createPrimitiveAtWorld(meshId, spot.x, spot.y, spot.z);
    }

    /** Hierarchy asset drop: same camera placement as Add, with drop parent. */
    function createPrimitiveInHierarchy(meshId:String, parentId:Int):Void {
        if (!canEdit()) return;
        var spot = pointInFrontOfCamera(ADD_IN_FRONT_DISTANCE);
        createPrimitiveAtWorld(meshId, spot.x, spot.y, spot.z, parentId);
    }

    function createEmptyObjectInFront():Void {
        if (!canEdit()) return;
        var spot = pointInFrontOfCamera(ADD_IN_FRONT_DISTANCE);
        var limit = WorldBounds.HALF_EXTENT - 0.5;
        var name = "GameObject";
        var transform = new EditorTransform(
            Math.max(-limit, Math.min(limit, spot.x)),
            Math.max(-limit, Math.min(limit, spot.y)),
            Math.max(-limit, Math.min(limit, spot.z)));
        var created = editorSession.createObject(name, transform, -1, []);
        logActivity("scene: created " + created.name);
    }

    /** A point directly along the viewport camera's view direction. */
    function pointInFrontOfCamera(distance:Float):{ x:Float, y:Float, z:Float } {
        var camera = s3d.camera;
        var dx = camera.target.x - camera.pos.x;
        var dy = camera.target.y - camera.pos.y;
        var dz = camera.target.z - camera.pos.z;
        var length = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (length <= 0.0001) {
            return { x: camera.pos.x, y: camera.pos.y, z: camera.pos.z - distance };
        }
        return {
            x: camera.pos.x + dx / length * distance,
            y: camera.pos.y + dy / length * distance,
            z: camera.pos.z + dz / length * distance
        };
    }

    // ------------------------------------------------------------------
    // Asset drops into the 3D viewport
    // ------------------------------------------------------------------

    /** Register the viewport as a drop target for engine mesh/material drags. */
    function registerViewportDropTargets():Void {
        viewportMeshDropTarget = new AssetDropTarget(AssetType.MeshAsset, s2d,
            viewportDropRect, function(active) {
                if (active) viewportDragKind |= 1;
                else {
                    viewportDragKind &= ~1;
                    if (viewportDragKind == 0) clearViewportDropHover();
                }
            }, function(payload) {
                var point = viewportLocalMouse();
                if (point != null) {
                    createPrimitiveAtViewport(payload.assetId, point.x, point.y);
                }
                clearViewportDropHover();
            });
        viewportMeshDropTarget.hideGhostOnHover = true;
        AssetDragSession.add(viewportMeshDropTarget);

        viewportMaterialDropTarget = new AssetDropTarget(AssetType.MaterialAsset, s2d,
            viewportDropRect, function(active) {
                if (active) viewportDragKind |= 2;
                else {
                    viewportDragKind &= ~2;
                    if (viewportDragKind == 0) clearViewportDropHover();
                }
            }, function(payload) {
                applyViewportMaterialDrop(payload.assetId);
                clearViewportDropHover();
            });
        viewportMaterialDropTarget.hideGhostOnHover = true;
        AssetDragSession.add(viewportMaterialDropTarget);
    }

    function viewportDropRect():AssetDropRect {
        var rect = boltUI.getViewportRect();
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    }

    /** Cursor in viewport-local coordinates, or null when outside the viewport. */
    function currentDragPointer():{x:Float, y:Float} {
        var p = boltspark.ui.UiContext.dragPointerOverride;
        return p != null ? {x: p.x, y: p.y}
            : {x: nativeWindow.mouseX, y: nativeWindow.mouseY};
    }

    function viewportLocalMouse():Null<{ x:Float, y:Float }> {
        var rect = boltUI.getViewportRect();
        var pointer = currentDragPointer();
        var mouseX = pointer.x;
        var mouseY = pointer.y;
        if (mouseX < rect.x || mouseX >= rect.x + rect.width
                || mouseY < rect.y || mouseY >= rect.y + rect.height) return null;
        return { x: mouseX - rect.x, y: mouseY - rect.y };
    }

    /** Nearest scene object under a viewport point, with its material slot. */
    function pickViewportObject(viewX:Float, viewY:Float):{
            object:Null<SceneObject>, distance:Float, materialIndex:Int } {
        var ray = viewportRay(viewX, viewY);
        var nearestDistance = Math.POSITIVE_INFINITY;
        var nearestObject:Null<SceneObject> = null;
        for (sceneObject in sceneObjects) {
            for (renderMesh in sceneObject.allRenderMeshes()) {
                var distance = MeshPicking.rayIntersection(renderMesh, ray);
                if (distance >= 0 && distance < nearestDistance) {
                    nearestDistance = distance;
                    nearestObject = sceneObject;
                }
            }
        }
        // Built-in primitives have a single material group (index 0). Imported
        // meshes can report the intersected group here once they exist.
        return {
            object: nearestObject,
            distance: nearestDistance,
            materialIndex: 0
        };
    }

    function updateViewportDropHover():Void {
        if (viewportDragKind == 0) {
            clearViewportDropHover();
            return;
        }
        var point = viewportLocalMouse();
        if (point == null) {
            clearViewportDropHover();
            return;
        }
        var pick = pickViewportObject(point.x, point.y);
        viewportHoverObject = pick.object;
        viewportHoverMaterialIndex = pick.materialIndex;
        if (viewportDropOutline != null) {
            viewportDropOutline.clear();
            // A mesh drag places a new object at the cursor; there is no target
            // to highlight. Only material drags overwrite an existing object.
            var materialDrag = (viewportDragKind & 2) != 0;
            if (pick.object != null && materialDrag) {
                viewportDropOutline.lineStyle(2.0, Theme.ACCENT_HOVER, 1);
                for (renderMesh in pick.object.allRenderMeshes()) {
                    drawSelectionEdges(viewportDropOutline, renderMesh);
                }
            }
            viewportDropOutlineDrawn = pick.object != null && materialDrag;
        }
        // The drag label is owned by updateDragLabel() so it follows the
        // pointer anywhere in the editor, not just inside the viewport.
    }

    /**
     * The label lives in a single always-on-top overlay HWND managed by
     * FloatWindowManager, so it stays above docked panels and native floats
     * alike. The old viewport hint would duplicate it and sit under floats.
     */
    function updateDragLabel():Void {
        boltUI.hideViewportDropHint();
    }

    function clearViewportDropHover():Void {
        if (viewportHoverObject == null && !viewportDropOutlineDrawn) {
            boltUI.hideViewportDropHint();
            return;
        }
        viewportHoverObject = null;
        viewportHoverMaterialIndex = 0;
        viewportDropOutlineDrawn = false;
        if (viewportDropOutline != null) viewportDropOutline.clear();
        boltUI.hideViewportDropHint();
    }

    /** Apply a material drag onto the material slot under the cursor. */
    function applyViewportMaterialDrop(assetId:String):Void {
        var material = Material.find(assetId);
        if (material == null) {
            boltUI.log("viewport: unknown material " + assetId);
            return;
        }
        var point = viewportLocalMouse();
        if (point == null) return;
        var pick = pickViewportObject(point.x, point.y);
        if (pick.object == null) {
            boltUI.log("viewport: drop a material onto an object");
            return;
        }
        var object = editorSession.findObject(pick.object.id);
        if (object == null) return;
        for (component in object.components) {
            var renderer = Std.downcast(component, MeshRenderer);
            if (renderer == null || renderer.getMaterial(pick.materialIndex) == null) continue;
            var propertyId = MeshRenderer.materialPropertyId(pick.materialIndex);
            var before = renderer.inspectorAssetId(propertyId);
            renderer.setMaterial(pick.materialIndex, material);
            var after = renderer.inspectorAssetId(propertyId);
            var label = 'Assign ${material.name} to ${object.name} ${propertyId}';
            if (!editorSession.commitMeshAssetAssignments([object.id], propertyId,
                    [before], [after], label)) {
                editorSession.componentEdited(object.id);
            }
            refreshSelectionInspector();
            logActivity('viewport: ${pick.object.name} material ${pick.materialIndex} = '
                + material.name);
            return;
        }
        boltUI.log("viewport: hovered object has no MeshRenderer");
    }

    function createPrimitiveAtViewport(meshId:String, viewX:Float,
            viewY:Float):Void {
        if (!canEdit()) return;
        var ray = viewportRay(viewX, viewY);
        var x = editorSession.nextRuntimeId * 1.5;
        var z = 0.0;
        if (Math.abs(ray.ly) > 0.0001) {
            var distance = -ray.py / ray.ly;
            if (distance >= 0) {
                x = ray.px + ray.lx * distance;
                z = ray.pz + ray.lz * distance;
            }
        }
        createPrimitiveAtPosition(meshId, x, z);
    }

    function createPrimitiveAtPosition(meshId:String, x:Float, z:Float):Void {
        if (!canEdit()) return;
        createPrimitiveAtWorld(meshId, x, 0, z);
    }

    function createPrimitiveAtWorld(meshId:String, x:Float, y:Float,
            z:Float, ?parentId:Int):Void {
        if (!canEdit()) return;
        var name = primitiveName(meshId);
        // Newly added objects keep identity rotation/scale; constrain their
        // pivot before they enter session history.
        var pivotLimit = WorldBounds.HALF_EXTENT - 0.5;
        var transform = new EditorTransform(
            Math.max(-pivotLimit, Math.min(pivotLimit, x)),
            Math.max(-pivotLimit, Math.min(pivotLimit, y)),
            Math.max(-pivotLimit, Math.min(pivotLimit, z)));
        var created = editorSession.createObject(name, transform,
            parentId == null ? -1 : parentId,
            PrimitiveGameObjects.primitiveComponents(meshId));
        logActivity("scene: created " + created.name);
    }

    function createHierarchyObject(parentId:Int, empty:Bool):Void {
        if (!canEdit()) return;
        // Non-empty children go through createHierarchyPrimitive; this only
        // serves the "Empty Object" menu entry now.
        editorSession.createObject("GameObject", new EditorTransform(),
            parentId, []);
    }

    function createHierarchyPrimitive(parentId:Int, meshId:String):Void {
        if (!canEdit()) return;
        var name = primitiveName(meshId);
        editorSession.createObject(name, new EditorTransform(), parentId,
            PrimitiveGameObjects.primitiveComponents(meshId));
    }

    function deleteSceneObjects(ids:Array<Int>):Void {
        if (!canEdit()) return;
        var deletedNames = editorSession.deleteObjects(ids);
        if (deletedNames.length == 0) {
            boltUI.log("scene: selected objects no longer exist");
            editorSession.selectObject(-1);
            return;
        }
        for (name in deletedNames) logActivity("scene: deleted " + name);
    }

    function selectSceneObjects(ids:Array<Int>, primaryId:Int):Void {
        if (!canEdit()) return;
        clearInspectorTransformEdit();
        editorSession.selectObjects(ids, primaryId);
    }

    /** Push the selection's full inspector state through BoltUI. */
    function refreshSelectionInspector():Void {
        var selected = getSelectedObject();
        if (selected == null) {
            boltUI.setSelectedObjects([], -1, "", [],
                ComponentRegistry.addableTypes());
            return;
        }
        var ids = editorSession.selectedObjectIds;
        if (ids.length <= 1) {
            var model = editorSession.findObject(selected.id);
            if (model == null) return;
            var components = [for (index in 0...model.components.length)
                model.components[index].inspectorData(index)];
            overrideInspectorRotation(components, selected);
            boltUI.setSelectedObjects(ids, selected.id,
                selected.name, components, ComponentRegistry.addableTypes(),
                model.enabled);
            return;
        }
        // Build an Inspector projection shared by every selected object:
        // common components/properties only, with per-axis mixed-value flags.
        var allData:Array<Array<ComponentInspectorData>> = [];
        var primaryData:Null<Array<ComponentInspectorData>> = null;
        var primaryEnabled = true;
        for (id in ids) {
            var model = editorSession.findObject(id);
            if (model == null) continue;
            var sceneObject = findSceneObject(id);
            var data = [for (index in 0...model.components.length)
                model.components[index].inspectorData(index)];
            if (sceneObject != null) overrideInspectorRotation(data, sceneObject);
            allData.push(data);
            if (id == editorSession.selectedObjectId) {
                primaryData = data;
                primaryEnabled = model.enabled;
            }
        }
        if (primaryData == null) {
            boltUI.setSelectedObjects([], -1, "", [], ComponentRegistry.addableTypes());
            return;
        }
        var merged = MultiInspectorData.build(primaryData, allData);
        boltUI.setSelectedObjects(ids, editorSession.selectedObjectId,
            '${ids.length} objects selected', merged,
            ComponentRegistry.addableTypes(), primaryEnabled);
    }

    /** Replace authored rotation hints with the live normalized Rotator. */
    function overrideInspectorRotation(components:Array<ComponentInspectorData>,
            sceneObject:SceneObject):Void {
        var model = editorSession.findObject(sceneObject.id);
        if (model == null) return;
        var rotation = rotationDegrees(sceneObject);
        var transformIndex = model.components.indexOf(model.transform);
        if (transformIndex < 0 || transformIndex >= components.length) return;
        for (property in components[transformIndex].properties) {
            if (property.id != "rotation" || property.numberValues.length < 3) continue;
            property.numberValues[0] = rotation.x;
            property.numberValues[1] = rotation.y;
            property.numberValues[2] = rotation.z;
        }
    }

    function getSelectedObject():Null<SceneObject> {
        return findSceneObject(editorSession.selectedObjectId);
    }

    /** Render views for the whole selection, in selection order. */
    function selectedSceneObjects():Array<SceneObject> {
        var result:Array<SceneObject> = [];
        for (id in editorSession.selectedObjectIds) {
            var sceneObject = findSceneObject(id);
            if (sceneObject != null) result.push(sceneObject);
        }
        return result;
    }

    /**
     * World transform used to place the shared gizmo. A single selection keeps
     * the object's own transform; a multi-selection uses the average world
     * position with the primary object's orientation and scale, so a shared
     * move/rotate/scale gesture pivots around the selection's center.
     */
    function selectionPivotWorld():Null<EditorTransform> {
        var primary = editorSession.findObject(editorSession.selectedObjectId);
        if (primary == null) return null;
        var ids = editorSession.selectedObjectIds;
        if (ids.length <= 1) return primary.worldTransform.clone();
        var count = 0;
        var x = 0.0;
        var y = 0.0;
        var z = 0.0;
        for (id in ids) {
            var model = editorSession.findObject(id);
            if (model == null) continue;
            var world = model.worldTransform;
            x += world.positionX;
            y += world.positionY;
            z += world.positionZ;
            count++;
        }
        if (count == 0) return primary.worldTransform.clone();
        var pivot = primary.worldTransform.clone();
        pivot.positionX = x / count;
        pivot.positionY = y / count;
        pivot.positionZ = z / count;
        return pivot;
    }

    /**
     * Live pivot from the renderer transforms, used while an Inspector edit is
     * still in progress (the session model is only updated on history commit).
     */
    /** Live world transform from renderer views, walking up selected parents. */
    function liveWorldFor(view:SceneObject):EditorTransform {
        var local = view.captureTransform();
        var model = editorSession.findObject(view.id);
        var parent = model == null ? null : model.parent;
        if (parent == null) return local;
        var parentView = findSceneObject(parent.id);
        var parentWorld = parentView == null
            ? editorSession.hierarchy.worldTransform(parent)
            : liveWorldFor(parentView);
        return SharedGizmoDelta.worldFromParent(
            local, parentWorld.toMatrix(), local);
    }

    function liveSelectionPivotWorld():Null<EditorTransform> {
        var primary = getSelectedObject();
        if (primary == null) return null;
        var pivot = liveWorldFor(primary);
        var ids = editorSession.selectedObjectIds;
        if (ids.length <= 1) return pivot;
        var count = 0;
        var x = 0.0;
        var y = 0.0;
        var z = 0.0;
        for (id in ids) {
            var view = findSceneObject(id);
            if (view == null) continue;
            var world = liveWorldFor(view);
            x += world.positionX;
            y += world.positionY;
            z += world.positionZ;
            count++;
        }
        if (count > 0) {
            pivot.positionX = x / count;
            pivot.positionY = y / count;
            pivot.positionZ = z / count;
        }
        return pivot;
    }

    /** Move the attached gizmo with live Inspector edits, before commit. */
    function refreshGizmoFromSelection():Void {
        if (gizmoDragging) return;
        var pivot = liveSelectionPivotWorld();
        if (pivot == null) {
            gizmo.attach(null);
            return;
        }
        applyGizmoProxy(pivot);
    }

    function attachGizmo(selected:Null<SceneObject>):Void {
        if (selected == null) {
            gizmo.attach(null);
            return;
        }
        var pivot = selectionPivotWorld();
        if (pivot == null) {
            gizmo.attach(null);
            return;
        }
        applyGizmoProxy(pivot);
        gizmo.attach(gizmoProxy);
    }

    function applyGizmoProxy(transform:EditorTransform):Void {
        gizmoProxy.defaultTransform = null;
        gizmoProxy.setPosition(transform.positionX,
            transform.positionY, transform.positionZ);
        gizmoProxy.setRotationQuat(new h3d.Quat(transform.rotationX,
            transform.rotationY, transform.rotationZ, transform.rotationW));
        gizmoProxy.scaleX = transform.scaleX;
        gizmoProxy.scaleY = transform.scaleY;
        gizmoProxy.scaleZ = transform.scaleZ;
    }

    function worldTransformForLocal(model:EditorObject,
            local:EditorTransform):EditorTransform {
        var matrix = model.parent == null
            ? local.toMatrix()
            : editorSession.hierarchy.worldMatrix(model.parent)
                .multiplied(local.toMatrix());
        return EditorTransform.fromMatrix(matrix, local);
    }

    function findSceneObject(id:Int):Null<SceneObject> {
        return sceneObjectsById.get(id);
    }

    function refreshHierarchy():Void {
        var entries:Array<HierarchyEntry> = [];
        var depths:Map<Int, Int> = [];
        var siblingCounts:Map<Int, Int> = [];
        for (object in editorSession.hierarchy.flatten()) {
            var parentId = object.parent == null ? -1 : object.parent.id;
            var depth = parentId < 0 ? 0 : depths.get(parentId) + 1;
            var siblingIndex = siblingCounts.exists(parentId)
                ? siblingCounts.get(parentId) : 0;
            siblingCounts.set(parentId, siblingIndex + 1);
            depths.set(object.id, depth);
            entries.push(new HierarchyEntry(object.id, object.name,
                object.persistentId, parentId,
                depth, object.children.length > 0,
                Mesh3D.is(object),
                object.children.length, siblingIndex, object.objectType,
                object.visible, object.enabled));
        }
        boltUI.setHierarchyEntries(entries);
    }

    function undoEditorCommand():Void {
        if (!canEdit()) return;
        if (gizmoDragging || inspectorEditObjectId >= 0
                || settingsEditPropertyId != "") return;
        var label = editorSession.history.undoLabel;
        if (!editorSession.undo()) return;
        logActivity('command: undo ${label}');
        printHistoryTransform("undo", label);
    }

    function redoEditorCommand():Void {
        if (!canEdit()) return;
        if (gizmoDragging || inspectorEditObjectId >= 0
                || settingsEditPropertyId != "") return;
        var label = editorSession.history.redoLabel;
        if (!editorSession.redo()) return;
        logActivity('command: redo ${label}');
        printHistoryTransform("redo", label);
    }

    /** Session edits mark the project dirty; loads and saves do not. */
    function onEditorSessionChanged():Void {
        synchronizeEditorSession();
        if (!suppressProjectDirty) projectSession.syncDirty(editorSession);
    }

    function confirmDiscardChanges():Bool {
        if (projectSession == null || !projectSession.dirty) return true;
        // Automated probes drive WM_CLOSE and cannot answer a modal OS dialog.
        // They supply a scratch answer file so cancel and confirm are both
        // exercised; a missing answer defaults to discarding the scratch state.
        if (inputProbeMode) {
            var answerFile = Sys.getEnv("BOLTSPARK_PROBE_CLOSE_ANSWER");
            var answer = "";
            if (answerFile != null && sys.FileSystem.exists(answerFile)) {
                answer = StringTools.trim(sys.io.File.getContent(answerFile))
                    .toLowerCase();
            }
            printActivity('[probe] close prompt answer=${answer == "" ? "yes" : answer}');
            return answer != "no";
        }
        #if hl
        // DialogFlags.YesNo is flag bit 1 << 0.
        return hl.UI.dialog("Unsaved changes",
            "The current project has unsaved changes. Discard them and continue?",
            haxe.EnumFlags.ofInt(1));
        #else
        return true;
        #end
    }

    function withNativeDialogTimeout<T>(open:Void->Null<T>):Null<T> {
        #if hl
        var previous = hxd.System.allowTimeout;
        hxd.System.allowTimeout = false;
        var result = open();
        hxd.System.allowTimeout = previous;
        return result;
        #else
        return null;
        #end
    }

    /**
     * Probe replacement for the modal OS picker. The path is supplied through
     * the environment so a native probe can exercise the full menu -> command
     * -> DocumentStore path without a dialog it cannot drive. An unset or empty
     * value means Cancel; "cancel" is also accepted for explicit test cases.
     */
    function probeFileChoice(kind:String, title:String):Null<String> {
        var variable = kind == "save"
            ? "BOLTSPARK_PROBE_SAVE_FILE"
            : "BOLTSPARK_PROBE_OPEN_FILE";
        var path = Sys.getEnv(variable);
        if (path == null || path == "") path = Sys.getEnv("BOLTSPARK_PROBE_FILE");
        if (path == "cancel") path = null;
        printActivity('[probe] file dialog ${kind} title="${title}"'
            + ' choice=${path == null ? "cancel" : path}');
        return path;
    }

    function pickOpenFile(title:String, extension:String, label:String):Null<String> {
        if (inputProbeMode) return probeFileChoice("open", title);
        return withNativeDialogTimeout(function() {
            return hl.UI.loadFile({
                title: title,
                filters: [{ name: label, exts: [extension] }]
            });
        });
    }

    /**
     * Texture imports use a real multi-select native picker. `hl.UI.loadFile`
     * returns a single path and has no multi-select flag, so the project-local
     * `multifile.hdll` drives the same Windows common item dialog with
     * FOS_ALLOWMULTISELECT. Probes substitute paths through the environment.
     */
    function pickOpenTextureFiles():Null<Array<String>> {
        var exts = AssetTypeRegistry.TEXTURE_EXTENSIONS;
        var spec = [for (ext in exts) "*." + ext].join(";");
        printActivity('[probe] import picker exts=${exts.join(",")}'
            + ' name="${AssetTypeRegistry.TEXTURE_FILTER_LABEL}" spec=${spec}');
        if (inputProbeMode) {
            // Numbered answer files let one probe drive several imports; a
            // child process cannot see env changes made after launch.
            if (pickerProbeDir != "") {
                var instruction = pickerProbeDir + "/pick-" + pickerProbeNext + ".txt";
                if (sys.FileSystem.exists(instruction)) {
                    var answer = StringTools.trim(sys.io.File.getContent(instruction));
                    sys.FileSystem.deleteFile(instruction);
                    pickerProbeNext++;
                    var files:Array<String> = [];
                    for (entry in answer.split("|")) {
                        var trimmed = StringTools.trim(entry);
                        if (trimmed.length > 0) files.push(trimmed);
                    }
                    printActivity('[probe] file dialog open title="Import Texture"'
                        + ' choice=${files.join("|")}');
                    return files.length == 0 ? null : files;
                }
            }
            var many = Sys.getEnv("BOLTSPARK_PROBE_OPEN_FILES");
            if (many != null && StringTools.trim(many).length > 0) {
                var paths:Array<String> = [];
                for (entry in many.split(";")) {
                    var trimmed = StringTools.trim(entry);
                    if (trimmed.length > 0) paths.push(trimmed);
                }
                printActivity('[probe] file dialog open title="Import Texture"'
                    + ' choice=${paths.join("|")}');
                return paths.length == 0 ? null : paths;
            }
            var single = probeFileChoice("open", "Import Texture");
            return single == null ? null : [single];
        }
        return withNativeDialogTimeout(function() {
            return NativeMultiFilePicker.pickImages("Import Texture",
                AssetTypeRegistry.TEXTURE_FILTER_LABEL, spec);
        });
    }

    function pickSaveFile(title:String, defaultName:String, extension:String,
            label:String):Null<String> {
        if (inputProbeMode) return probeFileChoice("save", title);
        return withNativeDialogTimeout(function() {
            return hl.UI.saveFile({
                title: title,
                fileName: defaultName,
                filters: [{ name: label, exts: [extension] }]
            });
        });
    }

    /** Replace the Heaps views and editor session with the loaded scene. */
    function reloadEditorSession():Void {
        if (playSession != null) stopScene();
        suppressProjectDirty = true;
        if (editorSession != null) editorSession.destroy();
        editorSession = projectSession.createSession();
        editorSession.onChanged = onEditorSessionChanged;
        synchronizeEditorSession();
        // The browser is docked and visible by default; refresh it here so a
        // project opened at startup is listed without waiting for a tab click.
        boltUI.refreshAssetBrowser();
        printActivity('[probe] scene loaded entities=${editorSession.objects.length}');
        suppressProjectDirty = false;
    }

    function reportProjectError(action:String, error:Dynamic):Void {
        var message = Std.string(error);
        boltUI.log('${action} failed: ${message}');
        Sys.println('[project] ${action} failed: ${message}');
    }

    function openAsset(source:String):Void {
        // Textures are loadable in the browser (so they can be previewed and
        if (projectSession.isMaterialPath(source)) {
            openMaterialAsset(source);
            return;
        }
        if (!projectSession.isScenePath(source)) {
            boltUI.log('asset: ${source} has no editor view');
            return;
        }
        if (!confirmDiscardChanges()) return;
        try {
            projectSession.openSceneSource(source);
            reloadEditorSession();
            boltUI.log('asset: opened ${projectSession.scenePath}');
        } catch (e:Dynamic) reportProjectError('open asset', e);
    }

    function openMaterialAsset(source:String):Void {
        try {
            var document = projectSession.loadMaterialDocument(source);
            boltUI.openMaterialEditor(source, document);
            printActivity('[material] open source=${source}');
            boltUI.log('asset: opened material ${document.name}');
        } catch (e:Dynamic) {
            reportProjectError('open material', e);
        }
    }

    function createMaterialAsset():Void {
        try {
            var source = projectSession.newMaterial("New Material");
            boltUI.refreshAssetBrowser();
            openMaterialAsset(source);
            boltUI.log('asset: created ${source}');
        } catch (e:Dynamic) {
            reportProjectError('create material', e);
        }
    }

    function saveMaterialAsset(source:String, document:MaterialDocument):Void {
        try {
            projectSession.saveMaterialDocument(source, document);
            boltUI.refreshAssetBrowser();
            printActivity('[material] saved source=${source} name=${document.name}');
            boltUI.log('material: saved ${document.name}');
        } catch (e:Dynamic) {
            reportProjectError('save material', e);
        }
    }

    function deleteMaterialAsset(source:String):Void {
        if (!confirmDestructive('Delete Material',
                'Delete material ${source}? This cannot be undone.')) return;
        try {
            projectSession.deleteMaterial(source);
            boltUI.clearMaterialEditor();
            boltUI.refreshAssetBrowser();
            boltUI.log('material: deleted ${source}');
        } catch (e:Dynamic) {
            reportProjectError('delete material', e);
        }
    }

    function createAssetScene(folder:String, name:String):Void {
        if (!confirmDiscardChanges()) return;
        try {
            projectSession.newScene(name.length == 0 ? "New Scene" : name, folder);
            projectSession.persistSceneDocument();
            reloadEditorSession();
            boltUI.log('asset: created ${projectSession.sceneSource}');
        } catch (e:Dynamic) reportProjectError('create asset', e);
    }

    function renameAsset(source:String, name:String):Void {
        try {
            var target = projectSession.renameAnyAsset(source, name);
            if (projectSession.isScenePath(source)) reloadEditorSession();
            else boltUI.refreshAssetBrowser();
            boltUI.log('asset: renamed ${source} to ${target}');
        } catch (e:Dynamic) reportProjectError('rename asset', e);
    }

    function deleteAsset(source:String):Void {
        if (!confirmDestructive("Delete asset", 'Delete ${source}? This cannot be undone.')) return;
        try {
            projectSession.deleteAnyAsset(source);
            if (projectSession.isScenePath(source)) reloadEditorSession();
            else boltUI.refreshAssetBrowser();
            boltUI.log('asset: deleted ${source}');
        } catch (e:Dynamic) reportProjectError('delete asset', e);
    }

    /**
     * Native Import command. The picker is the only modal OS interaction;
     * copying, registration, and persistence go through ProjectSession.
     */
    function importAssets(folder:String):Void {
        if (!canEdit()) return;
        var picked = pickOpenTextureFiles();
        if (picked == null || picked.length == 0) return;
        importExternalFiles(picked, folder);
    }

    /** Shared write path for the Import dialog and Explorer drops. */
    function importExternalFiles(paths:Array<String>, folder:String):Void {
        if (!canEdit()) return;
        if (paths == null || paths.length == 0) return;
        try {
            var imported = projectSession.importAssets(paths, folder);
            boltUI.refreshAssetBrowser();
            boltUI.log('asset: imported ${imported.length} texture(s) to ${folder}: ${imported.join(", ")}');
            printActivity('[probe] import completed count=${imported.length} folder=${folder}');
        } catch (e:Dynamic) reportProjectError('import asset', e);
    }

    /**
     * Probe-only delivery for Explorer drops. `BOLTSPARK_PROBE_DROP_DIR` points
     * at a directory where a probe writes `drop-N.txt` containing
     * `clientX;clientY|fullPath|fullPath...`. Each file is consumed once and
     * routed through `handleDroppedPaths`, so the import, folder placement, and
     * Play-mode guard are the real production code, not test-only stubs.
     */
    function pollDropProbe():Void {
        if (!sys.FileSystem.exists(dropProbeDir)) return;
        var instruction = dropProbeDir + "/drop-" + dropProbeNext + ".txt";
        if (!sys.FileSystem.exists(instruction)) return;
        var content = StringTools.trim(sys.io.File.getContent(instruction));
        sys.FileSystem.deleteFile(instruction);
        dropProbeNext++;
        var fields = content.split("|");
        var coords = fields[0].split(";");
        var x = Std.parseInt(StringTools.trim(coords[0]));
        var y = Std.parseInt(StringTools.trim(coords[1]));
        if (x == null) x = 0;
        if (y == null) y = 0;
        var paths:Array<String> = [];
        for (index in 1...fields.length) {
            var path = StringTools.trim(fields[index]);
            if (path.length > 0) paths.push(path);
        }
        printActivity('[probe] drop hook index=${dropProbeNext - 1}');
        handleDroppedPaths(paths, x, y);
    }

    /**
     * Windows Explorer drop handler. `dropX/dropY` are window-client
     * coordinates from hldx; the browser maps them to a folder so a drop lands
     * where the user aimed it. Generic files are ignored for now (only the
     * registered texture formats are real imports).
     */
    function onFilesDroppedFromShell(event:hxd.DropFileEvent):Void {
        var paths:Array<String> = [];
        for (file in event.files) paths.push(file.file);
        handleDroppedPaths(paths, event.dropX, event.dropY);
    }

    function handleDroppedPaths(paths:Array<String>, x:Int, y:Int):Void {
        printActivity('[probe] os file drop count=${paths.length} x=${x} y=${y}');
        if (!canEdit()) {
            printActivity('[probe] os file drop rejected=play-mode');
            boltUI.log('External file drops are disabled while playing.');
            return;
        }
        var images = paths.filter(AssetTypeRegistry.isTextureFile);
        if (images.length != paths.length) {
            printActivity('[probe] os file drop skipped=${paths.length - images.length}');
        }
        if (images.length == 0) return;
        var folder = boltUI.folderAtWindowPoint(x, y);
        if (folder != null && StringTools.startsWith(folder, EngineAssetCatalog.FOLDER)) {
            folder = null;
        }
        var target = folder == null ? "" : folder;
        printActivity('[probe] os file drop folder=${target}');
        importExternalFiles(images, target);
    }

    /**
     * Explorer drop on a floating Asset Browser. The float already mapped the
     * drop point to one of its own folders, so only import validation is left.
     */
    function handleFloatDroppedPaths(paths:Array<String>, folder:String):Void {
        printActivity('[probe] float file drop count=${paths.length} folder=${folder}');
        if (!canEdit()) {
            printActivity('[probe] float file drop rejected=play-mode');
            boltUI.log('External file drops are disabled while playing.');
            return;
        }
        var images = paths.filter(AssetTypeRegistry.isTextureFile);
        if (images.length != paths.length) {
            printActivity('[probe] float file drop skipped=${paths.length - images.length}');
        }
        if (images.length == 0) return;
        importExternalFiles(images, folder);
    }

    function createAssetFolder(parent:String):String {
        try {
            var folder = projectSession.createFolder(parent, "New Folder");
            boltUI.refreshAssetBrowser();
            boltUI.log('folder: created ${folder}');
            return folder;
        } catch (e:Dynamic) {
            reportProjectError('create folder', e);
            return null;
        }
    }

    function renameAssetFolder(source:String, name:String):String {
        try {
            var target = projectSession.renameFolder(source, name);
            boltUI.refreshAssetBrowser();
            boltUI.log('folder: renamed ${source} to ${target}');
            return target;
        } catch (e:Dynamic) {
            reportProjectError('rename folder', e);
            return null;
        }
    }

    function moveAsset(source:String, folder:String):Void {
        try {
            var moved = projectSession.moveAnyAsset(source, folder);
            if (projectSession.isScenePath(source)) reloadEditorSession();
            else boltUI.refreshAssetBrowser();
            boltUI.log('asset: moved ${source} to ${moved}');
        } catch (e:Dynamic) reportProjectError('move asset', e);
    }

    function copyAsset(source:String, folder:String):Void {
        try {
            var destination = projectSession.copyAnyAsset(source, folder);
            boltUI.refreshAssetBrowser();
            boltUI.log('asset: copied ${source} to ${destination}');
        } catch (e:Dynamic) reportProjectError('copy asset', e);
    }

    function deleteAssets(sources:Array<String>):Void {
        if (sources.length == 0) return;
        var label = sources.length == 1 ? sources[0] : '${sources.length} assets';
        if (!confirmDestructive("Delete assets", 'Delete ${label}? This cannot be undone.')) return;
        var scenesChanged = false;
        try {
            for (source in sources) {
                if (projectSession.isScenePath(source)) scenesChanged = true;
                projectSession.deleteAnyAsset(source);
            }
            if (scenesChanged) reloadEditorSession();
            else boltUI.refreshAssetBrowser();
            boltUI.log('asset: deleted ${sources.length} asset(s)');
        } catch (e:Dynamic) reportProjectError('delete assets', e);
    }

    function duplicateAsset(source:String):Void {
        try {
            var destination = projectSession.duplicateAnyAsset(source);
            boltUI.refreshAssetBrowser();
            boltUI.log('asset: duplicated ${source} to ${destination}');
        } catch (e:Dynamic) reportProjectError('duplicate asset', e);
    }

    function deleteAssetFolder(folder:String, recursive:Bool):Void {
        // Fail visibly before confirmation when the project rule would reject
        // it; otherwise the operation looks like it silently did nothing.
        if (!projectSession.canDeleteFolder(folder)) {
            printActivity('[probe] delete folder rejected=${folder}');
            boltUI.log('folder: cannot delete ${folder} - a project must keep at least one scene');
            #if hl
            if (!inputProbeMode) {
                hl.UI.dialog("Cannot delete folder",
                    "A project must keep at least one scene. Move the scene out first.",
                    haxe.EnumFlags.ofInt(0));
            }
            #end
            return;
        }
        if (!confirmDestructive("Delete folder",
                'Delete folder ${folder} and everything inside it?')) return;
        try {
            projectSession.deleteFolder(folder, recursive);
            reloadEditorSession();
            boltUI.log('folder: deleted ${folder}');
        } catch (e:Dynamic) reportProjectError('delete folder', e);
    }

    function moveAssetFolder(source:String, parent:String):Void {
        try {
            var target = projectSession.moveFolder(source, parent);
            reloadEditorSession();
            boltUI.log('folder: moved ${source} to ${target}');
        } catch (e:Dynamic) reportProjectError('move folder', e);
    }

    function revealAsset(source:String):Void {
        if (!requireProject("reveal files in Explorer")) return;
        try {
            // The root/"All" folder has an empty relative path; reveal the
            // project's asset root instead of feeding "" to ProjectPath.
            var absolute = isEmptyAssetPath(source)
                ? projectSession.assetRootPath()
                : projectSession.absoluteAssetPath(source);
            printActivity('[probe] reveal path=${absolute}');
            #if hl
            if (!inputProbeMode) {
                // ProjectSession paths use haxe.io.Path.join, which emits "/"
                // on HashLink. explorer.exe /select silently ignores the switch
                // for forward-slash paths and opens a default view instead.
                var nativePath = StringTools.replace(absolute, "/", "\\");
                printActivity('[probe] reveal native=${nativePath}');
                // `start` detaches from the shell immediately (~0.03s). Calling
                // explorer.exe directly makes Sys.command wait on the shell
                // process, which is what causes the long visible stall.
                Sys.command('cmd /c start "" explorer.exe /select,"' + nativePath + '"');
            }
            #end
        } catch (e:Dynamic) reportProjectError('reveal asset', e);
    }

    function copyAssetPath(source:String):Void {
        if (!requireProject("copy an asset path")) return;
        try {
            var value = isEmptyAssetPath(source)
                ? projectSession.assetRootPath()
                : ProjectPath.normalizeRelative(source);
            printActivity('[probe] copy asset path=${value}');
            #if hl
            // Native Windows clipboard from the bundled ui.hdll; no PowerShell
            // process, no quoting, and no editor stall.
            if (!inputProbeMode && !hl.UI.setClipboardText(value)) {
                boltUI.log('asset: clipboard unavailable for ${value}');
            }
            #end
        } catch (e:Dynamic) reportProjectError('copy asset path', e);
    }

    /**
     * Explorer/clipboard actions only make sense inside a real project. With an
     * untitled session, ask the user to create one instead of revealing the
     * process working directory (which is not a project root).
     */
    function requireProject(action:String):Bool {
        if (projectSession.projectPath != "") return true;
        printActivity('[probe] project required for ${action}');
        if (inputProbeMode) {
            fileNewProject();
            return false;
        }
        #if hl
        // DialogFlags.YesNo is flag bit 1 << 0.
        var accepted = hl.UI.dialog("No project",
            'Create a project before you ${action}?', haxe.EnumFlags.ofInt(1));
        if (accepted) fileNewProject();
        #end
        return false;
    }

    static function isEmptyAssetPath(source:String):Bool {
        return source == null || StringTools.trim(source).length == 0;
    }

    function confirmDestructive(title:String, message:String):Bool {
        if (inputProbeMode) {
            printActivity('[probe] confirm ${title}=yes');
            return true;
        }
        #if hl
        // DialogFlags.YesNo is flag bit 1 << 0.
        return hl.UI.dialog(title, message, haxe.EnumFlags.ofInt(1));
        #else
        return true;
        #end
    }

    function fileNewProject():Void {
        var path = pickSaveFile("Create Project", "Untitled Project.boltproject",
            ProjectSession.PROJECT_EXT, "Boltspark Project");
        if (path == null) return;
        if (!confirmDiscardChanges()) return;
        try {
            var info = new haxe.io.Path(path);
            projectSession.createProject(path, info.file);
            TextureCache.clear();
            reloadEditorSession();
            boltUI.log('project: created ${projectSession.projectPath}');
        } catch (e:Dynamic) reportProjectError('create project', e);
    }

    function fileOpenProject():Void {
        var path = pickOpenFile("Open Project", ProjectSession.PROJECT_EXT,
            "Boltspark Project");
        if (path == null) return;
        if (!confirmDiscardChanges()) return;
        try {
            projectSession.openProject(path);
            TextureCache.clear();
            reloadEditorSession();
            boltUI.log('project: opened ${projectSession.projectPath}');
        } catch (e:Dynamic) reportProjectError('open project', e);
    }

    function fileSaveProject():Void {
        if (projectSession.projectPath == "") {
            fileSaveProjectAs();
            return;
        }
        try {
            projectSession.save(editorSession);
            boltUI.log('project: saved ${projectSession.projectPath}');
        } catch (e:Dynamic) reportProjectError('save project', e);
    }

    function fileSaveProjectAs():Void {
        var path = pickSaveFile("Save Project As",
            projectSession.project.name + "." + ProjectSession.PROJECT_EXT,
            ProjectSession.PROJECT_EXT, "Boltspark Project");
        if (path == null) return;
        try {
            projectSession.saveAs(path, editorSession);
            TextureCache.clear();
            boltUI.refreshAssetBrowser();
            boltUI.log('project: saved ${projectSession.projectPath}');
        } catch (e:Dynamic) reportProjectError('save project as', e);
    }

    function fileSaveScene():Void {
        // A scene only exists on disk inside a project; on an untitled project
        // route the Save Scene command to the project save path instead of
        // dead-ending with a "no scene path" error.
        if (projectSession.scenePath == "") {
            fileSaveProjectAs();
            return;
        }
        try {
            projectSession.saveScene(editorSession);
            boltUI.log('scene: saved ${projectSession.scenePath}');
        } catch (e:Dynamic) reportProjectError('save scene', e);
    }

    function fileSaveAll():Void {
        if (projectSession.projectPath == "") {
            fileSaveProjectAs();
            return;
        }
        try {
            projectSession.save(editorSession);
            boltUI.refreshAssetBrowser();
            boltUI.log('saved all: ${projectSession.projectPath}');
        } catch (e:Dynamic) reportProjectError('save all', e);
    }

    function printHistoryTransform(action:String, label:Null<String>):Void {
        if (!verboseLogging) return;
        var selected = getSelectedObject();
        if (selected == null) {
            printActivity('[history] ${action} label=${label} selection=none');
            return;
        }
        printActivity('[history] ${action} label=${label} object=${selected.name}'
            + ' position=(${round2(selected.mesh.x)}, ${round2(selected.mesh.y)},'
            + ' ${round2(selected.mesh.z)})');
    }

    function setupViewportScene():Void {
        var lightSystem = Std.downcast(s3d.lightSystem, h3d.scene.fwd.LightSystem);
        if (lightSystem != null) {
            lightSystem.ambientLight.set(0.62, 0.65, 0.70);
            lightSystem.perPixelLighting = true;
        }

        var keyLight = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.8, -1.0, -0.55), s3d);
        keyLight.color = new h3d.Vector(0.55, 0.50, 0.44);
        keyLight.enableSpecular = true;
        var rimLight = new h3d.scene.fwd.DirLight(new h3d.Vector(0.65, -0.45, 0.8), s3d);
        rimLight.color = new h3d.Vector(0.10, 0.14, 0.22);
        var fillLight = new h3d.scene.fwd.DirLight(new h3d.Vector(-0.25, -0.2, -1.0), s3d);
        fillLight.color = new h3d.Vector(0.12, 0.14, 0.17);
        var bounceLight = new h3d.scene.fwd.DirLight(new h3d.Vector(1.0, -0.15, 0.25), s3d);
        bounceLight.color = new h3d.Vector(0.10, 0.12, 0.16);

        // The editor grid is NOT part of this scene graph: it renders from
        // its own dedicated h3d.scene.Scene pass (EditorGridRenderer) so it
        // never appears as a scene object, is never serialized, and never
        // participates in picking or inspection.

        selectionOutline = new h3d.scene.Graphics(s3d);
        selectionOutline.name = "SelectionOutline";
        // Keep the line shader in its default screen-space mode so outline
        // thickness is a constant number of pixels at every object scale and
        // camera distance.
        selectionOutline.is3D = false;
        // X-ray outline: disable both depth write and depth test so the
        // selected object's silhouette stays visible through any geometry
        // in front of it, not just through the object's own faces.
        selectionOutline.material.mainPass.depthWrite = false;
        selectionOutline.material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
        selectionOutline.material.mainPass.layer = 10;

        // Accent X-ray outline for the object currently under an asset drag.
        viewportDropOutline = new h3d.scene.Graphics(s3d);
        viewportDropOutline.name = "ViewportDropOutline";
        viewportDropOutline.is3D = false;
        viewportDropOutline.material.mainPass.depthWrite = false;
        viewportDropOutline.material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
        viewportDropOutline.material.mainPass.layer = 11;
    }

    function refreshSelectionOutline():Void {
        if (selectionOutline == null) return;
        selectionOutline.clear();
        selectionOutline.lineStyle(2.0, Theme.SELECTION_OUTLINE, 1);
        for (sceneObject in sceneObjects) {
            if (editorSession.selectedObjectIds.indexOf(sceneObject.id) < 0) continue;
            // The outline is a separate X-ray overlay on its own render layer,
            // so it does not inherit the scene-graph visibility that hides the
            // object's geometry. Skip selections whose node (or any ancestor
            // node) is hidden or disabled, mirroring the mesh.visible mirror in
            // synchronizeSceneObjects().
            var node:Null<h3d.scene.Object> = sceneObject.mesh;
            while (node != null && node.visible) node = node.parent;
            if (node != null) continue;
            for (renderMesh in sceneObject.allRenderMeshes()) {
                drawSelectionEdges(selectionOutline, renderMesh);
            }
        }
    }

    /**
     * Trace only the selected primitive's visible outer contour, transformed
     * by its current world matrix, instead of a bounding cube or a wireframe.
     * `SelectionOutlineEdges` classifies front/back faces in local space and
     * returns just the silhouette edges; its geometry cache is reused per
     * shared primitive.
     *
     * Edges are drawn at their exact transformed positions. The Graphics line
     * shader supplies the fixed two-pixel screen-space width; no world-space
     * inflation is applied, so scaling an object cannot scale its outline.
     * Segments are clipped to the camera near/far range before they reach the
     * line shader, avoiding oversized quads when an edge crosses behind the
     * camera.
     */
    function drawSelectionEdges(graphic:h3d.scene.Graphics, mesh:h3d.scene.Mesh):Void {
        if (mesh.primitive == null) return;
        var transform = mesh.getAbsPos();
        var camera = s3d.camera;
        // Evaluate facing in the primitive's local space so non-uniform scale
        // and reflection cannot skew the front/back classification.
        outlineInverse.initInverse(transform);
        var edges = SelectionOutlineEdges.silhouette(mesh.primitive,
            camera.pos.transformed(outlineInverse));
        if (edges.length == 0) return;
        var forwardX = camera.target.x - camera.pos.x;
        var forwardY = camera.target.y - camera.pos.y;
        var forwardZ = camera.target.z - camera.pos.z;
        var forwardLength = Math.sqrt(forwardX * forwardX
            + forwardY * forwardY + forwardZ * forwardZ);
        if (forwardLength <= 0.000001) return;
        forwardX /= forwardLength;
        forwardY /= forwardLength;
        forwardZ /= forwardLength;
        // Stay just inside the clip planes. An endpoint exactly on zNear has
        // zero projected depth in Heaps' line shader and cannot retain width.
        var nearDepth = camera.zNear * 1.01;
        var farDepth = camera.zFar * 0.999999;
        for (edge in edges) {
            var worldA = edge.a.transformed(transform);
            var worldB = edge.b.transformed(transform);
            var ax = worldA.x;
            var ay = worldA.y;
            var az = worldA.z;
            var bx = worldB.x;
            var by = worldB.y;
            var bz = worldB.z;
            var aDepth = (ax - camera.pos.x) * forwardX
                + (ay - camera.pos.y) * forwardY
                + (az - camera.pos.z) * forwardZ;
            var bDepth = (bx - camera.pos.x) * forwardX
                + (by - camera.pos.y) * forwardY
                + (bz - camera.pos.z) * forwardZ;
            if ((aDepth < nearDepth && bDepth < nearDepth)
                    || (aDepth > farDepth && bDepth > farDepth)) continue;

            if (aDepth < nearDepth) {
                var ratio = (nearDepth - aDepth) / (bDepth - aDepth);
                ax += (bx - ax) * ratio;
                ay += (by - ay) * ratio;
                az += (bz - az) * ratio;
                aDepth = nearDepth;
            } else if (bDepth < nearDepth) {
                var ratio = (nearDepth - bDepth) / (aDepth - bDepth);
                bx += (ax - bx) * ratio;
                by += (ay - by) * ratio;
                bz += (az - bz) * ratio;
                bDepth = nearDepth;
            }
            if (aDepth > farDepth) {
                var ratio = (aDepth - farDepth) / (aDepth - bDepth);
                ax += (bx - ax) * ratio;
                ay += (by - ay) * ratio;
                az += (bz - az) * ratio;
            } else if (bDepth > farDepth) {
                var ratio = (bDepth - farDepth) / (bDepth - aDepth);
                bx += (ax - bx) * ratio;
                by += (ay - by) * ratio;
                bz += (az - bz) * ratio;
            }
            graphic.moveTo(ax, ay, az);
            graphic.lineTo(bx, by, bz);
        }
    }

    static function main():Void {
        var args = Sys.args();
        var requestedWindow = ApplicationWindowKind.fromArguments(args);
        if (requestedWindow != null) {
            // HashLink's detached Windows process path allocates a console.
            // Auxiliary editor windows are GUI-only, so release it before the
            // hldx HWND is created. The main editor's launch behavior is
            // unchanged.
            #if hl
            hl.UI.closeConsole();
            #end
            switch (requestedWindow) {
                case EditorKeybindings:
                    new KeybindingsWindowApp();
                case DockPanel:
                    new DockPanelWindowApp();
            }
            return;
        }
        for (arg in args) {
            if (StringTools.startsWith(arg, "--project=")) {
                startupProjectPath = arg.substr("--project=".length);
                break;
            }
            if (StringTools.endsWith(arg.toLowerCase(), ".boltproject")) {
                startupProjectPath = arg;
                break;
            }
        }
        new Main();
    }
}

/** Per-object state captured when a shared gizmo drag begins. */
private class GizmoDragAnchor {
    public final sceneObject:SceneObject;
    public final model:EditorObject;
    /** Local transform at drag start (the undo "before" value). */
    public final startLocal:EditorTransform;
    /** World transform at drag start, used by SharedGizmoDelta. */
    public final startWorld:EditorTransform;
    /** Last accepted local transform, so out-of-bounds previews can revert. */
    public var previewLocal:EditorTransform;

    public function new(sceneObject:SceneObject, model:EditorObject,
            startLocal:EditorTransform, startWorld:EditorTransform) {
        this.sceneObject = sceneObject;
        this.model = model;
        this.startLocal = startLocal;
        this.startWorld = startWorld;
        this.previewLocal = startLocal.clone();
    }
}
