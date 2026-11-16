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
import boltspark.editor.MultiInspectorData;
import boltspark.editor.RotationEuler;
import boltspark.editor.ScalePolicy;
import boltspark.editor.SceneObject;
import boltspark.editor.SelectionClick;
import boltspark.editor.SharedGizmoDelta;
import boltspark.editor.TransformGizmo;
import boltspark.editor.WorldBounds;
import boltspark.engine.ComponentRegistry;
import boltspark.engine.Component;
import boltspark.engine.MeshRenderer;
import boltspark.engine.inspector.ComponentInspectorData;
import boltspark.engine.inspector.ComponentPropertyData;
import boltspark.engine.PrimitiveGameObjects;
import boltspark.diagnostics.RuntimeProbes;
import boltspark.platform.InteractiveResize;
import boltspark.ui.AppIcon;
import boltspark.ui.BoltUI;
import boltspark.ui.HierarchyEntry;
import boltspark.ui.Theme;
import boltspark.ui.windows.ApplicationWindowKind;
import boltspark.ui.windows.ApplicationWindowManager;
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
    /** Heaps render views synchronized from the renderer-independent session. */
    final sceneObjects:Array<SceneObject> = [];
    final sceneObjectsById:Map<Int, SceneObject> = [];
    var editorSession:EditorSession;
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
            runtimeProbes.shutdown();
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
        editorSession = new EditorSession();
        var initialEditorObject = editorSession.addInitialObject("sampleCube",
            null, null, PrimitiveGameObjects.cubeComponents());
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
        boltUI.onCreateObject = createCube;
        boltUI.onCreateObjectAt = createCubeAtViewport;
        boltUI.onDeleteObjects = deleteSceneObjects;
        boltUI.onObjectsSelected = selectSceneObjects;
        boltUI.onInspectorNumberChanged = applyInspectorNumberChange;
        boltUI.onInspectorTextChanged = applyInspectorTextChange;
        boltUI.onInspectorEditBegin = beginComponentInspectorEdit;
        boltUI.onInspectorEditEnd = endComponentInspectorEdit;
        boltUI.onInspectorReset = resetInspectorProperty;
        boltUI.onInspectorLinkChanged = setInspectorPropertyLinked;
        boltUI.onAddComponent = addSelectedComponent;
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
        boltUI.onHierarchyObjectNameChanged = function(id, name) {
            var trimmed = StringTools.trim(name);
            if (trimmed.length == 0) {
                boltUI.log("hierarchy: object name cannot be empty");
                return;
            }
            editorSession.renameObject(id, trimmed);
        };
        boltUI.onCreateChildObject = createHierarchyObject;
        boltUI.onCreateEmptyParent = function(ids) {
            editorSession.createEmptyParent(ids, "GameObject");
        };
        boltUI.onDuplicateObjects = function(ids) editorSession.duplicateObjects(ids);
        boltUI.onCopyObjects = function(ids) editorSession.copyObjects(ids);
        boltUI.onPasteObjects = function(parentId) editorSession.pasteObjects(parentId);
        boltUI.onUnparentObjects = function(ids) {
            editorSession.unparentObjects(ids, true);
        };
        boltUI.onSelectSubtree = editorSession.selectSubtree;
        boltUI.onCanHierarchyDrop = function(ids, parentId) {
            return editorSession.canReparentObjects(ids, parentId);
        };
        boltUI.onHierarchyDrop = function(ids, parentId, siblingIndex, preserveWorld) {
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
        boltUI.onFovChanged = function(value) {
            printActivity('[viewport] fov=${Math.round(value)}°');
        };
        boltUI.onFocusSelection = focusSelection;
        logActivity('renderer driver: ${driverName}');
        logActivity("editor shell ready — hierarchy, inspector, console live");
        if (keybindings.lastError != "") {
            boltUI.log("keybindings: " + keybindings.lastError);
        }
        editorSession.onChanged = synchronizeEditorSession;
        refreshHierarchy();
        editorSession.selectObject(initialEditorObject.id);

        boltUI.onObjectNameChanged = function(name:String) {
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
    }

    override function update(dt:Float):Void {
        runtimeProbes.update(dt, h3d.Engine.getCurrent());
        applicationWindows.update();
        editorSession.update(dt);
        if (keybindings.pollExternalChanges()) {
            logActivity("keybindings: synchronized changes from the settings window");
        }
        // Editor camera navigation runs before everything that reads the
        // camera this frame (gizmo follow, outline, rendering). Movement keys
        // are inert unless an RMB free-look gesture owns the viewport; gizmo
        // drags remain an additional safety lockout.
        cameraController.keyboardEnabled = !gizmoDragging;
        var viewport = boltUI.getViewportRect();
        cameraController.setViewportSize(viewport.width, viewport.height);
        cameraController.update(dt);
        boltUI.update(dt);
        axisGizmo.update();
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
        gizmo.follow();
        // A very large object can enclose the editor camera. Render that mesh
        // two-sided only while inside it so it remains visibly present rather
        // than looking as though it was deleted by a transform command.
        for (sceneObject in sceneObjects) {
            var model = editorSession.findObject(sceneObject.id);
            if (model != null) sceneObject.synchronizeComponents(model);
            refreshScaleRendering(sceneObject);
        }
        // The selection outline tracks transform edits and gizmo drags.
        refreshSelectionOutline();
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
            return;
        }
        if (editorSession.selectedObjectIds.length > 1) {
            var edited = false;
            for (id in editorSession.selectedObjectIds) {
                var component = multiComponentFor(id, componentIndex);
                if (component != null
                        && component.setInspectorNumber(propertyId, axis, value)) {
                    editorSession.componentEdited(id);
                    edited = true;
                }
            }
            if (edited) refreshSelectionInspector();
            return;
        }
        var component = selectedInspectorComponent(componentIndex);
        if (component != null
                && component.setInspectorNumber(propertyId, axis, value)) {
            editorSession.componentEdited(editorSession.selectedObjectId);
        }
    }

    function applyInspectorTextChange(componentIndex:Int, propertyId:String,
            value:String):Void {
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

    function beginComponentInspectorEdit(componentIndex:Int,
            propertyId:String, axis:Int):Void {
        if (!isSelectedTransform(componentIndex)) return;
        var row = transformPropertyRow(propertyId);
        if (row >= 0) beginInspectorTransformEdit(row, axis);
    }

    function endComponentInspectorEdit(componentIndex:Int,
            propertyId:String, axis:Int):Void {
        if (!isSelectedTransform(componentIndex)) {
            clearInspectorTransformEdit();
            return;
        }
        var row = transformPropertyRow(propertyId);
        if (row >= 0) endInspectorTransformEdit(row, axis);
    }

    function resetInspectorProperty(componentIndex:Int, propertyId:String):Void {
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

    function setInspectorPropertyLinked(componentIndex:Int, propertyId:String,
            linked:Bool):Void {
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
            for (id in editorSession.selectedObjectIds) {
                var sceneObject = findSceneObject(id);
                if (sceneObject == null) continue;
                inspectorEditIds.push(id);
                inspectorEditBefores.push(sceneObject.captureTransform());
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

    function multiTransformEdit(row:Int, axis:Int, value:Float):Void {
        var objects = selectedSceneObjects();
        if (objects.length == 0) return;
        for (sceneObject in objects) {
            switch (row) {
                case 0: applyMultiPosition(sceneObject, axis, value);
                case 1: applyMultiRotation(sceneObject, axis, value);
                default: applyMultiScale(sceneObject, axis, value);
            }
        }
        pushSelectionInspectorTransform();
    }

    function applyMultiPosition(sceneObject:SceneObject, axis:Int,
            value:Float):Void {
        var previous = sceneObject.captureTransform();
        var desired = previous.clone();
        switch (axis) {
            case 0: desired.positionX = value;
            case 1: desired.positionY = value;
            default: desired.positionZ = value;
        }
        sceneObject.applyTransform(desired);
        if (!containSceneObject(sceneObject)) sceneObject.applyTransform(previous);
    }

    function applyMultiRotation(sceneObject:SceneObject, axis:Int,
            degrees:Float):Void {
        var previous = sceneObject.captureTransform();
        var current = rotationDegrees(sceneObject);
        switch (axis) {
            case 0: current.x = degrees;
            case 1: current.y = degrees;
            default: current.z = degrees;
        }
        var quat = new h3d.Quat();
        quat.initRotation(degToRad(current.z), degToRad(current.y), degToRad(current.x));
        var desired = sceneObject.captureTransform();
        desired.rotationX = quat.x;
        desired.rotationY = quat.y;
        desired.rotationZ = quat.z;
        desired.rotationW = quat.w;
        desired.rotationHintX = current.x;
        desired.rotationHintY = current.y;
        desired.rotationHintZ = current.z;
        desired.rotationHintValid = true;
        sceneObject.applyTransform(desired);
        if (!containSceneObject(sceneObject)) sceneObject.applyTransform(previous);
    }

    function applyMultiScale(sceneObject:SceneObject, axis:Int,
            value:Float):Void {
        var previous = switch (axis) {
            case 0: sceneObject.mesh.scaleX;
            case 1: sceneObject.mesh.scaleY;
            default: sceneObject.mesh.scaleZ;
        };
        var clamped = clampedScale(value, previous);
        var targetX = sceneObject.mesh.scaleX;
        var targetY = sceneObject.mesh.scaleY;
        var targetZ = sceneObject.mesh.scaleZ;
        if (scaleProportionsLinked) {
            var ratio = clamped / ScalePolicy.nonZero(previous, clamped);
            targetX = clampedScale(targetX * ratio, targetX);
            targetY = clampedScale(targetY * ratio, targetY);
            targetZ = clampedScale(targetZ * ratio, targetZ);
        } else {
            switch (axis) {
                case 0: targetX = clamped;
                case 1: targetY = clamped;
                default: targetZ = clamped;
            }
        }
        var bounded = WorldBounds.fitScale(sceneObject.mesh,
            targetX, targetY, targetZ,
            function(x, y, z) applySceneObjectScale(sceneObject, x, y, z));
        applySceneObjectScale(sceneObject, bounded.x, bounded.y, bounded.z);
        refreshScaleRendering(sceneObject);
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

    function applyTransformChange(axis:Int, value:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var commandBefore = atomicTransformStart(selected);
        var previous = selected.captureTransform();
        // Inspector commits are deliberate typed values, so they are never
        // snapped (matching Unreal's details panel); only gizmo drags snap,
        // incrementally, and Ctrl+End performs an explicit absolute snap.
        var desired = previous.clone();
        switch (axis) {
            case 0: desired.positionX = value;
            case 1: desired.positionY = value;
            default: desired.positionZ = value;
        }
        selected.applyTransform(desired);
        var placed = containSceneObject(selected);
        if (!placed) {
            selected.applyTransform(previous);
            boltUI.log('world bounds: ${selected.name} is too large to reposition');
        }
        var actual = axis == 0 ? selected.mesh.x
            : axis == 1 ? selected.mesh.y : selected.mesh.z;
        if (placed && different(actual, value)) logWorldBound(selected);
        pushInspectorTransform(selected);
        commitAtomicTransform(selected, commandBefore,
            inspectorTransformLabel(selected.name, 0, axis));
        logActivity('command: ${selected.name} position.${axisName(axis)} = ${round2(actual)}');
    }

    function applyRotationChange(axis:Int, degrees:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var commandBefore = atomicTransformStart(selected);
        var previous = selected.captureTransform();
        var current = rotationDegrees(selected);
        switch (axis) {
            case 0: current.x = degrees;
            case 1: current.y = degrees;
            default: current.z = degrees;
        }
        var quat = new h3d.Quat();
        quat.initRotation(degToRad(current.z), degToRad(current.y), degToRad(current.x));
        var desired = selected.captureTransform();
        desired.rotationX = quat.x;
        desired.rotationY = quat.y;
        desired.rotationZ = quat.z;
        desired.rotationW = quat.w;
        desired.rotationHintX = current.x;
        desired.rotationHintY = current.y;
        desired.rotationHintZ = current.z;
        desired.rotationHintValid = true;
        selected.applyTransform(desired);
        var beforeContainX = selected.mesh.x;
        var beforeContainY = selected.mesh.y;
        var beforeContainZ = selected.mesh.z;
        if (!containSceneObject(selected)) {
            selected.applyTransform(previous);
            logWorldBound(selected);
        } else if (different(beforeContainX, selected.mesh.x)
                || different(beforeContainY, selected.mesh.y)
                || different(beforeContainZ, selected.mesh.z)) {
            logWorldBound(selected);
        }
        pushInspectorTransform(selected);
        var applied = rotationDegrees(selected);
        var actual = axis == 0 ? applied.x : axis == 1 ? applied.y : applied.z;
        commitAtomicTransform(selected, commandBefore,
            inspectorTransformLabel(selected.name, 1, axis));
        logActivity('command: ${selected.name} rotation.${axisName(axis)} = ${round2(actual)} deg');
    }

    function applyScaleChange(axis:Int, value:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var commandBefore = atomicTransformStart(selected);
        var previous = switch (axis) {
            case 0: selected.mesh.scaleX;
            case 1: selected.mesh.scaleY;
            default: selected.mesh.scaleZ;
        };
        // Signed scale mirrors geometry. Keep only a tiny dead zone around
        // zero because an exactly singular transform cannot be inverted.
        var clamped = clampedScale(value, previous);
        var targetX = selected.mesh.scaleX;
        var targetY = selected.mesh.scaleY;
        var targetZ = selected.mesh.scaleZ;
        if (scaleProportionsLinked) {
            var ratio = clamped / ScalePolicy.nonZero(previous, clamped);
            targetX = clampedScale(targetX * ratio, targetX);
            targetY = clampedScale(targetY * ratio, targetY);
            targetZ = clampedScale(targetZ * ratio, targetZ);
        } else {
            switch (axis) {
                case 0: targetX = clamped;
                case 1: targetY = clamped;
                default: targetZ = clamped;
            }
        }
        var bounded = WorldBounds.fitScale(
            selected.mesh, targetX, targetY, targetZ,
            function(x, y, z) applySceneObjectScale(selected, x, y, z));
        applySceneObjectScale(selected, bounded.x, bounded.y, bounded.z);
        if (different(bounded.x, targetX) || different(bounded.y, targetY)
                || different(bounded.z, targetZ)) logWorldBound(selected);
        refreshScaleRendering(selected);
        pushInspectorTransform(selected);
        if (scaleProportionsLinked) {
            commitAtomicTransform(selected, commandBefore,
                'Edit ${selected.name} Proportional Scale');
            logActivity('command: ${selected.name} proportional scale = '
                + scaleDescription(selected.mesh));
        } else {
            var actual = axis == 0 ? selected.mesh.scaleX
                : axis == 1 ? selected.mesh.scaleY : selected.mesh.scaleZ;
            commitAtomicTransform(selected, commandBefore,
                inspectorTransformLabel(selected.name, 2, axis));
            logActivity('command: ${selected.name} scale.${axisName(axis)} = ${round2(actual)}');
        }
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
        if (verboseLogging) {
            logActivity('viewport transform space: ${local ? "Local" : "World"}');
            var xAxis = gizmo.getAxisDirection(TransformGizmo.HANDLE_AXIS_X);
            printActivity('[gizmo] transform space=${local ? "Local" : "World"}'
                + ' xAxis=(${round2(xAxis.x)}, ${round2(xAxis.y)}, ${round2(xAxis.z)})');
        }
    }

    function onViewportHover(x:Float, y:Float):Void {
        if (gizmoDragging) return;
        var pointer = viewportPointer(x, y);
        gizmo.setHover(gizmo.pick(viewportRay(x, y), pointer.x, pointer.y));
    }

    function onViewportPush(x:Float, y:Float):Bool {
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
        if (!gizmoDragging) return;
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
        for (anchor in gizmoDragAnchors) {
            var desired = SharedGizmoDelta.apply(anchor.startWorld,
                dragStartWorldTransform, desiredWorld, mode);
            var local = editorSession.hierarchy.localTransformForWorld(
                anchor.model, desired, anchor.model.parent);
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

    /** Live inspector values while a gizmo drag is in progress. */
    function pushInspectorTransform(selected:SceneObject):Void {
        var rotation = rotationDegrees(selected);
        var model = editorSession.findObject(selected.id);
        if (model == null) return;
        var componentIndex = model.components.indexOf(model.transform);
        boltUI.updateInspectorVector(componentIndex, "position",
            selected.mesh.x, selected.mesh.y, selected.mesh.z);
        boltUI.updateInspectorVector(componentIndex, "rotation",
            rotation.x, rotation.y, rotation.z);
        boltUI.updateInspectorVector(componentIndex, "scale",
            selected.mesh.scaleX, selected.mesh.scaleY, selected.mesh.scaleZ);
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
        return switch (row) {
            case 0: [sceneObject.mesh.x, sceneObject.mesh.y, sceneObject.mesh.z];
            case 1:
                var rotation = rotationDegrees(sceneObject);
                [rotation.x, rotation.y, rotation.z];
            default: [sceneObject.mesh.scaleX, sceneObject.mesh.scaleY,
                sceneObject.mesh.scaleZ];
        };
    }

    function onViewportRelease(x:Float, y:Float):Void {
        if (!gizmoDragging) return;
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
        var ray = viewportRay(x, y);
        var nearestDistance = Math.POSITIVE_INFINITY;
        var nearestObject:Null<SceneObject> = null;
        for (sceneObject in sceneObjects) {
            for (renderMesh in sceneObject.allRenderMeshes()) {
                // Pick renderer-owned geometry, not the root's recursive
                // collider; empty parents must not steal their children's hits.
                var collider = renderMesh.getGlobalCollider();
                if (collider == null) continue;
                var distance = collider.rayIntersection(ray, true);
                if (distance >= 0 && distance < nearestDistance) {
                    nearestDistance = distance;
                    nearestObject = sceneObject;
                }
            }
        }
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
        var index = sceneObjects.length - 1;
        while (index >= 0) {
            if (editorSession.findObject(sceneObjects[index].id) == null) {
                sceneObjectsById.remove(sceneObjects[index].id);
                sceneObjects[index].mesh.remove();
                sceneObjects.splice(index, 1);
            }
            index--;
        }

        // Ensure every renderer node exists before linking parent references.
        for (object in editorSession.objects) {
            var sceneObject = findSceneObject(object.id);
            if (sceneObject == null) {
                sceneObject = createSceneObjectView(object);
                sceneObjectsById.set(object.id, sceneObject);
                sceneObjects.push(sceneObject);
            }
        }

        var ordered:Array<SceneObject> = [];
        for (object in editorSession.hierarchy.flatten()) {
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

    /** Keep back-face culling aligned with a reflected transform's winding. */
    function refreshScaleRendering(sceneObject:SceneObject):Void {
        for (mesh in sceneObject.allRenderMeshes()) {
            var renderer = sceneObject.rendererFor(mesh);
            if (renderer == null) continue;
            var mirrored = mesh.getAbsPos().getDeterminant() < 0;
            // A camera inside a closed one-sided mesh sees only back faces.
            // Draw both sides only in that editor condition.
            var culling = cameraInsideMesh(mesh)
                ? h3d.mat.Data.Face.None
                : renderer.cullingForScale(mirrored);
            mesh.material.mainPass.culling = culling;
            var shadowPass = mesh.material.getPass("shadow");
            if (shadowPass != null) shadowPass.culling = culling;
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

    function createCube():Void {
        createCubeAtPosition(editorSession.nextRuntimeId * 1.5, 0);
    }

    function createCubeAtViewport(viewX:Float, viewY:Float):Void {
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
        createCubeAtPosition(x, z);
    }

    function createCubeAtPosition(x:Float, z:Float):Void {
        var runtimeId = editorSession.nextRuntimeId;
        var name = "Cube" + runtimeId;
        // The current palette creates a unit cube with identity rotation/scale;
        // constrain its half-unit geometry before it enters session history.
        var pivotLimit = WorldBounds.HALF_EXTENT - 0.5;
        var transform = new EditorTransform(
            Math.max(-pivotLimit, Math.min(pivotLimit, x)), 0,
            Math.max(-pivotLimit, Math.min(pivotLimit, z)));
        editorSession.createObject(name, transform, -1,
            PrimitiveGameObjects.cubeComponents());
        logActivity("scene: created " + name);
    }

    function createHierarchyObject(parentId:Int, empty:Bool):Void {
        var runtimeId = editorSession.nextRuntimeId;
        var name = empty ? "GameObject" : "Cube" + runtimeId;
        editorSession.createObject(name, new EditorTransform(), parentId,
            empty ? [] : PrimitiveGameObjects.cubeComponents());
    }

    function deleteSceneObjects(ids:Array<Int>):Void {
        var deletedNames = editorSession.deleteObjects(ids);
        if (deletedNames.length == 0) {
            boltUI.log("scene: selected objects no longer exist");
            editorSession.selectObject(-1);
            return;
        }
        for (name in deletedNames) logActivity("scene: deleted " + name);
    }

    function selectSceneObjects(ids:Array<Int>, primaryId:Int):Void {
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
                selected.name, components, ComponentRegistry.addableTypes());
            return;
        }
        // Build an Inspector projection shared by every selected object:
        // common components/properties only, with per-axis mixed-value flags.
        var allData:Array<Array<ComponentInspectorData>> = [];
        var primaryData:Null<Array<ComponentInspectorData>> = null;
        for (id in ids) {
            var model = editorSession.findObject(id);
            if (model == null) continue;
            var sceneObject = findSceneObject(id);
            var data = [for (index in 0...model.components.length)
                model.components[index].inspectorData(index)];
            if (sceneObject != null) overrideInspectorRotation(data, sceneObject);
            allData.push(data);
            if (id == editorSession.selectedObjectId) primaryData = data;
        }
        if (primaryData == null) {
            boltUI.setSelectedObjects([], -1, "", [], ComponentRegistry.addableTypes());
            return;
        }
        var merged = MultiInspectorData.build(primaryData, allData);
        boltUI.setSelectedObjects(ids, editorSession.selectedObjectId,
            '${ids.length} objects selected', merged,
            ComponentRegistry.addableTypes());
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
                object.getComponent(MeshRenderer) != null,
                object.children.length, siblingIndex));
        }
        boltUI.setHierarchyEntries(entries);
    }

    function undoEditorCommand():Void {
        if (gizmoDragging || inspectorEditObjectId >= 0) return;
        var label = editorSession.history.undoLabel;
        if (!editorSession.undo()) return;
        logActivity('command: undo ${label}');
        printHistoryTransform("undo", label);
    }

    function redoEditorCommand():Void {
        if (gizmoDragging || inspectorEditObjectId >= 0) return;
        var label = editorSession.history.redoLabel;
        if (!editorSession.redo()) return;
        logActivity('command: redo ${label}');
        printHistoryTransform("redo", label);
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
    }

    function refreshSelectionOutline():Void {
        if (selectionOutline == null) return;
        selectionOutline.clear();
        selectionOutline.lineStyle(2.0, Theme.ACCENT, 1);
        for (sceneObject in sceneObjects) {
            if (editorSession.selectedObjectIds.indexOf(sceneObject.id) < 0) continue;
            for (renderMesh in sceneObject.allRenderMeshes()) {
                drawSelectionEdges(selectionOutline, renderMesh);
            }
        }
    }

    /**
     * Trace the renderer primitive's local bounds transformed by its current
     * transform. This remains exact for box primitives and works for arbitrary
     * primitive/imported mesh sizes without assuming unit-cube geometry.
     *
     * Edges are drawn at their exact transformed positions. The Graphics line
     * shader supplies the fixed two-pixel screen-space width; no world-space
     * inflation is applied, so scaling an object cannot scale its outline.
     * Segments are clipped to the camera near/far range before they reach the
     * line shader, avoiding oversized quads when a large edge crosses behind
     * the camera.
     */
    function drawSelectionEdges(graphic:h3d.scene.Graphics, mesh:h3d.scene.Mesh):Void {
        var transform = mesh.getAbsPos();
        if (mesh.primitive == null) return;
        var bounds = mesh.primitive.getBounds();
        if (bounds == null) return;
        inline function corner(x:Float, y:Float, z:Float):h3d.Vector {
            return new h3d.Vector(x, y, z)
                .transformed(transform);
        }
        var corners = [
            corner(bounds.xMin, bounds.yMin, bounds.zMin),
            corner(bounds.xMax, bounds.yMin, bounds.zMin),
            corner(bounds.xMax, bounds.yMax, bounds.zMin),
            corner(bounds.xMin, bounds.yMax, bounds.zMin),
            corner(bounds.xMin, bounds.yMin, bounds.zMax),
            corner(bounds.xMax, bounds.yMin, bounds.zMax),
            corner(bounds.xMax, bounds.yMax, bounds.zMax),
            corner(bounds.xMin, bounds.yMax, bounds.zMax)
        ];
        // 12 cube edges as index pairs over the corner list.
        var edges = [
            0, 1, 1, 2, 2, 3, 3, 0, // back face
            4, 5, 5, 6, 6, 7, 7, 4, // front face
            0, 4, 1, 5, 2, 6, 3, 7  // connecting edges
        ];
        var camera = s3d.camera;
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
        for (index in 0...(edges.length >> 1)) {
            var a = corners[edges[index * 2]];
            var b = corners[edges[index * 2 + 1]];
            var ax = a.x;
            var ay = a.y;
            var az = a.z;
            var bx = b.x;
            var by = b.y;
            var bz = b.z;
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
        var requestedWindow = ApplicationWindowKind.fromArguments(Sys.args());
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
            }
            return;
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
