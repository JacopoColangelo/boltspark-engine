package boltspark.ui;

import boltspark.editor.GridSnapping;
import boltspark.editor.Keybindings;
import boltspark.engine.ComponentTypeInfo;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.ui.layout.LayoutRect;
import boltspark.ui.HierarchyEntry;
import boltspark.project.ProjectSession.AssetDetails;
import boltspark.project.ProjectSession.AssetFileInfo;
import boltspark.ui.windows.ApplicationWindowKind;

/**
 * BoltUI foundation facade.
 *
 * This is a native H2D implementation layered over the Heaps 2D scene —
 * it is not the final immediate-mode API, and it is not HTML, DOM, CSS,
 * Electron, NW.js, CEF, or a WebView of any kind.
 *
 * Structure:
 *  - Theme        — tokens (colors, metrics)
 *  - UiContext    — shared window/font state handed to widgets
 *  - InputAdapter — central keyboard/focus/pointer reporting (Gate 3)
 *  - widgets/     — buttons, transform fields, hierarchy, console panel
 *  - EditorShell  — editor chrome: top bar, hierarchy, viewport, inspector,
 *                   console, status bar
 *
 * The facade keeps Main simple: build, wire editor commands, update per frame.
 */
class BoltUI {
    final ctx:UiContext;
    final input:InputAdapter;
    final shell:EditorShell;

    /** Editor commands forwarded to the engine by Main. */
    public var onCreatePrimitive:Null<String->Void>;
    /** Add an empty object in front of the viewport camera. */
    public var onAddEmptyObjectInFront:Null<Void->Void>;
    public var onDropPrimitive:Null<String->Float->Float->Void>;
    /** Engine mesh asset dropped on the hierarchy: mesh id + parent id. */
    public var onCreatePrimitiveInHierarchy:Null<String->Int->Void>;
    public var onDeleteObjects:Null<Array<Int>->Void>;
    public var onObjectsSelected:Null<Array<Int>->Int->Void>;
    public var onObjectNameChanged:Null<String->Void>;
    public var onHierarchyObjectNameChanged:Null<Int->String->Void>;
    public var onCreateChildObject:Null<Int->Bool->Void>;
    public var onCreateChildPrimitive:Null<Int->String->Void>;
    public var onCreateEmptyParent:Null<Array<Int>->Void>;
    public var onDuplicateObjects:Null<Array<Int>->Void>;
    public var onCopyObjects:Null<Array<Int>->Void>;
    public var onPasteObjects:Null<Int->Void>;
    public var onQueryObjectClipboard:Null<Void->Bool>;
    public var onUnparentObjects:Null<Array<Int>->Void>;
    public var onToggleObjectVisibility:Null<Int->Void>;
    public var onSetObjectEnabled:Null<Int->Bool->Void>;
    public var onSelectSubtree:Null<Int->Void>;
    public var onCanHierarchyDrop:Null<Array<Int>->Int->Bool>;
    public var onHierarchyDrop:Null<Array<Int>->Int->Int->Bool->Void>;
    public var onInspectorNumberChanged:Null<Int->String->Int->Float->Void>;
    public var onInspectorTextChanged:Null<Int->String->String->Void>;
    public var onInspectorAssetChanged:Null<Int->String->String->Void>;
    public var onInspectorBoolChanged:Null<Int->String->Bool->Void>;
    public var onInspectorEditBegin:Null<Int->String->Int->Void>;
    public var onInspectorEditEnd:Null<Int->String->Int->Void>;
    public var onInspectorReset:Null<Int->String->Void>;
    public var onInspectorLinkChanged:Null<Int->String->Bool->Void>;
    public var onAddComponent:Null<String->Void>;
    public var onRemoveComponent:Null<Int->Void>;
    public var onViewportClick:Null<Float->Float->Void>;
    public var onToolChanged:Null<Int->Void>;
    public var onTransformSpaceChanged:Null<Bool->Void>;
    public var onViewportHover:Null<Float->Float->Void>;
    public var onViewportPush:Null<Float->Float->Bool>;
    public var onViewportDrag:Null<Float->Float->Void>;
    public var onViewportRelease:Null<Float->Float->Void>;
    /** Fired when the viewport snap bar toggles or changes a preset. */
    public var onSnapChanged:Null<Int->Void>;
    /** Ctrl+End: snap the primary selection onto the translation grid. */
    public var onSnapToGrid:Null<Void->Void>;
    /** Hold key (default V): true while held to suspend translation snapping. */
    public var onSnapHoldChanged:Null<Bool->Void>;
    /** Project/scene file commands from the File menu. */
    public var onFileNewProject:Null<Void->Void>;
    public var onFileOpenProject:Null<Void->Void>;
    public var onFileSaveProject:Null<Void->Void>;
    public var onFileSaveProjectAs:Null<Void->Void>;
    public var onFileSaveScene:Null<Void->Void>;
    public var onFileSaveAll:Null<Void->Void>;
    /** Asset Browser data and actions. */
    public var onQueryAssets:Null<Void->Array<AssetFileInfo>>;
    public var onQueryEngineAssets:Null<Void->Array<AssetFileInfo>>;
    public var onOpenAsset:Null<String->Void>;
    public var onNewScene:Null<String->String->Void>;
    public var onRenameAsset:Null<String->String->Void>;
    public var onRenameFolder:Null<String->String->String>;
    public var onDeleteAsset:Null<String->Void>;
    public var onQueryFolders:Null<Void->Array<String>>;
    public var onNewFolder:Null<String->String>;
    public var onMoveAsset:Null<String->String->Void>;
    public var onCopyAsset:Null<String->String->Void>;
    public var onDeleteAssets:Null<Array<String>->Void>;
    public var onQueryAssetDetails:Null<String->AssetDetails>;
    public var onDuplicateAsset:Null<String->Void>;
    public var onDeleteFolder:Null<String->Bool->Void>;
    public var onMoveFolder:Null<String->String->Void>;
    public var onRevealAsset:Null<String->Void>;
    public var onCopyAssetPath:Null<String->Void>;
    /** External texture import request, with the browser's target folder. */
    public var onImportAssets:Null<String->Void>;
    /** Decoded thumbnail tile for a texture asset. */
    public var onQueryTextureTile:Null<String->Null<h2d.Tile>>;
    /** Open an editor dialog as its own native top-level application window. */
    public var onOpenApplicationWindow:Null<ApplicationWindowKind->Void>;
    /** Start an editor-window host before the user reaches its menu leaf. */
    public var onPrepareApplicationWindow:Null<ApplicationWindowKind->Void>;
    public var onUndo:Null<Void->Void>;
    public var onRedo:Null<Void->Void>;
    /** Transport toolbar and F5/F6/F7 shortcuts. */
    public var onPlayPressed:Null<Void->Void>;
    public var onPausePressed:Null<Void->Void>;
    public var onStopPressed:Null<Void->Void>;
    /** Mouse wheel over the viewport (positive delta scrolls down). */
    public var onViewportWheel:Null<Float->Void>;
    /** Camera gesture start: GESTURE_* kind + viewport-local pointer. */
    public var onViewportCameraBegin:Null<Int->Float->Float->Bool>;
    /** Camera gesture movement: kind + viewport-local pointer. */
    public var onViewportCameraMove:Null<Int->Float->Float->Void>;
    /** Camera gesture end: kind + viewport-local pointer (-1 when cancelled). */
    public var onViewportCameraEnd:Null<Int->Float->Float->Void>;
    /** Viewport contextual focus (hover or owned gesture) changed. */
    public var onViewportFocusChanged:Null<Bool->Void>;
    /** The native window lost keyboard focus. */
    public var onWindowFocusLost:Null<Void->Void>;
    /** G: toggle the independent editor grid. */
    public var onToggleGrid:Null<Void->Void>;
    /** Current grid visibility, mirrored by the camera-settings checkbox. */
    public var onQueryGridVisible:Null<Void->Bool>;
    /** Inspector rows for floating native panel hosts. */
    public var onQueryNativeInspector:Null<Void->Dynamic>;
    /** Fired with the new horizontal FOV whenever the FOV field is edited. */
    public var onFovChanged:Null<Float->Void>;
    /** F: frame the primary selection in the viewport. */
    public var onFocusSelection:Null<Void->Void>;

    public function new(parent:h2d.Scene, window:hxd.Window, snapping:GridSnapping,
            keybindings:Keybindings) {
        ctx = new UiContext(window);
        input = new InputAdapter(parent, keybindings, ctx.frame.input);
        shell = new EditorShell(parent, ctx, input, snapping);
        shell.onCreatePrimitive = function(meshId) {
            if (onCreatePrimitive != null) onCreatePrimitive(meshId);
        };
        shell.onAddEmptyObjectInFront = function() {
            if (onAddEmptyObjectInFront != null) onAddEmptyObjectInFront();
        };
        shell.onDropPrimitive = function(meshId, x, y) {
            if (onDropPrimitive != null) onDropPrimitive(meshId, x, y);
        };
        shell.onCreatePrimitiveInHierarchy = function(meshId, parentId) {
            if (onCreatePrimitiveInHierarchy != null) {
                onCreatePrimitiveInHierarchy(meshId, parentId);
            }
        };
        shell.onDeleteObjects = function(ids) if (onDeleteObjects != null) onDeleteObjects(ids);
        shell.onObjectsSelected = function(ids, primary) {
            if (onObjectsSelected != null) onObjectsSelected(ids, primary);
        };
        shell.onObjectNameChanged = function(name) if (onObjectNameChanged != null) onObjectNameChanged(name);
        shell.onHierarchyObjectNameChanged = function(id, name) {
            if (onHierarchyObjectNameChanged != null) onHierarchyObjectNameChanged(id, name);
        };
        shell.onCreateChildObject = function(parentId, empty) {
            if (onCreateChildObject != null) onCreateChildObject(parentId, empty);
        };
        shell.onCreateChildPrimitive = function(parentId, meshId) {
            if (onCreateChildPrimitive != null) onCreateChildPrimitive(parentId, meshId);
        };
        shell.onCreateEmptyParent = function(ids) {
            if (onCreateEmptyParent != null) onCreateEmptyParent(ids);
        };
        shell.onDuplicateObjects = function(ids) {
            if (onDuplicateObjects != null) onDuplicateObjects(ids);
        };
        shell.onCopyObjects = function(ids) {
            if (onCopyObjects != null) onCopyObjects(ids);
        };
        shell.onPasteObjects = function(parentId) {
            if (onPasteObjects != null) onPasteObjects(parentId);
        };
        shell.onQueryObjectClipboard = function() {
            return onQueryObjectClipboard != null && onQueryObjectClipboard();
        };
        shell.onUnparentObjects = function(ids) {
            if (onUnparentObjects != null) onUnparentObjects(ids);
        };
        shell.onToggleObjectVisibility = function(id) {
            if (onToggleObjectVisibility != null) onToggleObjectVisibility(id);
        };
        shell.onSetObjectEnabled = function(id, value) {
            if (onSetObjectEnabled != null) onSetObjectEnabled(id, value);
        };
        shell.onSelectSubtree = function(id) {
            if (onSelectSubtree != null) onSelectSubtree(id);
        };
        shell.onCanHierarchyDrop = function(ids, parentId) {
            return onCanHierarchyDrop != null && onCanHierarchyDrop(ids, parentId);
        };
        shell.onHierarchyDrop = function(ids, parentId, index, preserveWorld) {
            if (onHierarchyDrop != null) {
                onHierarchyDrop(ids, parentId, index, preserveWorld);
            }
        };
        shell.onInspectorNumberChanged = function(component, property, axis, value) {
            if (onInspectorNumberChanged != null) {
                onInspectorNumberChanged(component, property, axis, value);
            }
        };
        shell.onInspectorTextChanged = function(component, property, value) {
            if (onInspectorTextChanged != null) {
                onInspectorTextChanged(component, property, value);
            }
        };
        shell.onInspectorAssetChanged = function(component, property, assetId) {
            if (onInspectorAssetChanged != null) {
                onInspectorAssetChanged(component, property, assetId);
            }
        };
        shell.onInspectorBoolChanged = function(component, property, value) {
            if (onInspectorBoolChanged != null) {
                onInspectorBoolChanged(component, property, value);
            }
        };
        shell.onInspectorEditBegin = function(component, property, axis) {
            if (onInspectorEditBegin != null) {
                onInspectorEditBegin(component, property, axis);
            }
        };
        shell.onInspectorEditEnd = function(component, property, axis) {
            if (onInspectorEditEnd != null) {
                onInspectorEditEnd(component, property, axis);
            }
        };
        shell.onInspectorReset = function(component, property) {
            if (onInspectorReset != null) onInspectorReset(component, property);
        };
        shell.onInspectorLinkChanged = function(component, property, linked) {
            if (onInspectorLinkChanged != null) {
                onInspectorLinkChanged(component, property, linked);
            }
        };
        shell.onAddComponent = function(typeId) {
            if (onAddComponent != null) onAddComponent(typeId);
        };
        shell.onRemoveComponent = function(index) {
            if (onRemoveComponent != null) onRemoveComponent(index);
        };
        shell.onViewportClick = function(x, y) if (onViewportClick != null) onViewportClick(x, y);
        shell.onToolChanged = function(tool) if (onToolChanged != null) onToolChanged(tool);
        shell.onTransformSpaceChanged = function(local) {
            if (onTransformSpaceChanged != null) onTransformSpaceChanged(local);
        };
        shell.onViewportHover = function(x, y) if (onViewportHover != null) onViewportHover(x, y);
        shell.onViewportPush = function(x, y) {
            return onViewportPush != null && onViewportPush(x, y);
        };
        shell.onViewportDrag = function(x, y) if (onViewportDrag != null) onViewportDrag(x, y);
        shell.onViewportRelease = function(x, y) if (onViewportRelease != null) onViewportRelease(x, y);
        shell.onSnapChanged = function(mode) if (onSnapChanged != null) onSnapChanged(mode);
        shell.onSnapToGrid = function() if (onSnapToGrid != null) onSnapToGrid();
        shell.onSnapHoldChanged = function(active) {
            if (onSnapHoldChanged != null) onSnapHoldChanged(active);
        };
        shell.onFileNewProject = function() if (onFileNewProject != null) onFileNewProject();
        shell.onFileOpenProject = function() if (onFileOpenProject != null) onFileOpenProject();
        shell.onFileSaveProject = function() if (onFileSaveProject != null) onFileSaveProject();
        shell.onFileSaveProjectAs = function() {
            if (onFileSaveProjectAs != null) onFileSaveProjectAs();
        };
        shell.onFileSaveScene = function() if (onFileSaveScene != null) onFileSaveScene();
        shell.onFileSaveAll = function() if (onFileSaveAll != null) onFileSaveAll();
        shell.onQueryAssets = function() {
            return onQueryAssets != null ? onQueryAssets() : [];
        };
        shell.onQueryEngineAssets = function() {
            return onQueryEngineAssets != null ? onQueryEngineAssets() : [];
        };
        shell.onOpenAsset = function(source) {
            if (onOpenAsset != null) onOpenAsset(source);
        };
        shell.onNewScene = function(folder, name) {
            if (onNewScene != null) onNewScene(folder, name);
        };
        shell.onRenameAsset = function(source, name) {
            if (onRenameAsset != null) onRenameAsset(source, name);
        };
        shell.onDeleteAsset = function(source) {
            if (onDeleteAsset != null) onDeleteAsset(source);
        };
        shell.onRenameFolder = function(source, name) {
            return onRenameFolder != null ? onRenameFolder(source, name) : null;
        };
        shell.onQueryFolders = function() {
            return onQueryFolders != null ? onQueryFolders() : [];
        };
        shell.onNewFolder = function(parent) {
            return onNewFolder != null ? onNewFolder(parent) : null;
        };
        shell.onMoveAsset = function(source, folder) {
            if (onMoveAsset != null) onMoveAsset(source, folder);
        };
        shell.onCopyAsset = function(source, folder) {
            if (onCopyAsset != null) onCopyAsset(source, folder);
        };
        shell.onDeleteAssets = function(sources) {
            if (onDeleteAssets != null) onDeleteAssets(sources);
        };
        shell.onQueryAssetDetails = function(source) {
            return onQueryAssetDetails != null ? onQueryAssetDetails(source) : null;
        };
        shell.onDuplicateAsset = function(source) {
            if (onDuplicateAsset != null) onDuplicateAsset(source);
        };
        shell.onDeleteFolder = function(folder, recursive) {
            if (onDeleteFolder != null) onDeleteFolder(folder, recursive);
        };
        shell.onMoveFolder = function(source, parent) {
            if (onMoveFolder != null) onMoveFolder(source, parent);
        };
        shell.onRevealAsset = function(source) {
            if (onRevealAsset != null) onRevealAsset(source);
        };
        shell.onCopyAssetPath = function(source) {
            if (onCopyAssetPath != null) onCopyAssetPath(source);
        };
        shell.onImportAssets = function(folder) {
            if (onImportAssets != null) onImportAssets(folder);
        };
        shell.onQueryTextureTile = function(source) {
            return onQueryTextureTile != null ? onQueryTextureTile(source) : null;
        };
        shell.onOpenApplicationWindow = function(kind) {
            if (onOpenApplicationWindow != null) onOpenApplicationWindow(kind);
        };
        shell.onPrepareApplicationWindow = function(kind) {
            if (onPrepareApplicationWindow != null) onPrepareApplicationWindow(kind);
        };
        shell.onUndo = function() if (onUndo != null) onUndo();
        shell.onRedo = function() if (onRedo != null) onRedo();
        shell.onPlayPressed = function() if (onPlayPressed != null) onPlayPressed();
        shell.onPausePressed = function() if (onPausePressed != null) onPausePressed();
        shell.onStopPressed = function() if (onStopPressed != null) onStopPressed();
        shell.onViewportWheel = function(delta) {
            if (onViewportWheel != null) onViewportWheel(delta);
        };
        shell.onViewportCameraBegin = function(kind, x, y) {
            return onViewportCameraBegin != null
                && onViewportCameraBegin(kind, x, y);
        };
        shell.onViewportCameraMove = function(kind, x, y) {
            if (onViewportCameraMove != null) onViewportCameraMove(kind, x, y);
        };
        shell.onViewportCameraEnd = function(kind, x, y) {
            if (onViewportCameraEnd != null) onViewportCameraEnd(kind, x, y);
        };
        shell.onViewportFocusChanged = function(focused) {
            if (onViewportFocusChanged != null) onViewportFocusChanged(focused);
        };
        shell.onWindowFocusLost = function() {
            if (onWindowFocusLost != null) onWindowFocusLost();
        };
        shell.onToggleGrid = function() {
            if (onToggleGrid != null) onToggleGrid();
        };
        shell.onQueryGridVisible = function() {
            return onQueryGridVisible != null && onQueryGridVisible();
        };
        shell.onQueryNativeInspector = function() {
            return onQueryNativeInspector != null ? onQueryNativeInspector() : null;
        };
        shell.onFovChanged = function(value) {
            if (onFovChanged != null) onFovChanged(value);
        };
        shell.onFocusSelection = function() {
            if (onFocusSelection != null) onFocusSelection();
        };
        // Camera-key-bound shortcuts are suppressed only while RMB fly
        // navigation is actually captured. Hover alone must leave E and the
        // other editor shortcuts available, matching Unreal's input model.
        input.viewportNavigationQuery = function() {
            return shell.isViewportNavigationActive();
        };
    }

    /** Resolve a window-client point to a browser folder for OS file drops. */
    public function folderAtWindowPoint(x:Float, y:Float):Null<String> {
        return shell.folderAtWindowPoint(x, y);
    }

    /**
     * The centralized docking manager. Future panels register through its
     * PanelRegistry; existing panels are already registered by EditorShell.
     */
    public function dock():boltspark.ui.dock.DockingManager return shell.dockManager;

    /** Refresh snapshots shown in floating native panel windows. */
    public function refreshNativePanels():Void shell.refreshNativePanels();

    /** Shut down child processes hosting floating panels. */
    public function shutdown():Void shell.shutdownDockWindows();

    /** Editor console access. */
    public function log(line:String):Void {
        shell.log(line);
        refreshNativePanels();
        // Mirror the editor console to stdout so automated runs can verify
        // command flow without screenshots.
        Sys.println('[console] ' + line);
    }

    /** Called once per app frame. Re-layout only when the OS window changes size. */
    public function update(dt:Float):Void {
        ctx.beginFrame();
        ctx.frame.register("editor-shell",
            new LayoutRect(0, 0, ctx.windowWidth, ctx.windowHeight));
        shell.update(dt);
        shell.registerFrame(ctx.frame);
        var diagnostics = ctx.endFrame();
        if (diagnostics.length > 0) {
            // Contract failures are exceptional and de-duplicated per frame.
            // Keep them out of the normal Output Log unless they actually occur.
            for (message in diagnostics) Sys.println('[BoltUI] ${message}');
        }
    }

    /** Rebuild static 2D chrome in response to a native window resize. */
    public function resize():Void {
        shell.resize();
    }

    public function getViewportRect():LayoutRect {
        return shell.viewportRect;
    }

    /** Floating label for asset drags over the 3D viewport. */
    public function showViewportDropHint(text:String, x:Float, y:Float,
            viewport:LayoutRect):Void {
        shell.showViewportDropHint(text, x, y, viewport);
    }

    public function hideViewportDropHint():Void {
        shell.hideViewportDropHint();
    }

    /** UI font for editor overlay text (viewport axis gizmo letters). */
    public function viewportFont():h2d.Font {
        return shell.viewportFont();
    }

    /** Small viewport overlay showing the current camera movement speed. */
    public function setCameraSpeedLabel(text:String):Void {
        shell.setCameraSpeedLabel(text);
    }

    public function setHierarchyEntries(entries:Array<HierarchyEntry>):Void {
        shell.setHierarchyEntries(entries);
    }

    public function setSelectedObjects(ids:Array<Int>, primaryId:Int,
            name:String, ?components:Array<ComponentInspectorData>,
            ?availableTypes:Array<ComponentTypeInfo>, enabled:Bool = true):Void {
        shell.setSelectedObjects(ids, primaryId, name, components, availableTypes, enabled);
    }

    public function setObjectName(name:String):Void {
        shell.setObjectName(name);
    }

    public function setHistoryState(undoLabel:Null<String>,
            redoLabel:Null<String>):Void {
        shell.setHistoryState(undoLabel, redoLabel);
    }

    /** Reflect the live Play/Pause state on the transport buttons. */
    public function setPlaybackState(playing:Bool, paused:Bool):Void {
        shell.setPlaybackState(playing, paused);
    }

    /** Title-strip project/scene label, including the unsaved marker. */
    public function setProjectTitle(text:String):Void {
        shell.setProjectTitle(text);
    }

    /** Rebuild the Asset Browser after a project asset changes. */
    public function refreshAssetBrowser():Void {
        shell.refreshAssetBrowser();
    }

    /** Live component-vector update during viewport gizmo drags. */
    public function updateInspectorVector(componentIndex:Int,
            propertyId:String, x:Float, y:Float, z:Float):Void {
        shell.updateInspectorVector(componentIndex, propertyId, x, y, z);
    }

    /** Live vector update for a multi-object drag, including mixed axes. */
    public function updateInspectorVectorMixed(componentIndex:Int,
            propertyId:String, values:Array<Float>, mixed:Array<Bool>):Void {
        shell.updateInspectorVectorMixed(componentIndex, propertyId, values, mixed);
    }
}
