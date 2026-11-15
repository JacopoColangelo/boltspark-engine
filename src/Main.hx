import boltspark.editor.GridSnapping;
import boltspark.editor.EditorViewport;
import boltspark.editor.EditorObject;
import boltspark.editor.EditorObjectKind;
import boltspark.editor.EditorSession;
import boltspark.editor.EditorTransform;
import boltspark.editor.Keybindings;
import boltspark.editor.RotationEuler;
import boltspark.editor.ScalePolicy;
import boltspark.editor.SceneObject;
import boltspark.editor.TransformGizmo;
import boltspark.editor.WorldBounds;
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
    var cubePrimitive:h3d.prim.Cube;
    var groundGrid:h3d.scene.Graphics;
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

        cubePrimitive = new h3d.prim.Cube(1, 1, 1, true);
        // Cube.addUVs() unindexes the primitive; calculate normals afterwards
        // so each face stays flat instead of sharing smoothed corner normals.
        cubePrimitive.addUVs();
        cubePrimitive.addNormals();
        setupViewportScene();
        gizmoProxy = new h3d.scene.Object(s3d);
        gizmoProxy.name = "TransformGizmoProxy";
        gizmo = new TransformGizmo(s3d);
        editorSession = new EditorSession();
        var initialEditorObject = editorSession.addInitialObject("sampleCube");
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

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        // Inter and JetBrains Mono UI fonts are rasterized from their embedded
        // TTF faces by FreeType at the exact requested size and cached on
        // demand. Everything else defaults to pixel-exact sampling;
        // procedural icons perform analytic shader anti-aliasing.
        s2d.defaultSmooth = false;
        snap = new GridSnapping();
        keybindings = new Keybindings();
        boltUI = new BoltUI(s2d, nativeWindow, snap, keybindings);
        editorViewport = new EditorViewport(nativeWindow, s3d, s2d,
            function() return boltUI.getViewportRect());
        boltUI.onViewportClick = onViewportClick;
        boltUI.onCreateObject = createCube;
        boltUI.onCreateObjectAt = createCubeAtViewport;
        boltUI.onDeleteObjects = deleteSceneObjects;
        boltUI.onObjectsSelected = selectSceneObjects;
        boltUI.onTransformChanged = applyTransformChange;
        boltUI.onRotationChanged = applyRotationChange;
        boltUI.onScaleChanged = applyScaleChange;
        boltUI.onTransformEditBegin = beginInspectorTransformEdit;
        boltUI.onTransformEditEnd = endInspectorTransformEdit;
        boltUI.onTransformReset = resetTransformRow;
        boltUI.onScaleLinkChanged = setScaleProportionsLinked;
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
        logActivity('renderer driver: ${driverName}');
        logActivity("editor shell ready — hierarchy, inspector, console live");
        if (keybindings.lastError != "") {
            boltUI.log("keybindings: " + keybindings.lastError);
        }
        editorSession.onChanged = synchronizeEditorSession;
        refreshHierarchy();
        editorSession.selectObject(initialEditorObject.id);

        boltUI.onObjectNameChanged = function(name:String) {
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
        if (keybindings.pollExternalChanges()) {
            logActivity("keybindings: synchronized changes from the settings window");
        }
        boltUI.update(dt);
        gizmo.follow();
        // A very large object can enclose the editor camera. Render that mesh
        // two-sided only while inside it so it remains visibly present rather
        // than looking as though it was deleted by a transform command.
        for (sceneObject in sceneObjects) refreshScaleRendering(sceneObject);
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

    /** Capture one complete Inspector gesture so scrubbing creates one command. */
    function beginInspectorTransformEdit(row:Int, axis:Int):Void {
        var selected = getSelectedObject();
        if (selected == null || gizmoDragging) return;
        inspectorEditObjectId = selected.id;
        inspectorEditRow = row;
        inspectorEditAxis = axis;
        inspectorEditBefore = selected.captureTransform();
    }

    function endInspectorTransformEdit(row:Int, axis:Int):Void {
        if (inspectorEditObjectId < 0 || row != inspectorEditRow
                || axis != inspectorEditAxis) {
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
        var selected = getSelectedObject();
        if (selected == null) return false;
        var model = editorSession.findObject(selected.id);
        if (model == null) return false;
        var world = model.worldTransform;
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
        dragStartTransform = model.transform.clone();
        dragStartWorldTransform = world.clone();
        dragPreviewTransform = dragStartTransform.clone();
        gizmo.beginDrag(handle, gizmoProxy, viewportRay(x, y), pointer.x, pointer.y);
        // Capture all gizmo anchors before raw input can invoke its callback.
        beginRelativeDrag();
        if (verboseLogging) {
            var handleName = gizmo.describe(handle);
            logActivity('gizmo: drag ${selected.name} ${handleName}');
            printActivity('[gizmo] drag start object=${selected.name} handle=${handleName}'
                + ' space=${localTransformSpace ? "Local" : "World"}'
                + ' at=(${round2(world.positionX)}, ${round2(world.positionY)},'
                + ' ${round2(world.positionZ)})');
        }
        return true;
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
        // onDragRelativeMove instead; hxd delivers no EMove then.
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
                hxd.impl.MouseMode.Relative(onDragRelativeMove, true);
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

    /** Raw hardware deltas from the hidden-cursor drag drive the gizmo. */
    function onDragRelativeMove(event:hxd.Event):Void {
        if (!gizmoDragging || !dragRelative) return;
        // Relative callbacks are private to the gizmo. Never turn them back
        // into absolute EMove events, which would run the capture path twice.
        event.propagate = false;
        if (event.relX == 0 && event.relY == 0) return;
        dragVirtualX += event.relX;
        dragVirtualY += event.relY;
        var selected = getSelectedObject();
        if (selected == null) {
            cancelGizmoDrag();
            return;
        }
        applyDragTransform(selected);
    }

    /** Abort a drag safely if its selected object disappears mid-capture. */
    function cancelGizmoDrag():Void {
        gizmoDragging = false;
        gizmoHandle = -1;
        gizmoWorldBounded = false;
        dragStartTransform = null;
        dragStartWorldTransform = null;
        dragPreviewTransform = null;
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
            case RotateQuat(q):
                // Axis rings use Unreal-style incremental degree snapping.
                // The center arc-ball is intentionally freeform even while
                // rotation snapping is enabled: quantizing its three Euler
                // components would make a camera-space tumble feel stepped.
                var targetRotation = gizmoHandle == TransformGizmo.HANDLE_CENTER
                    ? q
                    : snap.snapQuatIncremental(dragStartQuat, q);
                desiredWorld.rotationX = targetRotation.x;
                desiredWorld.rotationY = targetRotation.y;
                desiredWorld.rotationZ = targetRotation.z;
                desiredWorld.rotationW = targetRotation.w;
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
        var previousPreview = dragPreviewTransform == null
            ? dragStartTransform : dragPreviewTransform;
        var local = editorSession.hierarchy.localTransformForWorld(
            model, desiredWorld, model.parent);
        selected.applyTransform(local);
        if (!containSceneObject(selected)) {
            selected.applyTransform(previousPreview);
            gizmoWorldBounded = true;
            return;
        }
        local = selected.captureTransform();
        dragPreviewTransform = local;
        var actualWorld = worldTransformForLocal(model, local);
        applyGizmoProxy(actualWorld);
        refreshScaleRendering(selected);
        pushInspectorTransform(selected);
    }

    /**
     * Ctrl+End: the one absolute snap. Round the selected object's world
     * position onto the nearest translation grid point, independent of the
     * translation enable flag — this is an explicit user command.
     */
    function snapSelectionToGrid():Void {
        var selected = getSelectedObject();
        if (selected == null || gizmoDragging) return;
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

    /** Optional diagnostic feedback for viewport snap toggle/preset changes. */
    function onSnapChanged(mode:Int):Void {
        if (!verboseLogging) return;
        var modeNames = ["translation", "rotation", "scale"];
        var enabled = snap.isEnabled(mode);
        logActivity('snapping: ${modeNames[mode]} ${enabled ? "enabled" : "disabled"}'
            + ' · step ${round2(snap.stepFor(mode))}');
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
        boltUI.updateTransformValues(
            selected.mesh.x, selected.mesh.y, selected.mesh.z,
            rotation.x, rotation.y, rotation.z,
            selected.mesh.scaleX, selected.mesh.scaleY, selected.mesh.scaleZ);
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
        var commandName = switch (currentTool) {
            case TransformGizmo.TOOL_MOVE: 'Move ${selected.name}';
            case TransformGizmo.TOOL_ROTATE: 'Rotate ${selected.name}';
            default: 'Scale ${selected.name}';
        };
        if (dragStartTransform != null && dragPreviewTransform != null) {
            editorSession.commitAppliedTransform(selected.id, dragStartTransform,
                dragPreviewTransform, commandName);
        }
        dragStartTransform = null;
        dragStartWorldTransform = null;
        dragPreviewTransform = null;
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
            var renderMesh = sceneObject.renderMesh;
            if (renderMesh == null) continue;
            // Pick this object's own geometry, not a recursive child collider;
            // empty hierarchy parents must not steal their children's hits.
            var collider = renderMesh.getGlobalCollider();
            if (collider == null) continue;
            var distance = collider.rayIntersection(ray, true);
            if (distance >= 0 && distance < nearestDistance) {
                nearestDistance = distance;
                nearestObject = sceneObject;
            }
        }
        if (nearestObject == null) {
            selectSceneObject(-1);
            logActivity("viewport: no object at pointer");
        } else {
            selectSceneObject(nearestObject.id);
            logActivity('viewport: selected ${nearestObject.name}');
        }
    }

    function createSceneObjectView(object:EditorObject):SceneObject {
        var node:h3d.scene.Object;
        if (object.kind == EditorObjectKind.Cube) {
            var mesh = new h3d.scene.Mesh(cubePrimitive, s3d);
            mesh.material.color.setColor(Theme.CUBE_ORANGE);
            mesh.material.shadows = false;
            mesh.material.specularAmount = 0.18;
            mesh.material.specularPower = 24;
            node = mesh;
        } else {
            node = new h3d.scene.Object(s3d);
        }
        node.name = object.name;
        var sceneObject = new SceneObject(object.id, node, object.persistentId);
        sceneObject.applyTransform(object.transform);
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
            sceneObject.applyTransform(object.transform);
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
        var mesh = sceneObject.renderMesh;
        if (mesh == null) return;
        var mirrored = mesh.getAbsPos().getDeterminant() < 0;
        // A camera inside a closed one-sided mesh sees only back faces. Draw
        // both sides in that editor-only condition so extreme but valid scale
        // values cannot make an object appear to have been deleted.
        var culling = cameraInsideMesh(mesh)
            ? h3d.mat.Data.Face.None
            : sceneObject.cullingForScale(mirrored);
        mesh.material.mainPass.culling = culling;
        var shadowPass = mesh.material.getPass("shadow");
        if (shadowPass != null) shadowPass.culling = culling;
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
        editorSession.createObject(name, transform);
        logActivity("scene: created " + name);
    }

    function createHierarchyObject(parentId:Int, empty:Bool):Void {
        var runtimeId = editorSession.nextRuntimeId;
        var name = empty ? "GameObject" : "Cube" + runtimeId;
        editorSession.createObject(name, new EditorTransform(), parentId,
            empty ? EditorObjectKind.Empty : EditorObjectKind.Cube);
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

    function selectSceneObject(id:Int):Void {
        editorSession.selectObject(id);
    }

    function selectSceneObjects(ids:Array<Int>, primaryId:Int):Void {
        clearInspectorTransformEdit();
        editorSession.selectObjects(ids, primaryId);
    }

    /** Push the primary selection's full inspector state through BoltUI. */
    function refreshSelectionInspector():Void {
        var selected = getSelectedObject();
        if (selected == null) {
            boltUI.setSelectedObjects(editorSession.selectedObjectIds, -1, "");
            return;
        }
        var rotation = rotationDegrees(selected);
        boltUI.setSelectedObjects(editorSession.selectedObjectIds, selected.id,
            selected.name, selected.mesh.x, selected.mesh.y, selected.mesh.z,
            rotation.x, rotation.y, rotation.z,
            selected.mesh.scaleX, selected.mesh.scaleY, selected.mesh.scaleZ);
    }

    function getSelectedObject():Null<SceneObject> {
        return findSceneObject(editorSession.selectedObjectId);
    }

    function attachGizmo(selected:Null<SceneObject>):Void {
        if (selected == null) {
            gizmo.attach(null);
            return;
        }
        var model = editorSession.findObject(selected.id);
        if (model == null) {
            gizmo.attach(null);
            return;
        }
        applyGizmoProxy(model.worldTransform);
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
                depth, object.children.length > 0, object.kind,
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

        groundGrid = new h3d.scene.Graphics(s3d);
        groundGrid.name = "EditorGrid";
        groundGrid.material.mainPass.depthWrite = false;
        // Draw the grid before scene geometry and editor overlays. Both the
        // grid and selection outline are screen-space Graphics lines, so an
        // explicit layer prevents material sorting from painting grid pixels
        // over the outline where their projections cross.
        groundGrid.material.mainPass.layer = -10;
        var extent = 20;
        var gridY = -0.505;
        for (i in -extent...(extent + 1)) {
            var major = i % 5 == 0;
            groundGrid.lineStyle(major ? 1.0 : 0.75,
                major ? 0x384450 : 0x252D37, 1);
            groundGrid.moveTo(i, gridY, -extent);
            groundGrid.lineTo(i, gridY, extent);
            groundGrid.moveTo(-extent, gridY, i);
            groundGrid.lineTo(extent, gridY, i);
        }
        groundGrid.lineStyle(1.35, Theme.AXIS_X, 1);
        groundGrid.moveTo(-extent, gridY + 0.003, 0);
        groundGrid.lineTo(extent, gridY + 0.003, 0);
        groundGrid.lineStyle(1.35, Theme.AXIS_Z, 1);
        groundGrid.moveTo(0, gridY + 0.003, -extent);
        groundGrid.lineTo(0, gridY + 0.003, extent);

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
            if (sceneObject.renderMesh != null) {
                drawSelectionEdges(selectionOutline, sceneObject.renderMesh);
            }
        }
    }

    /**
     * Trace the mesh's actual silhouette: the unit cube primitive's 12 edges
     * transformed by the object's current transform (rotation and scale), so
     * a rotated object is outlined by its true shape rather than an
     * axis-aligned boundary cube.
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
        inline function corner(sx:Float, sy:Float, sz:Float):h3d.Vector {
            return new h3d.Vector(sx * 0.5, sy * 0.5, sz * 0.5)
                .transformed(transform);
        }
        var corners = [
            corner(-1, -1, -1), corner(1, -1, -1), corner(1, 1, -1), corner(-1, 1, -1),
            corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1)
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
