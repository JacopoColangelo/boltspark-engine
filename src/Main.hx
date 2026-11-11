import boltspark.editor.SceneObject;
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
    final sceneObjects:Array<SceneObject> = [];
    final selectedObjectIds:Array<Int> = [];
    var nextObjectId:Int = 1;
    var selectedObjectId:Int = -1;

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
        nativeWindow = hxd.Window.getInstance();
        nativeWindow.title = "Boltspark Engine";
        nativeWindow.vsync = true;

        // M0 evidence: log which Heaps driver backend is actually running.
        var engine = h3d.Engine.getCurrent();
        var driverName = Type.getClassName(Type.getClass(engine.driver));
        Sys.println('[M0] renderer driver = ${driverName}');

        cubePrimitive = new h3d.prim.Cube(1, 1, 1, true);
        cubePrimitive.addNormals();
        cubePrimitive.addUVs();
        addSceneObject("sampleCube", 0, Theme.CUBE_ORANGE);

        s3d.camera.pos.set(5, 5, 5);

        // BoltUI is a native H2D overlay rendered by Heaps. It is not HTML,
        // DOM, CSS, Electron, NW.js, CEF, or a WebView.
        boltUI = new BoltUI(s2d, nativeWindow);
        boltUI.onViewportClick = onViewportClick;
        boltUI.onCreateObject = createCube;
        boltUI.onCreateObjectAt = createCubeAtViewport;
        boltUI.onDeleteObjects = deleteSceneObjects;
        boltUI.onObjectsSelected = selectSceneObjects;
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
                boltUI.setSelectedObjects(selectedObjectIds, selected.id,
                    selected.name, selected.spinSpeed, selected.color);
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
            sceneObject.mesh.rotate(0.0, 0.0, dt * sceneObject.spinSpeed);
        }
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
            s3d.render(engine);
            engine.setRenderZone();
        }
        s2d.render(engine);
    }

    function onViewportClick(x:Float, y:Float):Void {
        var viewport = boltUI.getViewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        var ray = s3d.camera.rayFromScreen(
            (viewport.x + x) * scaleX,
            (viewport.y + y) * scaleY,
            engine.width,
            engine.height);
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
        var sceneObject = new SceneObject(nextObjectId++, mesh, color);
        sceneObjects.push(sceneObject);
        return sceneObject;
    }

    function createCube():Void {
        createCubeAtPosition(nextObjectId * 1.5, 0);
    }

    function createCubeAtViewport(viewX:Float, viewY:Float):Void {
        var viewport = boltUI.getViewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, nativeWindow.width);
        var scaleY = engine.height / Math.max(1, nativeWindow.height);
        var ray = s3d.camera.rayFromScreen(
            (viewport.x + viewX) * scaleX,
            (viewport.y + viewY) * scaleY,
            engine.width,
            engine.height);
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
        var selected = getSelectedObject();
        if (selected == null) {
            boltUI.setSelectedObjects(selectedObjectIds, -1, "", 0, 0);
            return;
        }
        boltUI.setSelectedObjects(selectedObjectIds, selected.id,
            selected.name, selected.spinSpeed, selected.color);
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

    static function main():Void {
        new Main();
    }
}
