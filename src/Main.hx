import boltspark.editor.SceneObject;
import boltspark.editor.TransformGizmo;
import boltspark.ui.BoltUI;
import boltspark.ui.HierarchyEntry;
import boltspark.ui.Theme;

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
    var nativeWindow:hxd.Window;
    var cubePrimitive:h3d.prim.Cube;
    var groundGrid:h3d.scene.Graphics;
    var selectionOutline:h3d.scene.Graphics;
    final sceneObjects:Array<SceneObject> = [];
    final selectedObjectIds:Array<Int> = [];
    var nextObjectId:Int = 1;
    var selectedObjectId:Int = -1;
    var gizmo:TransformGizmo;
    var currentTool:Int = 0;
    var gizmoDragging:Bool = false;
    var gizmoHandle:Int = -1;

    static inline var OUTLINE_INFLATE:Float = 1.015;
    static inline var OUTLINE_LIFT:Float = 0.008;

    @:hlNative("directx", "win_set_interactive_resize_callback")
    static function setInteractiveResizeCallback(callback:Void->Void):Void return;

    static function interactiveResizeFrame():Void {
        try {
            @:privateAccess hxd.System.mainLoop();
        } catch (error:Dynamic) {
            Sys.println('[resize] frame failed: ${Std.string(error)}');
            setInteractiveResizeCallback(null);
        }
    }

    override function init():Void {
        setInteractiveResizeCallback(interactiveResizeFrame);
        // Fonts, icons, and vector UI surfaces are compiled into both the HL
        // bytecode and native release executable; no runtime asset folder is
        // required beside Boltspark.exe.
        hxd.Res.initEmbed();
        nativeWindow = hxd.Window.getInstance();
        nativeWindow.title = "Boltspark Engine";
        nativeWindow.vsync = true;

        // M0 evidence: log which Heaps driver backend is actually running.
        var engine = h3d.Engine.getCurrent();
        engine.backgroundColor = 0xFF000000 | Theme.APP_BG;
        var driverName = Type.getClassName(Type.getClass(engine.driver));
        Sys.println('[M0] renderer driver = ${driverName}');

        cubePrimitive = new h3d.prim.Cube(1, 1, 1, true);
        // Cube.addUVs() unindexes the primitive; calculate normals afterwards
        // so each face stays flat instead of sharing smoothed corner normals.
        cubePrimitive.addUVs();
        cubePrimitive.addNormals();
        setupViewportScene();
        gizmo = new TransformGizmo(s3d);
        addSceneObject("sampleCube", 0, Theme.CUBE_ORANGE);

        s3d.camera.pos.set(5.8, 4.2, 6.4);
        s3d.camera.target.set(0, 0, 0);
        // Boltspark's scene editing logic is Y-up (ground placement intersects
        // y = 0), while Heaps defaults its camera to Z-up.
        s3d.camera.up.set(0, 1, 0);

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        // Proportional UI fonts are rasterized from their embedded TTF faces by
        // FreeType at the exact requested size and cached on demand. Everything
        // else defaults to pixel-exact sampling; procedural icons perform
        // analytic shader anti-aliasing.
        s2d.defaultSmooth = false;
        boltUI = new BoltUI(s2d, nativeWindow);
        boltUI.onViewportClick = onViewportClick;
        boltUI.onCreateObject = createCube;
        boltUI.onCreateObjectAt = createCubeAtViewport;
        boltUI.onDeleteObjects = deleteSceneObjects;
        boltUI.onObjectsSelected = selectSceneObjects;
        boltUI.onTransformChanged = applyTransformChange;
        boltUI.onRotationChanged = applyRotationChange;
        boltUI.onScaleChanged = applyScaleChange;
        boltUI.onToolChanged = setEditorTool;
        boltUI.onViewportHover = onViewportHover;
        boltUI.onViewportPush = onViewportPush;
        boltUI.onViewportDrag = onViewportDrag;
        boltUI.onViewportRelease = onViewportRelease;
        boltUI.log('renderer driver: ${driverName}');
        boltUI.log("editor shell ready — hierarchy, inspector, console live");
        refreshHierarchy();
        selectSceneObject(sceneObjects[0].id);

        boltUI.onSpinSpeedChanged = function(v:Float) {
            var selected = getSelectedObject();
            if (selected == null) return;
            for (sceneObject in sceneObjects) {
                if (selectedObjectIds.indexOf(sceneObject.id) >= 0) sceneObject.spinSpeed = v;
            }
            boltUI.log('command: ${selected.name} spin speed = ${Std.string(v)}');
        };
        boltUI.onColorChanged = function(color:Int) {
            var selected = getSelectedObject();
            if (selected == null) return;
            for (sceneObject in sceneObjects) {
                if (selectedObjectIds.indexOf(sceneObject.id) < 0) continue;
                sceneObject.color = color;
                sceneObject.mesh.material.color.setColor(color);
            }
            boltUI.log('command: ${selected.name} base color = 0x' + StringTools.hex(color, 6));
        };
        boltUI.onObjectNameChanged = function(name:String) {
            var selected = getSelectedObject();
            if (selected == null) return;
            var trimmedName = StringTools.trim(name);
            if (trimmedName.length == 0) {
                boltUI.log("inspector: object name cannot be empty");
                refreshSelectionInspector();
                return;
            }
            selected.name = trimmedName;
            refreshHierarchy();
            boltUI.log("command: object name = " + trimmedName);
        };
    }

    override function update(dt:Float):Void {
        boltUI.update(dt);

        // Visible motion confirms the 3D update path is alive; the editor
        // controls the rate through the inspector stepper.
        for (sceneObject in sceneObjects) {
            sceneObject.mesh.rotate(0.0, dt * sceneObject.spinSpeed, 0.0);
        }
        gizmo.follow();
        // The selection outline must track spinning/moving objects every frame.
        refreshSelectionOutline();
    }

    override function render(engine:h3d.Engine):Void {
        var viewport = boltUI.getViewportRect();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        var x = Std.int(Math.round(viewport.x * scaleX));
        var y = Std.int(Math.round(viewport.y * scaleY));
        var width = Std.int(Math.max(0, Math.round(viewport.width * scaleX)));
        var height = Std.int(Math.max(0, Math.round(viewport.height * scaleY)));
        if (width > 0 && height > 0) {
            var centerX = x + width * 0.5;
            var centerY = y + height * 0.5;
            s3d.camera.setFovX(70, engine.width / engine.height);
            s3d.camera.viewX = centerX * 2 / engine.width - 1;
            s3d.camera.viewY = 1 - centerY * 2 / engine.height;
            engine.setRenderZone(x, y, width, height);
            engine.clear(0xFF000000 | Theme.VIEWPORT_BG, 1, 0);
            s3d.render(engine);
            engine.setRenderZone();
        }
        s2d.render(engine);
    }

    /** Build a scene ray from viewport-local pointer coordinates. */
    function viewportRay(viewX:Float, viewY:Float):h3d.col.Ray {
        var viewport = boltUI.getViewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        return s3d.camera.rayFromScreen(
            (viewport.x + viewX) * scaleX,
            (viewport.y + viewY) * scaleY,
            engine.width,
            engine.height);
    }

    /** Engine-space pointer coordinates matching camera.project output. */
    function viewportPointer(viewX:Float, viewY:Float):h3d.Vector {
        var viewport = boltUI.getViewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        return new h3d.Vector((viewport.x + viewX) * scaleX,
            (viewport.y + viewY) * scaleY, 0);
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

    /** Euler degrees (X, Y, Z) read from an object's rotation quaternion. */
    function rotationDegrees(mesh:h3d.scene.Object):h3d.Vector {
        var euler = mesh.getRotationQuat().toEuler();
        return new h3d.Vector(radToDeg(euler.x), radToDeg(euler.y), radToDeg(euler.z));
    }

    function applyTransformChange(axis:Int, value:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        switch (axis) {
            case 0: selected.mesh.x = value;
            case 1: selected.mesh.y = value;
            default: selected.mesh.z = value;
        }
        boltUI.log('command: ${selected.name} position.${axisName(axis)} = ${round2(value)}');
    }

    function applyRotationChange(axis:Int, degrees:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        var current = rotationDegrees(selected.mesh);
        switch (axis) {
            case 0: current.x = degrees;
            case 1: current.y = degrees;
            default: current.z = degrees;
        }
        var quat = new h3d.Quat();
        quat.initRotation(degToRad(current.x), degToRad(current.y), degToRad(current.z));
        selected.mesh.setRotationQuat(quat);
        boltUI.log('command: ${selected.name} rotation.${axisName(axis)} = ${round2(degrees)} deg');
    }

    function applyScaleChange(axis:Int, value:Float):Void {
        var selected = getSelectedObject();
        if (selected == null) return;
        // Guard against zero/negative scale which collapses the mesh.
        var clamped = Math.max(0.01, value);
        switch (axis) {
            case 0: selected.mesh.scaleX = clamped;
            case 1: selected.mesh.scaleY = clamped;
            default: selected.mesh.scaleZ = clamped;
        }
        boltUI.log('command: ${selected.name} scale.${axisName(axis)} = ${round2(clamped)}');
    }

    static function axisName(axis:Int):String {
        return axis == 0 ? "x" : axis == 1 ? "y" : "z";
    }

    /** Toolbar/shortcut tool switch: every tool drives its viewport gizmo. */
    function setEditorTool(tool:Int):Void {
        currentTool = tool;
        gizmo.setTool(tool);
        var selected = getSelectedObject();
        gizmo.attach(selected == null ? null : selected.mesh);
        var toolNames = ["Move", "Rotate", "Scale"];
        boltUI.log('viewport tool: ${toolNames[tool]} gizmo active');
    }

    function onViewportHover(x:Float, y:Float):Void {
        if (gizmoDragging) return;
        var pointer = viewportPointer(x, y);
        gizmo.setHover(gizmo.pick(viewportRay(x, y), pointer.x, pointer.y));
    }

    function onViewportPush(x:Float, y:Float):Bool {
        var selected = getSelectedObject();
        if (selected == null) return false;
        var pointer = viewportPointer(x, y);
        var handle = gizmo.pick(viewportRay(x, y), pointer.x, pointer.y);
        if (handle < 0) return false;
        gizmoHandle = handle;
        gizmoDragging = true;
        gizmo.beginDrag(handle, selected.mesh, viewportRay(x, y), pointer.x, pointer.y);
        var handleName = gizmo.describe(handle);
        boltUI.log('gizmo: drag ${selected.name} ${handleName}');
        Sys.println('[gizmo] drag start object=${selected.name} handle=${handleName}'
            + ' at=(${round2(selected.mesh.x)}, ${round2(selected.mesh.y)},'
            + ' ${round2(selected.mesh.z)})');
        return true;
    }

    function onViewportDrag(x:Float, y:Float):Void {
        if (!gizmoDragging) return;
        var selected = getSelectedObject();
        if (selected == null) {
            gizmoDragging = false;
            gizmo.endDrag();
            return;
        }
        var pointer = viewportPointer(x, y);
        var next = gizmo.dragTo(viewportRay(x, y), pointer.x, pointer.y);
        if (next == null) return;
        switch (next) {
            case MovePosition(nx, ny, nz):
                selected.mesh.setPosition(nx, ny, nz);
            case RotateQuat(q):
                selected.mesh.setRotationQuat(q);
            case ScaleValues(sx, sy, sz):
                selected.mesh.scaleX = sx;
                selected.mesh.scaleY = sy;
                selected.mesh.scaleZ = sz;
        }
        pushInspectorTransform(selected);
    }

    /** Live inspector values while a gizmo drag is in progress. */
    function pushInspectorTransform(selected:SceneObject):Void {
        var rotation = rotationDegrees(selected.mesh);
        boltUI.updateTransformValues(
            selected.mesh.x, selected.mesh.y, selected.mesh.z,
            rotation.x, rotation.y, rotation.z,
            selected.mesh.scaleX, selected.mesh.scaleY, selected.mesh.scaleZ);
    }

    function onViewportRelease(x:Float, y:Float):Void {
        if (!gizmoDragging) return;
        gizmoDragging = false;
        var handle = gizmoHandle;
        gizmoHandle = -1;
        gizmo.endDrag();
        var selected = getSelectedObject();
        if (selected == null || handle < 0) return;
        var handleName = gizmo.describe(handle);
        var at = '(${round2(selected.mesh.x)}, ${round2(selected.mesh.y)},'
            + ' ${round2(selected.mesh.z)})';
        var rotation = rotationDegrees(selected.mesh);
        var rot = '(${round2(rotation.x)}, ${round2(rotation.y)}, ${round2(rotation.z)} deg)';
        var scl = '(${round2(selected.mesh.scaleX)}, ${round2(selected.mesh.scaleY)},'
            + ' ${round2(selected.mesh.scaleZ)})';
        switch (currentTool) {
            case TransformGizmo.TOOL_MOVE:
                boltUI.log('command: ${selected.name} ${handleName} position = ' + at);
                Sys.println('[gizmo] drag end object=${selected.name} handle=${handleName} at=' + at);
            case TransformGizmo.TOOL_ROTATE:
                boltUI.log('command: ${selected.name} ${handleName} rotation = ' + rot);
                Sys.println('[gizmo] drag end object=${selected.name} handle=${handleName} rotation=' + rot);
            default:
                boltUI.log('command: ${selected.name} ${handleName} scale = ' + scl);
                Sys.println('[gizmo] drag end object=${selected.name} handle=${handleName} scale=' + scl);
        }
    }

    function onViewportClick(x:Float, y:Float):Void {
        var ray = viewportRay(x, y);
        var nearestDistance = Math.POSITIVE_INFINITY;
        var nearestObject:Null<SceneObject> = null;
        for (sceneObject in sceneObjects) {
            var collider = sceneObject.mesh.getCollider();
            if (collider == null) continue;
            var distance = collider.rayIntersection(ray, true);
            if (distance >= 0 && distance < nearestDistance) {
                nearestDistance = distance;
                nearestObject = sceneObject;
            }
        }
        if (nearestObject == null) {
            selectSceneObject(-1);
            boltUI.log("viewport: no object at pointer");
        } else {
            selectSceneObject(nearestObject.id);
            boltUI.log('viewport: selected ${nearestObject.name}');
        }
    }

    function addSceneObject(name:String, x:Float, color:Int, z:Float = 0):SceneObject {
        var mesh = new h3d.scene.Mesh(cubePrimitive, s3d);
        mesh.name = name;
        mesh.setPosition(x, 0, z);
        mesh.material.color.setColor(color);
        mesh.material.shadows = false;
        mesh.material.specularAmount = 0.18;
        mesh.material.specularPower = 24;
        var sceneObject = new SceneObject(nextObjectId++, mesh, color);
        sceneObjects.push(sceneObject);
        return sceneObject;
    }

    function createCube():Void {
        createCubeAtPosition(nextObjectId * 1.5, 0);
    }

    function createCubeAtViewport(viewX:Float, viewY:Float):Void {
        var ray = viewportRay(viewX, viewY);
        var x = nextObjectId * 1.5;
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
        var colors = [Theme.CUBE_ORANGE, Theme.CUBE_STEEL, Theme.CUBE_MOSS, Theme.CUBE_VIOLET];
        var color = colors[sceneObjects.length % colors.length];
        var name = "Cube" + nextObjectId;
        var sceneObject = addSceneObject(name, x, color, z);
        refreshHierarchy();
        selectSceneObject(sceneObject.id);
        boltUI.log("scene: created " + name);
    }

    function deleteSceneObjects(ids:Array<Int>):Void {
        var deletedNames:Array<String> = [];
        var index = sceneObjects.length - 1;
        while (index >= 0) {
            var sceneObject = sceneObjects[index];
            if (ids.indexOf(sceneObject.id) >= 0) {
                deletedNames.push(sceneObject.name);
                sceneObject.mesh.remove();
                sceneObjects.splice(index, 1);
            }
            index--;
        }
        if (deletedNames.length == 0) {
            boltUI.log("scene: selected objects no longer exist");
            selectSceneObject(-1);
            return;
        }
        refreshHierarchy();
        var nextSelection = sceneObjects.length == 0 ? -1 : sceneObjects[sceneObjects.length - 1].id;
        selectSceneObject(nextSelection);
        for (name in deletedNames) boltUI.log("scene: deleted " + name);
    }

    function selectSceneObject(id:Int):Void {
        selectSceneObjects(id < 0 ? [] : [id], id);
    }

    function selectSceneObjects(ids:Array<Int>, primaryId:Int):Void {
        selectedObjectIds.resize(0);
        for (id in ids) {
            if (selectedObjectIds.indexOf(id) >= 0) continue;
            if (findSceneObject(id) != null) selectedObjectIds.push(id);
        }
        selectedObjectId = selectedObjectIds.indexOf(primaryId) >= 0
            ? primaryId
            : (selectedObjectIds.length == 0 ? -1 : selectedObjectIds[selectedObjectIds.length - 1]);
        refreshSelectionOutline();
        gizmo.attach(getSelectedObject() == null ? null : getSelectedObject().mesh);
        refreshSelectionInspector();
    }

    /** Push the primary selection's full inspector state through BoltUI. */
    function refreshSelectionInspector():Void {
        var selected = getSelectedObject();
        if (selected == null) {
            boltUI.setSelectedObjects(selectedObjectIds, -1, "", 0, 0);
            return;
        }
        var rotation = rotationDegrees(selected.mesh);
        boltUI.setSelectedObjects(selectedObjectIds, selected.id,
            selected.name, selected.spinSpeed, selected.color,
            selected.mesh.x, selected.mesh.y, selected.mesh.z,
            rotation.x, rotation.y, rotation.z,
            selected.mesh.scaleX, selected.mesh.scaleY, selected.mesh.scaleZ);
    }

    function getSelectedObject():Null<SceneObject> {
        return findSceneObject(selectedObjectId);
    }

    function findSceneObject(id:Int):Null<SceneObject> {
        for (sceneObject in sceneObjects) if (sceneObject.id == id) return sceneObject;
        return null;
    }

    function refreshHierarchy():Void {
        var entries:Array<HierarchyEntry> = [];
        for (sceneObject in sceneObjects) {
            entries.push(new HierarchyEntry(sceneObject.id, sceneObject.name));
        }
        boltUI.setHierarchyEntries(entries);
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
        var extent = 20;
        var gridY = -0.505;
        for (i in -extent...(extent + 1)) {
            var major = i % 5 == 0;
            groundGrid.lineStyle(major ? 1.25 : 1.0,
                major ? 0x384450 : 0x252D37, 1);
            groundGrid.moveTo(i, gridY, -extent);
            groundGrid.lineTo(i, gridY, extent);
            groundGrid.moveTo(-extent, gridY, i);
            groundGrid.lineTo(extent, gridY, i);
        }
        groundGrid.lineStyle(1.8, Theme.AXIS_X, 1);
        groundGrid.moveTo(-extent, gridY + 0.003, 0);
        groundGrid.lineTo(extent, gridY + 0.003, 0);
        groundGrid.lineStyle(1.8, Theme.AXIS_Z, 1);
        groundGrid.moveTo(0, gridY + 0.003, -extent);
        groundGrid.lineTo(0, gridY + 0.003, extent);

        selectionOutline = new h3d.scene.Graphics(s3d);
        selectionOutline.name = "SelectionOutline";
        selectionOutline.material.mainPass.depthWrite = false;
    }

    function refreshSelectionOutline():Void {
        if (selectionOutline == null) return;
        selectionOutline.clear();
        selectionOutline.lineStyle(2.0, Theme.ACCENT, 1);
        for (sceneObject in sceneObjects) {
            if (selectedObjectIds.indexOf(sceneObject.id) < 0) continue;
            drawSelectionEdges(selectionOutline, sceneObject.mesh);
        }
    }

    /**
     * Trace the mesh's actual silhouette: the unit cube primitive's 12 edges
     * transformed by the object's current transform (rotation and scale), so
     * a rotated object is outlined by its true shape rather than an
     * axis-aligned boundary cube.
     *
     * The outline is inflated slightly about the object center and lifted a
     * little on Y so it never z-fights with the object's own faces or the
     * ground grid beneath it.
     */
    function drawSelectionEdges(graphic:h3d.scene.Graphics, mesh:h3d.scene.Mesh):Void {
        var transform = mesh.getTransform();
        var center = new h3d.Vector(mesh.x, mesh.y, mesh.z);
        inline function corner(sx:Float, sy:Float, sz:Float):h3d.Vector {
            var point = new h3d.Vector(sx * 0.5, sy * 0.5, sz * 0.5)
                .transformed(transform);
            // Inflate about the center, then lift clear of the grid plane.
            point.x = center.x + (point.x - center.x) * OUTLINE_INFLATE;
            point.y = center.y + (point.y - center.y) * OUTLINE_INFLATE
                + OUTLINE_LIFT;
            point.z = center.z + (point.z - center.z) * OUTLINE_INFLATE;
            return point;
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
        for (index in 0...(edges.length >> 1)) {
            var a = corners[edges[index * 2]];
            var b = corners[edges[index * 2 + 1]];
            graphic.moveTo(a.x, a.y, a.z);
            graphic.lineTo(b.x, b.y, b.z);
        }
    }

    static function main():Void {
        new Main();
    }
}
